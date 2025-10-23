import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'

/**
 * 在应用内打开网页
 */
export async function openInAppBrowser(
  url: string,
  options?: {
    /** 工具栏颜色 (hex) */
    toolbarColor?: string
    /** 是否显示标题 */
    presentationStyle?: 'fullscreen' | 'popover'
    /** iOS 关闭按钮文字 */
    closeButtonTitle?: string
  },
) {
  if (!Capacitor.isNativePlatform()) {
    // Web 环境下直接打开新窗口
    window.open(url, '_blank')
    return
  }

  await Browser.open({
    url,
    toolbarColor: options?.toolbarColor,
    presentationStyle: options?.presentationStyle || 'fullscreen',
    // iOS 特有配置
    ...(Capacitor.getPlatform() === 'ios' && {
      closeButtonTitle: options?.closeButtonTitle || '关闭',
    }),
  })
}

/**
 * 关闭应用内浏览器
 */
export async function closeInAppBrowser() {
  if (Capacitor.isNativePlatform()) {
    await Browser.close()
  }
}

/**
 * 监听浏览器事件
 */
export function useBrowserEvents() {
  const isOpen = ref(false)

  onMounted(() => {
    // 监听浏览器打开
    Browser.addListener('browserPageLoaded', () => {
      isOpen.value = true
    })

    // 监听浏览器关闭
    Browser.addListener('browserFinished', () => {
      isOpen.value = false
    })
  })

  onUnmounted(() => {
    Browser.removeAllListeners()
  })

  return {
    isOpen,
  }
}
