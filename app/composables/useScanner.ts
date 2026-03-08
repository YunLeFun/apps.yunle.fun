/**
 * 统一扫码 composable
 *
 * @description
 * 封装扫码完整流程：环境判断、启动扫码、处理结果、关闭清理。
 * - Native 环境调用 Capacitor 插件
 * - Web 环境打开 BarcodeScanner 组件
 * - 支持从相册选择图片解码二维码
 * - 用户主动取消时静默处理，不抛错
 */
export function useScanner() {
  const showScanner = ref(false)
  const { startScan: startNativeScan, stopScan: stopNativeScan, isScanning } = useBarcodeScan()
  const { showError, showWarning } = useToast()

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
   * 从相册选择图片并解码二维码
   * @returns 解码结果字符串或 null
   */
  async function scanFromAlbum(): Promise<string | null> {
    try {
      const file = await pickImageFile()
      if (!file)
        return null

      const imageData = await loadImageData(file)
      const jsQR = (await import('jsqr')).default
      const result = jsQR(imageData.data, imageData.width, imageData.height)

      if (result?.data) {
        return result.data
      }

      showWarning('未识别到二维码，请选择包含二维码的图片')
      return null
    }
    catch (error: any) {
      console.error('相册扫码失败:', error)
      showError('图片识别失败，请重试')
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
    /** 从相册选择图片扫码 */
    scanFromAlbum,
    /** 关闭扫码 */
    closeScanner,
  }
}

/**
 * 判断错误是否为用户主动取消
 */
function isUserCancelled(error: any): boolean {
  if (!error)
    return false
  const msg = String(error.message || error).toLowerCase()
  return msg.includes('cancel')
    || msg.includes('user denied')
    || msg.includes('permission')
    || msg.includes('dismissed')
    || msg.includes('aborted')
}

/**
 * 弹出系统文件选择器，限定图片类型
 * 用户取消时返回 null
 */
function pickImageFile(): Promise<File | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/*'
    input.style.display = 'none'

    input.addEventListener('change', () => {
      const file = input.files?.[0] ?? null
      input.remove()
      resolve(file)
    })

    // 用户取消文件选择时 change 不触发，通过 focus 回退检测
    const handleFocus = () => {
      setTimeout(() => {
        if (!input.files?.length) {
          input.remove()
          resolve(null)
        }
        window.removeEventListener('focus', handleFocus)
      }, 300)
    }
    window.addEventListener('focus', handleFocus)

    document.body.appendChild(input)
    input.click()
  })
}

/**
 * 将图片文件加载为 ImageData（RGBA 像素数据）
 */
function loadImageData(file: File): Promise<ImageData> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => {
      const canvas = document.createElement('canvas')
      canvas.width = img.width
      canvas.height = img.height
      const ctx = canvas.getContext('2d')
      if (!ctx) {
        reject(new Error('无法创建 Canvas 上下文'))
        return
      }
      ctx.drawImage(img, 0, 0)
      resolve(ctx.getImageData(0, 0, img.width, img.height))
    }
    img.onerror = () => reject(new Error('图片加载失败'))
    img.src = URL.createObjectURL(file)
  })
}
