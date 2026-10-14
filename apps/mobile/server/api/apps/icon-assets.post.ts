import { createHash, randomUUID } from 'node:crypto'
import { createError, readMultipartFormData } from 'h3'
import { normalizeAppIconRole, validateNormalizedAppIcon } from '../../utils/app-icon-upload'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'

const uploadWindows = new Map<string, { count: number, resetAt: number }>()
const UPLOAD_WINDOW_MS = 60_000
const UPLOAD_LIMIT = 12

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  enforceUploadRateLimit(user.uid)

  const parts = await readMultipartFormData(event)
  const file = parts?.find(part => part.name === 'file' && part.filename)
  const rolePart = parts?.find(part => part.name === 'assetRole')
  if (!file || !rolePart)
    throw createError({ statusCode: 400, statusMessage: '请选择图标文件和图标类型' })

  const role = normalizeAppIconRole(rolePart.data.toString('utf8'))
  const dimensions = validateNormalizedAppIcon(file.data, file.type)
  const ownerHash = createHash('sha256').update(user.uid).digest('hex').slice(0, 16)
  const cloudPath = `app-icons/${ownerHash}/${randomUUID()}.png`
  const { fileID } = await useCloudbaseAdmin().app.uploadFile({
    cloudPath,
    fileContent: file.data,
  })

  return { fileID, role, ...dimensions }
})

function enforceUploadRateLimit(uid: string) {
  const now = Date.now()
  const window = uploadWindows.get(uid)
  if (!window || window.resetAt <= now) {
    uploadWindows.set(uid, { count: 1, resetAt: now + UPLOAD_WINDOW_MS })
    return
  }
  if (window.count >= UPLOAD_LIMIT) {
    throw createError({
      statusCode: 429,
      statusMessage: '上传过于频繁，请稍后再试',
    })
  }
  window.count += 1
}
