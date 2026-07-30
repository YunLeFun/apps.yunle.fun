import type { BackgroundSession } from '~/composables/useBrowser'
import { Capacitor } from '@capacitor/core'
import { InAppWebView, openInAppBrowser } from '~/composables/useBrowser'

/** 首次最小化时一次性顶部轻提示，教用户去左上角入口找回（之后不再打扰） */
function coachMinimizeOnce(name?: string) {
  if (!import.meta.client)
    return
  const KEY = 'ylf:bg-minimize-coached'
  try {
    if (localStorage.getItem(KEY))
      return
    localStorage.setItem(KEY, '1')
  }
  catch {}
  useToast().showInfo(name ? `「${name}」已转入后台，点左上角可恢复` : '已转入后台，点左上角可恢复')
}

/**
 * useBackgroundSessions - 后台保活会话（压后台的应用网站）
 *
 * 原生侧（iOS 自定义容器）按 appId 保活多个已最小化的 WebView（LRU 上限 3），
 * 通过 sessionsChanged 事件 + listSessions 暴露给前端。本组合式以模块级单例维护
 * 一份共享列表，供「正在运行」区与悬浮球/托盘复用，监听器随 App 生命周期常驻。
 *
 * - resume：再次走 openInAppBrowser，命中暂停会话即秒恢复（保留滚动/表单/登录态）；
 * - end：调用原生 endSession 彻底释放该会话。
 *
 * 仅在 iOS 自定义容器模式下生效；其他平台/「手机内置」模式下列表恒为空。
 */

const sessions = ref<BackgroundSession[]>([])
let initialized = false

/** 是否运行在 iOS 自定义容器（沉浸/标题栏）模式 */
function isCustomContainer(): boolean {
  if (!import.meta.client || Capacitor.getPlatform() !== 'ios')
    return false
  try {
    return useSettingsStore().inAppBrowserMode !== 'system'
  }
  catch {
    return false
  }
}

async function ensureInit() {
  if (initialized || !isCustomContainer())
    return
  initialized = true
  try {
    const { sessions: list } = await InAppWebView.listSessions()
    sessions.value = list ?? []
    // 监听器随 App 生命周期常驻，无需保存移除句柄
    await InAppWebView.addListener('sessionsChanged', (data) => {
      sessions.value = data?.sessions ?? []
    })
    await InAppWebView.addListener('browserMinimized', (data) => {
      coachMinimizeOnce(data?.name)
    })
  }
  catch {
    // 旧版本原生不支持（无 listSessions / 事件）：保持空列表，UI 自然隐藏
  }
}

export function useBackgroundSessions() {
  if (import.meta.client)
    ensureInit()

  /** 恢复（再次打开命中暂停会话即秒恢复） */
  async function resume(session: BackgroundSession) {
    await openInAppBrowser(session.url, {
      title: session.title || session.name,
      displayMode: session.displayMode,
      app: {
        id: session.id || session.key,
        name: session.name,
        emoji: session.emoji,
        logo: session.logo,
        themeColor: session.themeColor,
      },
    })
  }

  /** 结束并释放该后台会话 */
  async function end(session: BackgroundSession) {
    // 乐观更新，原生 sessionsChanged 会再兜底刷新
    sessions.value = sessions.value.filter(s => s.key !== session.key)
    try {
      await InAppWebView.endSession({ id: session.key })
    }
    catch {
      // 调用失败时回到原生真相
      void refresh()
    }
  }

  /** 一键清理：结束并释放全部后台会话 */
  async function clearAll() {
    const all = sessions.value.slice()
    sessions.value = []
    for (const s of all) {
      try {
        await InAppWebView.endSession({ id: s.key })
      }
      catch {}
    }
  }

  /** 主动拉取一次（如页面进入前台时） */
  async function refresh() {
    if (!isCustomContainer())
      return
    try {
      const { sessions: list } = await InAppWebView.listSessions()
      sessions.value = list ?? []
    }
    catch {}
  }

  return { sessions: readonly(sessions), resume, end, clearAll, refresh }
}
