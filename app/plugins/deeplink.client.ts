/**
 * Deeplink 处理插件（仅客户端 + 原生平台）
 * 监听 Capacitor App.appUrlOpen 事件，处理 yunlefun:// 协议的回调
 *
 * 目前支持：
 * - yunlefun://auth/callback?code=xxx&state=xxx → OAuth 登录回调
 * - yunlefun://wallet → 钱包页（www 支付成功后「返回云乐坊」备用回流）
 */
import { App } from '@capacitor/app'
import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'

export default defineNuxtPlugin(() => {
  if (!Capacitor.isNativePlatform())
    return

  App.addListener('appUrlOpen', async ({ url }) => {
    // eslint-disable-next-line no-console
    console.debug('[Deeplink] 收到 URL:', url)

    try {
      const parsed = new URL(url)

      // yunlefun://auth/callback?code=xxx&state=xxx
      if (parsed.hostname === 'auth' && parsed.pathname === '/callback') {
        const code = parsed.searchParams.get('code')
        const state = parsed.searchParams.get('state')

        if (code && state) {
          // 关闭系统浏览器
          await Browser.close().catch(() => {})

          // 调用 OAuth 回调处理
          const { handleNativeOAuthCallback } = useCloudbaseAuth()
          await handleNativeOAuthCallback(code, state)
        }
      }

      // yunlefun://wallet → 回到钱包页（页面 onMounted 会自动对账刷新）
      if (parsed.hostname === 'wallet') {
        await Browser.close().catch(() => {})
        useRouter().push('/wallet')
      }
    }
    catch (err) {
      console.error('[Deeplink] 处理失败:', err)
    }
  })
})
