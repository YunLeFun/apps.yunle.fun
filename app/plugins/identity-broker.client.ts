import type { HostAuthorizationEvent } from '~/host-runtime'

import { App } from '@capacitor/app'
import { Capacitor } from '@capacitor/core'
import { HostRuntime } from '~/host-runtime'
import {
  anonymizeTelemetryIdentifier,
  reportClientEvent,
} from '~/utils/client-telemetry'
import {
  HostIdentityBrokerError,
  readIssuedAuthorizationCode,
  validateHostAuthorization,
} from '~/utils/host-identity-broker'
import {
  clearNativeAuthorizationLogin,
  NATIVE_AUTHORIZATION_LOGIN_RETURN_TO,
  rememberNativeAuthorizationLogin,
} from '~/utils/native-authorization-login'

const SSO_ISSUER = 'https://www.yunle.fun'

function readHostname(origin: string): string {
  try {
    return new URL(origin).hostname
  }
  catch {
    return ''
  }
}

/**
 * 移动端第一方宿主身份代理。
 *
 * Apps 使用自身 CloudBase 登录态向统一 SSO 云函数申请一个 60 秒、单次使用、
 * 绑定 source origin / client / nonce / PKCE 的 code。页面永远拿不到 Apps 的
 * access token 或 refresh token。
 */
