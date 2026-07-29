import { randomUUID } from 'node:crypto'
import { createError, readBody } from 'h3'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import {
  DIAGNOSTIC_UPLOAD_RETENTION_MS,
  validateDiagnosticLogUpload,
} from '../../utils/diagnostic-logs'

const UPLOAD_COOLDOWN_MS = 60 * 1000

export default defineEventHandler(async (event) => {
  const user = await requireRegisteredCloudbaseUser(event)
  const now = Date.now()
  const input = validateDiagnosticLogUpload(await readBody(event), now)
  const { db } = useCloudbaseAdmin()
  const collection = db.collection('diagnostic_log_uploads')

  const { data: recentUploads } = await collection
    .where({ ownerUid: user.uid })
    .orderBy('createdAt', 'desc')
    .limit(1)
    .get()
  const latestUpload = recentUploads?.[0]
  if (isRecord(latestUpload)
    && typeof latestUpload.createdAt === 'number'
    && now - latestUpload.createdAt < UPLOAD_COOLDOWN_MS) {
    throw createError({
      statusCode: 429,
      message: '提交过于频繁，请一分钟后再试',
    })
  }

  const supportCode = randomUUID().replaceAll('-', '').slice(0, 12).toUpperCase()
  const expiresAt = now + DIAGNOSTIC_UPLOAD_RETENTION_MS
  const addResult = await collection.add({
    schemaVersion: 1,
    supportCode,
    ownerUid: user.uid,
    issueDescription: input.issueDescription,
    startTime: input.startTime,
    endTime: input.endTime,
    logCount: input.logs.length,
    sizeBytes: input.sizeBytes,
    logs: input.logs,
    client: input.client,
    status: 'new',
    createdAt: now,
    updatedAt: now,
    expiresAt,
  })
  const uploadId = typeof addResult.id === 'string' ? addResult.id : ''

  try {
    await collection
      .where({ expiresAt: db.command.lt(now) })
      .remove()
  }
  catch {
    // 清理失败不影响本次已完成的上传；定时函数或后续提交会再次清理。
    console.warn('[Diagnostics] expired diagnostic log cleanup deferred')
  }

  return {
    code: 0,
    data: {
      uploadId,
      supportCode,
      logCount: input.logs.length,
      expiresAt,
    },
  }
})

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
