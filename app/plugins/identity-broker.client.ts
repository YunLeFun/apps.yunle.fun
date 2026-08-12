import type { HostAuthorizationEvent } from '~/host-runtime'

import { App } from '@capacitor/app'
import { Capacitor } from '@capacitor/core'
import { HostRuntime } from '~/host-runtime'
import {
  anonymizeTelemetryIdentifier,
  reportClientEvent,
} from '~/utils/client-telemetry'
import {
  createHostAuthorizationResolutionRequest,
  HostIdentityBrokerError,
  readIssuedAuthorizationCode,
  readResolvedHostAuthorization,
} from '~/utils/host-identity-broker'
import {
  clearNativeAuthorizationLogin,
  NATIVE_AUTHORIZATION_LOGIN_RETURN_TO,
  rememberNativeAuthorizationLogin,
} from '~/utils/native-authorization-login'

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
      let stage = 'validate_protocol'
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
        const pendingRequest = createHostAuthorizationResolutionRequest(event)
        clientId = pendingRequest.clientId
        flow = await anonymizeTelemetryIdentifier(pendingRequest.nonce)
        stage = 'resolve_policy'
        const policyResponse = await useNuxtApp().$api('/api/auth/sso/resolve', {
          method: 'POST',
          body: pendingRequest,
        })
        const request = readResolvedHostAuthorization(policyResponse, pendingRequest)
        clientId = request.clientId
        report('auth.native_sso.resolved', {
          policyVersion: request.policyVersion,
          prompt: request.prompt || 'default',
        })
        if (request.prompt === 'select_account') {
          stage = 'account_selection'
          await HostRuntime.authorizeWithOtherAccount({
            requestId: event.requestId,
          })
          report('auth.native_sso.handed_off', { outcome: 'other_account' })
          return
        }
        const userStore = useUserStore()
        const { app, auth } = useCloudbase()
        const { data, error } = await auth.getSession()
        const session = data?.session
        const hasCloudBaseSession = !error && !!session?.access_token && !session.user?.is_anonymous
        if (!hasCloudBaseSession) {
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
          const accountName = userInfo.nickname || userInfo.login || '当前云乐坊账号'
          report('auth.native_sso.prompted', {
            accountSource: 'cloudbase',
          })
          const decision = await HostRuntime.confirmAuthorization({
            requestId: event.requestId,
            ...(request.applicationIconUrl
              ? { applicationIconUrl: request.applicationIconUrl }
              : {}),
            applicationName: request.applicationName,
            applicationOrigin: request.applicationOrigin,
            accountName,
            ...(userInfo.avatar
              ? { accountAvatarUrl: userInfo.avatar }
              : {}),
            permissionDescription: request.permissionDescription,
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
        const response = await app.callFunction({
          name: 'sso-ticket',
          data: {
            action: 'issueSsoCode',
            ...request.issueRequest,
          },
        })
        const issued = readIssuedAuthorizationCode(response)
        report('auth.native_sso.code_issued', {
          accountSource: 'cloudbase',
          outcome: 'success',
        })
        stage = 'deliver_code'
        await HostRuntime.resolveAuthorization({
          requestId: event.requestId,
          result: {
            ok: true,
            code: issued.code,
            issuer: request.issuer,
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
