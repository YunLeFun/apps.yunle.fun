import type { HostAuthorizationEvent } from '~/composables/useBrowser'

import { Capacitor } from '@capacitor/core'
import { InAppWebView } from '~/composables/useBrowser'
import {
  HostIdentityBrokerError,
  readIssuedAuthorizationCode,
  validateHostAuthorization,
} from '~/utils/host-identity-broker'

const SSO_ISSUER = 'https://www.yunle.fun'

/**
 * iOS 宿主身份代理。
 *
 * Apps 使用自身 CloudBase 登录态向统一 SSO 云函数申请一个 60 秒、单次使用、
 * 绑定 source origin / client / nonce / PKCE 的 code。页面永远拿不到 Apps 的
 * access token 或 refresh token。
 */
export default defineNuxtPlugin(() => {
  if (!Capacitor.isNativePlatform() || Capacitor.getPlatform() !== 'ios')
    return

  InAppWebView.addListener(
    'authorizationRequested',
    async (event: HostAuthorizationEvent) => {
      try {
        const request = validateHostAuthorization(event)
        const { app, auth } = useCloudbase()
        const { data, error } = await auth.getSession()
        const session = data?.session
        if (error || !session?.access_token || session.user?.is_anonymous) {
          throw new HostIdentityBrokerError(
            'HOST_AUTH_REQUIRED',
            '请先登录云乐坊',
          )
        }

        const response = await app.callFunction({
          name: 'sso-ticket',
          data: {
            action: 'issueSsoCode',
            clientId: request.clientId,
            mode: 'redirect',
            targetOrigin: request.targetOrigin,
            returnUrl: request.redirectUri,
            scope: request.scope,
            nonce: request.nonce,
            codeChallenge: request.codeChallenge,
            codeChallengeMethod: 'S256',
          },
        })
        const issued = readIssuedAuthorizationCode(response)
        await InAppWebView.resolveAuthorization({
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
          await InAppWebView.resolveAuthorization({
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
