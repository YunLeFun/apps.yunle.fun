import type { CapacitorBarcodeScannerScanResult } from '@capacitor/barcode-scanner'
import {
  CapacitorBarcodeScanner,
  CapacitorBarcodeScannerCameraDirection,
  CapacitorBarcodeScannerTypeHintALLOption,
} from '@capacitor/barcode-scanner'

export function useBarcodeScan() {
  const isScanning = ref(false)

  /**
   * 开始扫描
   * 用户主动取消时返回 null 而非抛错
   */
  async function startScan(): Promise<CapacitorBarcodeScannerScanResult | null> {
    try {
      isScanning.value = true

      const result = await CapacitorBarcodeScanner.scanBarcode({
        hint: CapacitorBarcodeScannerTypeHintALLOption.ALL,
        cameraDirection: CapacitorBarcodeScannerCameraDirection.BACK,
        scanInstructions: '将二维码或条形码放入框内',
        cancelButtonAccessibilityLabel: '取消扫码',
        torchButtonOnAccessibilityLabel: '关闭手电筒',
        torchButtonOffAccessibilityLabel: '打开手电筒',
      })

      // 检查是否扫描成功
      if (result.ScanResult) {
        return result
      }

      return null
    }
    catch (error: any) {
      // 用户主动取消/关闭摄像头，静默返回 null
      const msg = String(error?.message || error).toLowerCase()
      if (msg.includes('cancel') || msg.includes('dismissed') || msg.includes('aborted')) {
        return null
      }
      console.error('扫描失败:', error)
      throw error
    }
    finally {
      isScanning.value = false
    }
  }

  /**
   * 停止扫描（新版本自动处理）
   */
  async function stopScan() {
    isScanning.value = false
  }

  return {
    isScanning: readonly(isScanning),
    startScan,
    stopScan,
  }
}
