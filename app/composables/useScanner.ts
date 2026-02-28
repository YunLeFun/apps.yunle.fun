/**
 * 统一扫码 composable
 *
 * @description
 * 封装扫码完整流程：环境判断、启动扫码、处理结果、关闭清理。
 * - Native 环境调用 Capacitor 插件
 * - Web 环境打开 BarcodeScanner 组件
 * - 用户主动取消时静默处理，不抛错
 */
export function useScanner() {
  const showScanner = ref(false)
  const { startScan: startNativeScan, stopScan: stopNativeScan, isScanning } = useBarcodeScan()
  const { showError } = useToast()

  /** 是否运行在 Capacitor 原生环境 */
  function isNativeEnv(): boolean {
    return !!(import.meta.client && (window as any).Capacitor)
  }

  /**
   * 发起扫码
   * - Native 环境直接调用 Capacitor 扫码，返回结果字符串
   * - Web 环境设置 showScanner = true，由 BarcodeScanner 组件接管
   *
   * @returns 原生环境返回扫码内容字符串或 null，Web 环境返回 null（结果通过事件获取）
   */
  async function openScanner(): Promise<string | null> {
    if (!isNativeEnv()) {
      // Web 环境：显示扫码组件
      showScanner.value = true
      return null
    }

    // Native 环境：调用 Capacitor
    try {
      const result = await startNativeScan()
      return result?.ScanResult ?? null
    }
    catch (error: any) {
      // 用户主动取消扫码，静默处理
      if (isUserCancelled(error)) {
        return null
      }
      console.error('扫码失败:', error)
      showError(`扫码失败，请检查相机权限`)
      return null
    }
  }

  /**
   * 关闭扫码
   * 同时清理 Web 和 Native 端资源
   */
  function closeScanner() {
    showScanner.value = false
    if (isScanning.value) {
      stopNativeScan()
    }
  }

  return {
    /** 控制 Web 端 BarcodeScanner 组件显隐 */
    showScanner: readonly(showScanner),
    /** 是否正在扫描（原生端） */
    isScanning,
    /** 打开扫码 */
    openScanner,
    /** 关闭扫码 */
    closeScanner,
  }
}

/**
 * 判断错误是否为用户主动取消
 */
function isUserCancelled(error: any): boolean {
  if (!error) return false
  const msg = String(error.message || error).toLowerCase()
  return msg.includes('cancel')
    || msg.includes('user denied')
    || msg.includes('permission')
    || msg.includes('dismissed')
    || msg.includes('aborted')
}
