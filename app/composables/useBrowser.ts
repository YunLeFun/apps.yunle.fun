import type { PluginListenerHandle } from '@capacitor/core'
import type { ExternalLinkMode } from '~/stores/settings'
import { Browser } from '@capacitor/browser'
import { Capacitor, registerPlugin } from '@capacitor/core'
import { NATIVE_API_BASE_URL } from '~/constants/api'

/** 传递给原生详情面板的应用元信息 */
export interface InAppWebViewAppInfo {
  id?: string
  /** URL slug（评价数据以 slug 优先作为 key） */
  slug?: string
  name?: string
  emoji?: string
  logo?: string
  themeColor?: string
  description?: string
  category?: string
  rating?: number
  /** 评价条数（打开后异步补充） */
  ratingCount?: number
}

interface InAppWebViewAuthContext {
  accessToken: string
  refreshToken?: string
  apiBaseUrl: string
}

/** 后台保活会话摘要（原生 sessionsChanged 事件 / listSessions 返回） */
export interface BackgroundSession {
  /** 应用 id（第三方外链应用可能为空） */
  id: string
  /** 去重 / 操作键：优先 appId，无则 URL */
  key: string
  name: string
  emoji?: string
  logo?: string
  themeColor?: string
  url: string
  title?: string
  displayMode?: 'immersive' | 'titlebar'
}

interface InAppWebViewPlugin {
  open: (options: {
    url: string
    title?: string
    toolbarColor?: string
    app?: InAppWebViewAppInfo
    /** 展示形态：titlebar = 顶部固定标题栏（默认，套用主题色 + 单菜单按钮）；immersive = 全屏平铺 + 悬浮胶囊（官方应用声明专属） */
    displayMode?: 'immersive' | 'titlebar'
    /** 跨站外链打开方式：safari-view = App 内系统浏览器视图；default-browser = 跳出到手机默认浏览器 */
    externalLinkMode?: ExternalLinkMode
    /**
     * 本次会话追加的 JSAPI 授信域（可注册域，子域自动匹配，要求 https）。
     * 授信页面可调用敏感 JSAPI（如 setClipboard），详见 docs/dev/in-app-browser.md；
     * 内置已授信 yunle.fun 及其子域，仅对人工核验过的第三方应用传入
     */
    trustedHosts?: string[]
    /**
     * 宿主登录上下文。只传给云乐坊自定义容器，由原生 JSAPI 用它向服务端签发
     * 短期授权码；不会直接暴露给被打开网页。
     */
    auth?: InAppWebViewAuthContext
  }) => Promise<void>
  close: () => Promise<void>
  /** 浏览器已打开时增量更新应用元信息（如评价数） */
  updateAppInfo: (options: { app: InAppWebViewAppInfo }) => Promise<void>
  /** 当前后台保活会话列表 */
  listSessions: () => Promise<{ sessions: BackgroundSession[] }>
  /** 彻底结束并释放指定会话（按 key 传入） */
  endSession: (options: { id: string }) => Promise<void>
  addListener: ((event: 'browserFinished', handler: () => void) => Promise<PluginListenerHandle>) & ((event: 'detailRequested', handler: (data: { appId: string }) => void) => Promise<PluginListenerHandle>) & ((event: 'sessionsChanged', handler: (data: { sessions: BackgroundSession[] }) => void) => Promise<PluginListenerHandle>)
  removeAllListeners: () => Promise<void>
}

export const InAppWebView = registerPlugin<InAppWebViewPlugin>('InAppWebView')

/**
 * 在应用内打开网页
 *
 * iOS: 自定义 WKWebView，默认标题栏形态（顶部固定导航栏，套用应用主题色，右上角单菜单按钮）；
 *      沉浸形态（全屏平铺 + 悬浮胶囊）仅由官方应用经目录声明 displayMode 启用；
 *      容器内点击跨站外链时按设置以 App 内系统浏览器视图（默认）或手机默认浏览器打开
 * 其他平台: @capacitor/browser 原有行为
 */
