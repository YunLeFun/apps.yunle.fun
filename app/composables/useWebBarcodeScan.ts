/**
 * Web 端条码扫描（使用浏览器 API）
 * 作为 Capacitor 插件的备用方案
 */
export function useWebBarcodeScan() {
  const isScanning = ref(false)
  const videoElement = ref<HTMLVideoElement | null>(null)
  const stream = ref<MediaStream | null>(null)

  /**
   * 检查浏览器是否支持相机
   */
  function isSupported(): boolean {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)
  }

  /**
   * 请求相机权限并开始扫描
   */
  async function startScan(video: HTMLVideoElement): Promise<void> {
    if (!isSupported()) {
      throw new Error('当前浏览器不支持相机功能')
    }

    try {
      isScanning.value = true
      videoElement.value = video

      // 请求相机权限
      stream.value = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: 'environment', // 使用后置摄像头
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      })

      // 将视频流绑定到 video 元素
      video.srcObject = stream.value
      await video.play()
    }
    catch (error) {
      isScanning.value = false
      console.error('启动相机失败:', error)
      throw error
    }
  }

  /**
   * 停止扫描
   * 优雅地关闭摄像头，不抛出错误
   */
  function stopScan(): void {
    try {
      if (stream.value) {
        stream.value.getTracks().forEach((track) => {
          try {
            track.stop()
          }
          catch {
            // 摄像头 track 已停止或释放，忽略
          }
        })
        stream.value = null
      }

      if (videoElement.value) {
        videoElement.value.srcObject = null
        videoElement.value = null
      }
    }
    catch {
      // 清理过程中出错，静默处理
    }
    finally {
      isScanning.value = false
    }
  }

  /**
   * 从视频帧中检测二维码/条形码
   * 注意：这需要额外的库如 jsQR 或 @zxing/library
   */
  async function detectBarcode(_video: HTMLVideoElement): Promise<string | null> {
    // 这里需要集成条码检测库
    // 例如使用 @zxing/library 或 jsQR
    // 暂时返回 null，需要后续集成
    return null
  }

  // 清理函数
  onUnmounted(() => {
    stopScan()
  })

  return {
    isScanning: readonly(isScanning),
    /** 当前活跃的 MediaStream（供 useTorch 等外部消费） */
    stream,
    isSupported,
    startScan,
    stopScan,
    detectBarcode,
  }
}
