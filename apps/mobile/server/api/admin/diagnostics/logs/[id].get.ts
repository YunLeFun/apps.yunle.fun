import { createError, getRouterParam } from 'h3'
import { useCloudbaseAdmin } from '../../../../utils/cloudbase-admin'
import { requireDiagnosticAdmin } from '../../../../utils/diagnostic-admin'
import { getActiveDiagnosticLogUpload } from '../../../../utils/diagnostic-log-admin-service'

export default defineEventHandler(async (event) => {
  await requireDiagnosticAdmin(event)
  const uploadId = getRouterParam(event, 'id')?.trim() || ''
  if (!uploadId || uploadId.length > 128 || uploadId.includes('/')) {
    throw createError({
      statusCode: 400,
      message: '日志上传 ID 格式错误',
    })
  }

  const { db } = useCloudbaseAdmin()
  const upload = await getActiveDiagnosticLogUpload(db, uploadId)
  if (!upload) {
    throw createError({
      statusCode: 404,
      message: '诊断日志不存在或已过期',
    })
  }

  return {
    code: 0,
    data: {
      upload,
    },
  }
})