export async function openInAppBrowser(
  url: string,
  options?: {
    /** 顶部显示的站点名称，不传则自动读取页面 <title> */
    title?: string
    /** 工具栏颜色 (hex) */
    toolbarColor?: string
    presentationStyle?: 'fullscreen' | 'popover'
    /**
     * 应用目录声明的展示形态（YlfAppInfo.displayMode），优先于用户全局设置；
     * 用户全局选「手机内置」时整体退出自定义容器，声明不生效
     */
    displayMode?: 'immersive' | 'titlebar'
    /** 应用元信息（自定义容器详情面板展示：图标/评分/简介等） */
    app?: InAppWebViewAppInfo
    /**
     * 本次会话追加的 JSAPI 授信域（敏感 JSAPI 鉴权，仅沉浸/标题栏模式生效）。
     * 内置已授信 yunle.fun 及其子域，仅对人工核验过的第三方应用传入
     */
    trustedHosts?: string[]
  },
) {
  if (!Capacitor.isNativePlatform()) {
    window.open(url, '_blank')
    return
  }

  if (Capacitor.getPlatform() === 'ios') {
    const { inAppBrowserMode, externalLinkMode } = useSettingsStore()
    if (inAppBrowserMode !== 'system') {
      try {
        await InAppWebView.open({
          url,
          title: options?.title ?? '',
          toolbarColor: options?.toolbarColor,
          app: options?.app,
          // 形态优先级：应用目录声明 > 用户全局设置
          displayMode: options?.displayMode ?? inAppBrowserMode,
          externalLinkMode,
          trustedHosts: options?.trustedHosts,
          auth: await resolveAuthContext(),
        })
        refreshReviewMeta(options?.app)
        return
      }
      catch (e) {
        console.warn('[useBrowser] InAppWebView.open failed, falling back to Browser:', e)
        // fall through to @capacitor/browser below
      }
    }
    // system 模式或自定义容器降级
    // closeButtonTitle 已在 @capacitor/browser 8 移除，关闭按钮文案由系统控制
    await Browser.open({
      url,
      toolbarColor: options?.toolbarColor,
      presentationStyle: options?.presentationStyle || 'fullscreen',
    })
    return
  }

  // Android / other
  await Browser.open({
    url,
    toolbarColor: options?.toolbarColor,
    presentationStyle: options?.presentationStyle || 'fullscreen',
  })
}

async function resolveAuthContext(): Promise<InAppWebViewAuthContext | undefined> {
  let userStore: ReturnType<typeof useUserStore>
  try {
    userStore = useUserStore()
  }
  catch {
    return undefined
  }

  if (!userStore.isLoggedIn && !userStore.accessToken)
    return undefined

  let sessionAccessToken = ''
  try {
    const { ensureValidToken } = useCloudbaseAuth()
    const valid = await ensureValidToken()
    if (valid) {
      const { auth } = useCloudbase()
      const { data } = await auth.getSession()
      const session = data?.session
      if (session?.access_token)
        sessionAccessToken = String(session.access_token)
      if (session?.refresh_token) {
        return {
          accessToken: String(sessionAccessToken || userStore.accessToken || ''),
          refreshToken: String(session.refresh_token),
          apiBaseUrl: resolveNativeApiBaseUrl(),
        }
      }
    }
  }
  catch {
    // 保持打开流程不中断；后续 JSAPI 会按未登录处理。
  }

  const accessToken = String(sessionAccessToken || userStore.accessToken || '')
  if (!accessToken)
    return undefined

  return {
    accessToken,
    apiBaseUrl: resolveNativeApiBaseUrl(),
  }
}

function resolveNativeApiBaseUrl(): string {
  const config = useRuntimeConfig()
  const configured = typeof config.public.apiBaseUrl === 'string'
    ? config.public.apiBaseUrl.trim()
    : ''
  if (configured)
    return configured.replace(/\/$/, '')

  const isPackagedNative = typeof window !== 'undefined'
    && Capacitor.isNativePlatform()
    && window.location.hostname === 'localhost'
  if (isPackagedNative)
    return NATIVE_API_BASE_URL

  return typeof window !== 'undefined' ? window.location.origin : ''
}

/**
 * 打开后异步拉取评价摘要，推给原生详情面板（不阻塞打开）
 */
function refreshReviewMeta(app?: InAppWebViewAppInfo) {
  // 评价 key 与站内详情页一致：slug 优先
  const appKey = app?.slug || app?.id
  if (!appKey)
    return

  try {
    const { $api } = useNuxtApp()
    $api<{ code: number, data: { summary: { average: number, count: number } } }>('/api/reviews', {
      query: { appKey },
    }).then((res) => {
      const summary = res?.data?.summary
      if (!summary)
        return
      return InAppWebView.updateAppInfo({
        app: {
          // 有真实评价时用动态均分覆盖目录里的静态评分
          rating: summary.count > 0 ? summary.average : app?.rating,
          ratingCount: summary.count,
        },
      })
    }).catch(() => {})
  }
  catch {
    // Nuxt 上下文不可用（如单测环境），跳过补充
  }
}

/**
 * 关闭应用内浏览器
 */
export async function closeInAppBrowser() {
  if (!Capacitor.isNativePlatform())
    return

  if (Capacitor.getPlatform() === 'ios') {
    await InAppWebView.close()
    return
  }

  await Browser.close()
}

/**
 * 监听浏览器事件
 */
export function useBrowserEvents() {
  const isOpen = ref(false)

  onMounted(async () => {
    const useCustom = Capacitor.getPlatform() === 'ios'
      && useSettingsStore().inAppBrowserMode !== 'system'

    if (useCustom) {
      await InAppWebView.addListener('browserFinished', () => {
        isOpen.value = false
      })
    }
    else {
      Browser.addListener('browserPageLoaded', () => {
        isOpen.value = true
      })
      Browser.addListener('browserFinished', () => {
        isOpen.value = false
      })
    }
  })

  onUnmounted(async () => {
    const useCustom = Capacitor.getPlatform() === 'ios'
      && useSettingsStore().inAppBrowserMode !== 'system'

    if (useCustom)
      await InAppWebView.removeAllListeners()
    else
      Browser.removeAllListeners()
  })

  return { isOpen }
}
