import { hostEnvironment, HostRuntime } from '~/host-runtime'
/**
 * 沉浸式内嵌浏览器事件桥（移动原生平台）
 *
 * browserMinimized：收起回云居，展示当前原生会话的悬浮卡片。
 * detailRequested：
 * 用户在浏览器详情面板点「查看评价」时，原生侧将浏览器「暂停」
 * （收起但保留 WebView 状态），这里负责跳转到站内应用详情页
 * （含评分与评论区）；在详情页再次打开同一应用时原生侧会直接恢复会话。
 */

export default defineNuxtPlugin(() => {
  if (!hostEnvironment.isNative() || !hostEnvironment.hasRuntime())
    return

  const router = useRouter()
  // 在所有入口打开网页前注册会话监听，包含寻乐 / 工坊 / 详情页。
  useBackgroundSessions()

  HostRuntime.addListener('browserMinimized', async () => {
    await router.isReady()
    if (router.currentRoute.value.path !== '/tabs/home')
      await router.replace('/tabs/home')
  })

  HostRuntime.addListener('detailRequested', ({ appId }) => {
    if (appId)
      router.push(`/app/${appId}`)
  })
})
