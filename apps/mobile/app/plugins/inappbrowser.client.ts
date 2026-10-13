/**
 * 沉浸式内嵌浏览器事件桥（移动原生平台）
 *
 * 监听原生 HostRuntime 插件的 detailRequested 事件：
 * 用户在浏览器详情面板点「查看评价」时，原生侧将浏览器「暂停」
 * （收起但保留 WebView 状态），这里负责跳转到站内应用详情页
 * （含评分与评论区）；在详情页再次打开同一应用时原生侧会直接恢复会话。
 */
import { Capacitor } from '@capacitor/core'
import { HostRuntime } from '~/host-runtime'

export default defineNuxtPlugin(() => {
  if (!Capacitor.isNativePlatform() || !Capacitor.isPluginAvailable('HostRuntime'))
    return

  HostRuntime.addListener('detailRequested', ({ appId }) => {
    if (appId)
      useRouter().push(`/app/${appId}`)
  })
})
