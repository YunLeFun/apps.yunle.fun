import type { AppIconAssetRole } from '~/types/app'

export const APP_ICON_CANVAS_SIZE = 1024
export const APP_ICON_MARK_SAFE_RATIO = 0.8
export const APP_ICON_INPUT_MAX_BYTES = 5 * 1024 * 1024

const ACCEPTED_TYPES = new Set(['image/png', 'image/webp', 'image/svg+xml'])
const ACTIVE_SVG_PATTERN = /<(?:script|foreignObject|iframe|object|embed)\b|\son[a-z]+\s*=|(?:href|xlink:href)\s*=\s*["'](?!#)|url\(\s*["']?(?!#)/i

/** 把用户文件转换为后端可验证的 1024px PNG。 */
export async function normalizeAppIconFile(file: File, role: AppIconAssetRole): Promise<File> {
  validateAppIconInput(file)
  if (file.type === 'image/svg+xml')
    validatePassiveSvg(await file.text())

  const image = await loadImage(file)
  if (role === 'app-icon')
    validateNearSquare(image.naturalWidth, image.naturalHeight)

  const sourceCanvas = document.createElement('canvas')
  sourceCanvas.width = APP_ICON_CANVAS_SIZE
  sourceCanvas.height = APP_ICON_CANVAS_SIZE
  const sourceContext = requireContext(sourceCanvas)
  sourceContext.clearRect(0, 0, APP_ICON_CANVAS_SIZE, APP_ICON_CANVAS_SIZE)
  if (role === 'mark') {
    const scale = APP_ICON_CANVAS_SIZE / Math.max(image.naturalWidth, image.naturalHeight)
    const width = image.naturalWidth * scale
    const height = image.naturalHeight * scale
    sourceContext.drawImage(
      image,
      (APP_ICON_CANVAS_SIZE - width) / 2,
      (APP_ICON_CANVAS_SIZE - height) / 2,
      width,
      height,
    )
  }
  else {
    sourceContext.drawImage(image, 0, 0, APP_ICON_CANVAS_SIZE, APP_ICON_CANVAS_SIZE)
  }

  const outputCanvas = role === 'mark' ? normalizeMarkCanvas(sourceCanvas) : sourceCanvas
  const blob = await canvasToPng(outputCanvas)
  return new File([blob], `${role}.png`, { type: 'image/png', lastModified: Date.now() })
}

export function validateAppIconInput(file: Pick<File, 'size' | 'type'>) {
  if (!ACCEPTED_TYPES.has(file.type))
    throw new Error('请选择 PNG、WebP 或 SVG 图片')
  if (file.size <= 0 || file.size > APP_ICON_INPUT_MAX_BYTES)
    throw new Error('图片大小需在 5 MB 以内')
}

export function validatePassiveSvg(source: string) {
  if (!/<svg\b/i.test(source) || ACTIVE_SVG_PATTERN.test(source))
    throw new Error('SVG 包含不受支持的活动内容或外部资源')
}

function normalizeMarkCanvas(source: HTMLCanvasElement): HTMLCanvasElement {
  const context = requireContext(source)
  const pixels = context.getImageData(0, 0, source.width, source.height).data
  let minX = source.width
  let minY = source.height
  let maxX = -1
  let maxY = -1

  for (let y = 0; y < source.height; y += 1) {
    for (let x = 0; x < source.width; x += 1) {
      if ((pixels[(y * source.width + x) * 4 + 3] ?? 0) <= 4)
        continue
      minX = Math.min(minX, x)
      minY = Math.min(minY, y)
      maxX = Math.max(maxX, x)
      maxY = Math.max(maxY, y)
    }
  }

  if (maxX < minX || maxY < minY)
    throw new Error('主体图标不能是全透明图片')

  const width = maxX - minX + 1
  const height = maxY - minY + 1
  const safeSize = APP_ICON_CANVAS_SIZE * APP_ICON_MARK_SAFE_RATIO
  const scale = safeSize / Math.max(width, height)
  const targetWidth = width * scale
  const targetHeight = height * scale
  const targetX = (APP_ICON_CANVAS_SIZE - targetWidth) / 2
  const targetY = (APP_ICON_CANVAS_SIZE - targetHeight) / 2

  const output = document.createElement('canvas')
  output.width = APP_ICON_CANVAS_SIZE
  output.height = APP_ICON_CANVAS_SIZE
  requireContext(output).drawImage(
    source,
    minX,
    minY,
    width,
    height,
    targetX,
    targetY,
    targetWidth,
    targetHeight,
  )
  return output
}

function validateNearSquare(width: number, height: number) {
  if (!width || !height || Math.abs(width - height) / Math.max(width, height) > 0.05)
    throw new Error('完整图标应使用接近正方形的画布')
}

async function loadImage(file: File): Promise<HTMLImageElement> {
  const source = URL.createObjectURL(file)
  try {
    const image = new Image()
    image.decoding = 'async'
    image.src = source
    await image.decode()
    return image
  }
  catch {
    throw new Error('图片无法读取，请检查文件是否完整')
  }
  finally {
    URL.revokeObjectURL(source)
  }
}

function requireContext(canvas: HTMLCanvasElement): CanvasRenderingContext2D {
  const context = canvas.getContext('2d', { willReadFrequently: true })
  if (!context)
    throw new Error('当前浏览器无法处理图片')
  return context
}

function canvasToPng(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob)
        resolve(blob)
      else
        reject(new Error('图标转换失败'))
    }, 'image/png')
  })
}
