import type { HostSession } from '~/host-runtime'
import { Capacitor } from '@capacitor/core'
import { openInAppBrowser } from '~/composables/useBrowser'
import { HostRuntime } from '~/host-runtime'

/**
 * useBackgroundSessions - 后台保活会话（压后台的应用网站）
 *
 * 原生侧按平台能力保活 WebView（iOS 支持多个 LRU 会话，Android 首版支持当前会话），
 * 通过 sessionsChanged 事件 + listSessions 暴露给前端。本组合式以模块级单例维护
 * 一份共享列表，供「正在运行」区与悬浮球/托盘复用，监听器随 App 生命周期常驻。
 *
 * - resume：按 session key 恢复原生实例（保留滚动/表单/登录态）；
 * - end：调用原生 endSession 彻底释放该会话。
 *
 * 原生监听随主壳生命周期常驻；Web 列表为空，「手机内置」模式不展示悬浮卡片。
 */

const sessions = ref<HostSession[]>([])
const minimizedKey = ref<string | null>(null)
let initialized = false

/** 是否运行在平台自定义容器（沉浸/标题栏）模式。 */
function isCustomContainer(): boolean {
  if (!import.meta.client || !Capacitor.isNativePlatform())
    return false
  try {
    return useSettingsStore().inAppBrowserMode !== 'system'
  }
  catch {
    return false
  }
}

async function ensureInit() {
  if (initialized || !import.meta.client || !Capacitor.isNativePlatform())
    return
  initialized = true
  try {
    // 监听器随 App 生命周期常驻，无需保存移除句柄
    await HostRuntime.addListener('sessionsChanged', (data) => {
      sessions.value = data?.sessions ?? []
      if (!sessions.value.some(s => s.key === minimizedKey.value))
        minimizedKey.value = null
    })
    await HostRuntime.addListener('browserMinimized', (data) => {
      minimizedKey.value = data?.key ?? null
    })
    const { sessions: list } = await HostRuntime.listSessions()
    sessions.value = list ?? []
  }
  catch {
    // 旧版本原生不支持（无 listSessions / 事件）：保持空列表，UI 自然隐藏
  }
}

export function useBackgroundSessions() {
  if (import.meta.client)
    ensureInit()

  /** 恢复（再次打开命中暂停会话即秒恢复） */
  async function resume(session: HostSession) {
    try {
      await HostRuntime.resumeSession({ id: session.key })
    }
    catch (error) {
      // Web assets can update before the native binary. Only old plugins fall back.
      if ((error as { code?: string }).code !== 'UNIMPLEMENTED')
        throw error
      await openInAppBrowser(session.url, {
        title: session.title || session.name,
        displayMode: session.displayMode,
        app: { id: session.id || session.key, name: session.name, emoji: session.emoji, logo: session.logo, themeColor: session.themeColor },
      })
    }
    if (minimizedKey.value === session.key)
      minimizedKey.value = null
  }

  /** 结束并释放该后台会话 */
  async function end(session: HostSession) {
    await HostRuntime.endSession({ id: session.key })
    sessions.value = sessions.value.filter(s => s.key !== session.key)
    if (minimizedKey.value === session.key)
      minimizedKey.value = null
  }

  /** 一键清理：结束并释放全部后台会话 */
  async function clearAll() {
    const all = sessions.value.slice()
    sessions.value = []
    for (const s of all) {
      try {
        await HostRuntime.endSession({ id: s.key })
      }
      catch {}
    }
  }

  /** 主动拉取一次（如页面进入前台时） */
  async function refresh() {
    if (!isCustomContainer())
      return
    try {
      const { sessions: list } = await HostRuntime.listSessions()
      sessions.value = list ?? []
    }
    catch {}
  }

  return { sessions: readonly(sessions), minimizedKey: readonly(minimizedKey), resume, end, clearAll, refresh }
}
