/**
 * 扫码桥接 composable
 *
 * @description
 * 用模块级变量存储回调，提供统一的扫码导航入口。
 * 各调用方只需 `navigateToScan(callback)` 即可跳转到 /scan 页面，
 * 扫码成功后自动返回并执行回调。
 */

// 模块级变量，跨组件共享
let _onResult: ((content: string) => void) | null = null

export function useScanBridge() {
  const router = useRouter()

  /** 导航到扫码页，扫码成功后回调 */
  function navigateToScan(onResult: (content: string) => void) {
    _onResult = onResult
    router.push('/scan')
  }

  /** 扫码页调用：传递结果并返回上一页 */
  function resolveScan(content: string) {
    _onResult?.(content)
    _onResult = null
    router.back()
  }

  /** 扫码页调用：用户取消 */
  function cancelScan() {
    _onResult = null
    router.back()
  }

  return { navigateToScan, resolveScan, cancelScan }
}
