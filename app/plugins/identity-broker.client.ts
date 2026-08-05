import type { HostAuthorizationEvent } from '~/host-runtime'

import { Capacitor } from '@capacitor/core'
import { HostRuntime } from '~/host-runtime'
import {
  HostIdentityBrokerError,
  readIssuedAuthorizationCode,
  validateHostAuthorization,
} from '~/utils/host-identity-broker'

const SSO_ISSUER = 'https://www.yunle.fun'

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

  HostRuntime.addListener(
    'authorizationRequested',
    async (event: HostAuthorizationEvent) => {
      try {
        const request = validateHostAuthorization(event)
        if (request.prompt === 'select_account') {
          await HostRuntime.authorizeWithOtherAccount({
            requestId: event.requestId,
          })
          return
        }
        const { app, auth } = useCloudbase()
        const { data, error } = await auth.getSession()
        const session = data?.session
        const hasCloudBaseSession = !error && !!session?.access_token && !session.user?.is_anonymous
        const userStore = useUserStore()
        const nativeTestSession = userStore.nativeTestSession
        const hasNativeTestSession = !!nativeTestSession
          && nativeTestSession.expiresAt > Date.now()
        if (!hasCloudBaseSession && !hasNativeTestSession) {
          if (nativeTestSession)
            userStore.clearNativeTestSession()
          throw new HostIdentityBrokerError(
            'HOST_AUTH_REQUIRED',
            '请先登录云乐坊',
          )
        }

        if (request.prompt === 'consent') {
          const userInfo = userStore.userInfo
          const accountName = hasCloudBaseSession
            ? userInfo.nickname || userInfo.login || '当前云乐坊账号'
            : nativeTestSession!.account.publicAlias
          const decision = await HostRuntime.confirmAuthorization({
            applicationName: request.applicationName,
            accountName,
          })
          if (decision.choice === 'other') {
            await HostRuntime.authorizeWithOtherAccount({
              requestId: event.requestId,
            })
            return
          }
          if (!decision.allowed) {
            throw new HostIdentityBrokerError(
              'HOST_AUTH_DENIED',
              '用户取消了宿主账号授权',
            )
          }
        }

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
        await HostRuntime.resolveAuthorization({
          requestId: event.requestId,
          result: {
            ok: true,
            code: issued.code,
            issuer: SSO_ISSUER,
            ...(issued.expiresAt ? { expiresAt: issued.expiresAt } : {}),
          },
        })
      }
      catch (cause) {
        const error = cause instanceof HostIdentityBrokerError
          ? cause.code
          : 'HOST_AUTH_FAILED'
        try {
          await HostRuntime.resolveAuthorization({
            requestId: event.requestId,
            error,
          })
        }
        catch {
          // The originating WebView may have closed or the request may have
          // reached its native timeout while CloudBase was responding.
        }
      }
    },
  )
})
