/**
 * 统一扫码 composable
 *
 * @description
 * 封装扫码完整流程：启动扫码、处理结果、关闭清理。
 * - 统一使用 BarcodeScanner 组件（基于 getUserMedia + jsQR）
 * - 支持从相册选择图片解码二维码
 * - 用户主动取消时静默处理，不抛错
 */
import { Capacitor } from '@capacitor/core'

type AlbumImageSource = File | string

export function useScanner() {
  const showScanner = ref(false)
  const { showError, showWarning } = useToast()

  /**
   * 发起扫码
   * 显示 BarcodeScanner 组件，由组件接管摄像头和 QR 检测
   * 结果通过组件的 result 事件返回
   */
  async function openScanner(): Promise<string | null> {
    showScanner.value = true
    return null
  }

  /**
   * 从相册选择图片并解码二维码
   * @returns 解码结果字符串或 null
   */
  async function scanFromAlbum(): Promise<string | null> {
    try {
      const imageSource = await pickPhotoLibraryImageSource()
      if (!imageSource)
        return null

      const jsQR = (await import('jsqr')).default

      // 先用降采样图识别（大图直接解码慢且成功率低），失败再回退原图
      const downscaled = await loadImageData(imageSource, 1280)
      let result = jsQR(downscaled.imageData.data, downscaled.imageData.width, downscaled.imageData.height)

      if (!result?.data && downscaled.wasScaled) {
        const full = await loadImageData(imageSource)
        result = jsQR(full.imageData.data, full.imageData.width, full.imageData.height)
      }

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
   */
  function closeScanner() {
    showScanner.value = false
  }

  return {
    /** 控制 BarcodeScanner 组件显隐 */
    showScanner: readonly(showScanner),
    /** 打开扫码 */
    openScanner,
    /** 从相册选择图片扫码 */
    scanFromAlbum,
    /** 关闭扫码 */
    closeScanner,
  }
}

async function pickPhotoLibraryImageSource(): Promise<AlbumImageSource | null> {
  if (!Capacitor.isNativePlatform())
    return pickImageFile()

  try {
    return await pickNativePhotoLibraryImageSource()
  }
  catch (error) {
    if (isPhotoPickerCancel(error))
      return null

    throw error
  }
}

async function pickNativePhotoLibraryImageSource(): Promise<string | null> {
  const { Camera, MediaTypeSelection } = await import('@capacitor/camera')
  const { results } = await Camera.chooseFromGallery({
    mediaType: MediaTypeSelection.Photo,
    allowMultipleSelection: false,
    editable: 'no',
    quality: 100,
    correctOrientation: true,
    presentationStyle: 'fullscreen',
  })

  return results[0]?.webPath ?? null
}

function isPhotoPickerCancel(error: unknown): boolean {
  const message = String((error as any)?.message || error).toLowerCase()
  return message.includes('cancel') || message.includes('dismiss') || message.includes('no image')
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

    // 老 WebView 无 cancel 事件时的兜底：窗口重获焦点后长延迟判定取消。
    // iOS 选图后系统需要导出/转码（HEIC 等），change 可能晚于 focus 数秒到达，
    // 延迟必须足够长；change 先到时 settle 已处理（幂等）。
    const handleFocus = () => {
      setTimeout(() => {
        if (!input.files?.length)
          settle(null)
      }, 5000)
    }

    let settled = false
    function settle(file: File | null) {
      if (settled)
        return
      settled = true
      window.removeEventListener('focus', handleFocus)
      input.remove()
      resolve(file)
    }

    input.addEventListener('change', () => {
      settle(input.files?.[0] ?? null)
    })

    // 现代浏览器（iOS 16.4+ / Chrome 113+）取消选择时触发标准 cancel 事件
    input.addEventListener('cancel', () => settle(null))
    if (!('oncancel' in input))
      window.addEventListener('focus', handleFocus, { once: true })

    document.body.appendChild(input)
    input.click()
  })
}

/**
 * 将图片文件加载为 ImageData（RGBA 像素数据）
 * @param source 图片文件或可加载的图片 URL
 * @param maxDimension 最长边上限，超出时等比缩小（不传则按原尺寸）
 */
function loadImageData(source: AlbumImageSource, maxDimension?: number): Promise<{ imageData: ImageData, wasScaled: boolean }> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    const shouldRevokeUrl = source instanceof File
    const url = shouldRevokeUrl ? URL.createObjectURL(source) : source
    img.onload = () => {
      if (shouldRevokeUrl)
        URL.revokeObjectURL(url)
      const scale = maxDimension ? Math.min(1, maxDimension / Math.max(img.width, img.height)) : 1
      const width = Math.max(1, Math.round(img.width * scale))
      const height = Math.max(1, Math.round(img.height * scale))

      const canvas = document.createElement('canvas')
      canvas.width = width
      canvas.height = height
      const ctx = canvas.getContext('2d')
      if (!ctx) {
        reject(new Error('无法创建 Canvas 上下文'))
        return
      }
      ctx.drawImage(img, 0, 0, width, height)
      resolve({ imageData: ctx.getImageData(0, 0, width, height), wasScaled: scale < 1 })
    }
    img.onerror = () => {
      if (shouldRevokeUrl)
        URL.revokeObjectURL(url)
      reject(new Error('图片加载失败'))
    }
    img.src = url
  })
}
