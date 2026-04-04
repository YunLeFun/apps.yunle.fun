import type { AppMarketSource } from '~/types/market'
import { validateMarketSource } from '~/types/market'

// URL 协议检测正则
const HTTP_URL_REGEX = /^https?:\/\//i

/**
 * 扫码添加第三方应用市场
 *
 * 支持两种二维码格式：
 * - URL：fetch 远程 JSON 数据
 * - 直接 JSON：解析二维码中的 JSON 字符串
 */
export function useMarketScan() {
  const store = useMarketSourcesStore()
  const { showSuccess, showError, showWarning } = useToast()
  const loading = ref(false)

  /**
   * 解析扫码内容为 AppMarketSource
   */
  async function parseMarketData(content: string): Promise<AppMarketSource> {
    const trimmed = content.trim()
    let raw: unknown

    // URL 模式：fetch JSON
    if (HTTP_URL_REGEX.test(trimmed)) {
      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(), 10_000)
      try {
        const res = await fetch(trimmed, { signal: controller.signal })
        if (!res.ok)
          throw new Error(`HTTP ${res.status}`)
        raw = await res.json()
      }
      catch (e: any) {
        if (e.name === 'AbortError')
          throw new Error('请求超时，请检查网络')
        throw new Error(`获取数据失败：${e.message}`)
      }
      finally {
        clearTimeout(timer)
      }
    }
    else {
      // JSON 模式：直接解析
      try {
        raw = JSON.parse(trimmed)
      }
      catch {
        throw new Error('无法解析二维码内容，格式无效')
      }
    }

    if (!validateMarketSource(raw))
      throw new Error('数据格式不符合应用市场规范')

    const source = raw as AppMarketSource
    // 补充元数据
    if (!source.id)
      source.id = `market-${Date.now()}`
    if (HTTP_URL_REGEX.test(trimmed))
      source.url = source.url || trimmed
    source.addedAt = source.addedAt || Date.now()

    return source
  }

  /**
   * 处理扫码结果：解析 → 校验 → 添加到 store
   */
  async function handleScanResult(content: string) {
    if (!content)
      return

    loading.value = true
    try {
      const source = await parseMarketData(content)

      // 去重检查
      if (source.url && store.hasSource(source.url)) {
        showWarning('该应用市场已添加')
        return
      }

      const added = store.addSource(source)
      if (added) {
        showSuccess(`已添加「${source.name}」，包含 ${source.apps.length} 个应用`)
      }
      else {
        showWarning('该应用市场已存在')
      }
    }
    catch (e: any) {
      console.warn('[MarketScan] 解析失败:', e.message)
      showError(e.message || '解析失败')
    }
    finally {
      loading.value = false
    }
  }

  return {
    loading: readonly(loading),
    handleScanResult,
  }
}
