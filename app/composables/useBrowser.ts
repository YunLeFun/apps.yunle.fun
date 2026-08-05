import type { HostAppInfo } from '~/host-runtime'
import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'
import { HostRuntime } from '~/host-runtime'

export type {
  HostSession as BackgroundSession,
  HostAuthorizationEvent,
  HostAuthorizationRequest,
} from '~/host-runtime'

/** 传递给原生详情面板的应用元信息 */
export type InAppWebViewAppInfo = HostAppInfo

/** Catalog fields required to launch an app without losing its trusted identity. */
export interface CatalogBrowserApp extends InAppWebViewAppInfo {
  websiteUrl: string
  displayMode?: 'immersive' | 'titlebar'
  trustedHosts?: string[]
}

export interface InAppBrowserOptions {
  /** 顶部显示的站点名称，不传则自动读取页面 <title> */
  title?: string
  /** 工具栏颜色 (hex) */
  toolbarColor?: string
  presentationStyle?: 'fullscreen' | 'popover'
  /** 应用目录声明优先于用户全局设置。 */
  displayMode?: 'immersive' | 'titlebar'
  /** 应用元信息（自定义容器详情面板与宿主授权使用）。 */
  app?: InAppWebViewAppInfo
  /** 经人工核验、允许调用授信 JSAPI 的可注册域名。 */
  trustedHosts?: string[]
}

/**
 * Opens one catalog app with the stable slug/id and display metadata required
 * by the native identity broker. Generic links should use openInAppBrowser.
 */
export function openCatalogAppInBrowser(app: CatalogBrowserApp): Promise<void> {
  const appId = app.slug || app.id
  if (!appId)
    throw new TypeError('Catalog app requires a stable slug or id')
  return openInAppBrowser(app.websiteUrl, {
    title: app.name,
    displayMode: app.displayMode,
    app: {
      id: appId,
      slug: app.slug,
      name: app.name,
      emoji: app.emoji,
      logo: app.logo,
      themeColor: app.themeColor,
      description: app.description,
      category: app.category,
      rating: app.rating,
    },
    trustedHosts: app.trustedHosts,
  })
}

/**
 * 在应用内打开网页
 *
 * iOS / Android: 平台原生 WebView，默认标题栏形态；
 *      沉浸形态（全屏平铺 + 悬浮胶囊）仅由官方应用经目录声明 displayMode 启用；
 *      容器内点击跨站外链时按设置以 App 内系统浏览器视图（默认）或手机默认浏览器打开
 * 「手机内置」模式使用 @capacitor/browser。
 */
export async function openInAppBrowser(
  url: string,
  options?: InAppBrowserOptions,
) {
  if (!Capacitor.isNativePlatform()) {
    window.open(url, '_blank')
    return
  }

  const { inAppBrowserMode, externalLinkMode } = useSettingsStore()
  if (inAppBrowserMode !== 'system') {
    try {
      await HostRuntime.open({
        url,
        title: options?.title ?? '',
        toolbarColor: options?.toolbarColor,
        app: options?.app,
        // 形态优先级：应用目录声明 > 用户全局设置
        displayMode: options?.displayMode ?? inAppBrowserMode,
        externalLinkMode,
        trustedHosts: options?.trustedHosts,
      })
      refreshReviewMeta(options?.app)
      return
    }
    catch (e) {
      console.warn('[useBrowser] HostRuntime.open failed, falling back to Browser:', e)
      // fall through to @capacitor/browser below
    }
  }

  // system 模式或自定义容器降级
  await Browser.open({
    url,
    toolbarColor: options?.toolbarColor,
    presentationStyle: options?.presentationStyle || 'fullscreen',
  })
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
      return HostRuntime.updateAppInfo({
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

  if (useSettingsStore().inAppBrowserMode !== 'system') {
    await HostRuntime.close()
    return
  }

  await Browser.close()
}

/** 清理原生容器中由宿主身份派生的第一方应用会话。 */
export async function clearInAppBrowserIdentitySessions() {
  if (!Capacitor.isNativePlatform()) {
    return
  }
  await HostRuntime.clearIdentitySessions()
}

/**
 * 监听浏览器事件
 */
export function useBrowserEvents() {
  const isOpen = ref(false)

  onMounted(async () => {
    const useCustom = Capacitor.isNativePlatform()
      && useSettingsStore().inAppBrowserMode !== 'system'

    if (useCustom) {
      await HostRuntime.addListener('browserFinished', () => {
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
    const useCustom = Capacitor.isNativePlatform()
      && useSettingsStore().inAppBrowserMode !== 'system'

    if (useCustom)
      await HostRuntime.removeAllListeners()
    else
      Browser.removeAllListeners()
  })

  return { isOpen }
}