export default defineNuxtPlugin(() => {
  if (!Capacitor.isNativePlatform() || !Capacitor.isPluginAvailable('HostRuntime'))
    return

  let nativeAppVersion = ''
  let nativeBuild = ''
  void App.getInfo().then((info) => {
    nativeAppVersion = info.version
    nativeBuild = info.build
  }).catch(() => undefined)

  HostRuntime.addListener(
    'authorizationRequested',
    async (event: HostAuthorizationEvent) => {
      const startedAt = Date.now()
      const host = readHostname(event.sourceOrigin)
      let clientId = ''
      let flow = ''
      let stage = 'validate'
      const report = (
        name: string,
        context: Record<string, boolean | null | number | string | undefined> = {},
      ) => reportClientEvent(name, {
        appId: event.appId,
        appVersion: nativeAppVersion,
        build: nativeBuild,
        clientId,
        elapsedMs: Date.now() - startedAt,
        flow,
        host,
        requestId: event.requestId,
        stage,
        surface: 'native_sso',
        ...context,
      })

      report('auth.native_sso.requested')
      try {
        const request = validateHostAuthorization(event)
        clientId = request.clientId
        flow = await anonymizeTelemetryIdentifier(request.nonce)
        report('auth.native_sso.validated', { prompt: request.prompt || 'default' })
        if (request.prompt === 'select_account') {
          stage = 'account_selection'
          await HostRuntime.authorizeWithOtherAccount({
            requestId: event.requestId,
          })
          report('auth.native_sso.handed_off', { outcome: 'other_account' })
          return
        }
        const userStore = useUserStore()
        const nativeTestSession = userStore.nativeTestSession
        const hasNativeTestSession = !!nativeTestSession
          && nativeTestSession.expiresAt > Date.now()
        if (nativeTestSession && !hasNativeTestSession)
          userStore.clearNativeTestSession()

        const { app, auth } = useCloudbase()
        let hasCloudBaseSession = false
        if (!hasNativeTestSession) {
          const { data, error } = await auth.getSession()
          const session = data?.session
          hasCloudBaseSession = !error && !!session?.access_token && !session.user?.is_anonymous
        }
        if (!hasCloudBaseSession && !hasNativeTestSession) {
          stage = 'host_login'
          if (!rememberNativeAuthorizationLogin(event.requestId)) {
            throw new HostIdentityBrokerError(
              'HOST_AUTH_FAILED',
              '授权请求标识无效',
            )
          }
          try {
            await HostRuntime.requestHostLogin({ requestId: event.requestId })
          }
          catch (cause) {
            clearNativeAuthorizationLogin(event.requestId)
            throw cause
          }
          report('auth.native_sso.handed_off', { outcome: 'host_login' })
          await navigateTo({
            path: '/login',
            query: { returnTo: NATIVE_AUTHORIZATION_LOGIN_RETURN_TO },
          })
          return
        }

        if (request.prompt === 'consent') {
          stage = 'consent'
          const userInfo = userStore.userInfo
          const accountName = hasCloudBaseSession
            ? userInfo.nickname || userInfo.login || '当前云乐坊账号'
            : nativeTestSession!.account.publicAlias
          report('auth.native_sso.prompted', {
            accountSource: hasCloudBaseSession ? 'cloudbase' : 'native_test',
          })
          const decision = await HostRuntime.confirmAuthorization({
            requestId: event.requestId,
            ...(request.applicationIconUrl
              ? { applicationIconUrl: request.applicationIconUrl }
              : {}),
            applicationName: request.applicationName,
            applicationOrigin: request.applicationOrigin,
            accountName,
            ...(hasCloudBaseSession && userInfo.avatar
              ? { accountAvatarUrl: userInfo.avatar }
              : {}),
            permissionDescription: request.permissionDescription,
            ...(request.authorizationNotice
              ? { authorizationNotice: request.authorizationNotice }
              : {}),
          })
          report('auth.native_sso.consent_decided', {
            outcome: decision.choice || (decision.allowed ? 'current' : 'cancel'),
          })
          if (decision.choice === 'other') {
            stage = 'account_selection'
            await HostRuntime.authorizeWithOtherAccount({
              requestId: event.requestId,
            })
            report('auth.native_sso.handed_off', { outcome: 'other_account' })
            return
          }
          if (!decision.allowed) {
            throw new HostIdentityBrokerError(
              'HOST_AUTH_DENIED',
              '用户取消了宿主账号授权',
            )
          }
        }

        stage = 'issue_code'
        const issueRequest = {
          mode: 'redirect' as const,
          clientId: request.clientId,
          targetOrigin: request.targetOrigin,
          returnUrl: request.redirectUri,
          scope: request.scope,
          nonce: request.nonce,
          codeChallenge: request.codeChallenge,
          codeChallengeMethod: 'S256' as const,
        }
        const response = hasCloudBaseSession
          ? await app.callFunction({
              name: 'sso-ticket',
              data: {
                action: 'issueSsoCode',
                ...issueRequest,
              },
            })
          : await useNuxtApp().$api('/api/auth/native-test-session/authorize', {
              method: 'POST',
              body: {
                hostSession: nativeTestSession!.hostSession,
                request: issueRequest,
              },
            })
        const issued = readIssuedAuthorizationCode(response)
        report('auth.native_sso.code_issued', {
          accountSource: hasCloudBaseSession ? 'cloudbase' : 'native_test',
          outcome: 'success',
        })
        stage = 'deliver_code'
        await HostRuntime.resolveAuthorization({
          requestId: event.requestId,
          result: {
            ok: true,
            code: issued.code,
            issuer: SSO_ISSUER,
            ...(issued.expiresAt ? { expiresAt: issued.expiresAt } : {}),
          },
        })
        report('auth.native_sso.completed', { outcome: 'success' })
      }
      catch (cause) {
        const error = cause instanceof HostIdentityBrokerError
          ? cause.code
          : 'HOST_AUTH_FAILED'
        report('auth.native_sso.failed', {
          error,
          outcome: error === 'HOST_AUTH_DENIED' ? 'denied' : 'failed',
        })
        try {
          await HostRuntime.resolveAuthorization({
            requestId: event.requestId,
            error,
          })
        }
        catch {
          // The originating WebView may have closed or the request may have
          // reached its native timeout while CloudBase was responding.
          report('auth.native_sso.delivery_expired', { outcome: 'failed' })
        }
      }
    },
  )
})
