/**
 * Deeplink 处理插件（仅客户端 + 原生平台）
 * 监听 Capacitor URL 事件，并补处理冷启动 URL。
 *
 * 目前支持：
 * - yunlefun://auth/callback?code=xxx&state=xxx → OAuth 登录回调
 * - yunlefun://wallet → 钱包页（www 支付成功后「返回云乐坊」备用回流）
 * - yunlefun://workshop/EJ83N5 → 个人工坊
 * - https://apps.yunle.fun/w/EJ83N5 → Universal Link 个人工坊
 */
import { App } from '@capacitor/app'
import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'
import { resolveNativeDeepLink } from '~/utils/nativeDeepLink'

export default defineNuxtPlugin(() => {
  if (!Capacitor.isNativePlatform())
    return

  const router = useRouter()
  let lastHandledUrl = ''
  let lastHandledAt = 0

  async function handleAppUrl(url: string) {
    // eslint-disable-next-line no-console
    console.debug('[Deeplink] 收到 URL:', url)

    try {
      const target = resolveNativeDeepLink(url)
      if (!target)
        return

      const now = Date.now()
      if (url === lastHandledUrl && now - lastHandledAt < 2000)
        return
      lastHandledUrl = url
      lastHandledAt = now

      if (target.closeBrowser)
        await Browser.close().catch(() => {})

      if (target.type === 'oauth-callback') {
        const { handleNativeOAuthCallback } = useCloudbaseAuth()
        await handleNativeOAuthCallback(target.code, target.state)
        return
      }

      await router.isReady()
      if (router.currentRoute.value.fullPath !== target.path)
        await router.push(target.path)
    }
    catch (err) {
      console.error('[Deeplink] 处理失败:', err)
    }
  }

  void App.addListener('appUrlOpen', ({ url }) => {
    void handleAppUrl(url)
  }).catch((err) => {
    console.error('[Deeplink] 监听注册失败:', err)
  })

  void App.getLaunchUrl().then((launch) => {
    if (launch?.url)
      return handleAppUrl(launch.url)
  }).catch((err) => {
    console.error('[Deeplink] 冷启动 URL 读取失败:', err)
  })
})
