import type { AppIconAssetRole } from '~/types/app'
import { Buffer } from 'node:buffer'
import { createError } from 'h3'

export const NORMALIZED_APP_ICON_SIZE = 1024
export const NORMALIZED_APP_ICON_MAX_BYTES = 4 * 1024 * 1024

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

export function normalizeAppIconRole(value: string): AppIconAssetRole {
  if (value === 'app-icon' || value === 'mark')
    return value
  throw createError({ statusCode: 400, statusMessage: '图标类型不正确' })
}

export function validateNormalizedAppIcon(data: Buffer, contentType: string | undefined) {
  if (contentType !== 'image/png')
    invalid('上传内容必须是标准化 PNG')
  if (!data.length || data.length > NORMALIZED_APP_ICON_MAX_BYTES)
    invalid('图标大小需在 4 MB 以内')
  if (data.length < 24 || !data.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE))
    invalid('PNG 文件头不正确')
  if (data.toString('ascii', 12, 16) !== 'IHDR')
    invalid('PNG 缺少 IHDR 信息')

  const width = data.readUInt32BE(16)
  const height = data.readUInt32BE(20)
  if (width !== NORMALIZED_APP_ICON_SIZE || height !== NORMALIZED_APP_ICON_SIZE)
    invalid(`图标尺寸必须为 ${NORMALIZED_APP_ICON_SIZE}×${NORMALIZED_APP_ICON_SIZE}`)

  return { width, height }
}

function invalid(message: string): never {
  throw createError({ statusCode: 400, statusMessage: message })
}
