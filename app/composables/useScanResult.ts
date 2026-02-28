/**
 * 扫码结果处理 composable
 *
 * @description
 * 负责解析扫码内容并执行对应动作：
 * - 应用链接 → 跳转到应用详情
 * - 普通 URL → 打开浏览器
 * - 其他内容 → Toast 提示
 */
export function useScanResult() {
  const router = useRouter()
  const { showInfo } = useToast()

  /**
   * 处理扫码结果
   */
  function handleScanResult(content: string) {
    if (!content)
      return

    if (content.startsWith('http://') || content.startsWith('https://')) {
      const appIdMatch = content.match(/\/app\/(\d+)/)
      if (appIdMatch) {
        router.push(`/app/${appIdMatch[1]}`)
        return
      }
      window.open(content, '_blank')
    }
    else {
      showInfo(`扫码内容：${content}`)
    }
  }

  return {
    handleScanResult,
  }
}
