import type { CloudbaseAdminDb } from './cloudbase-admin'
import type {
  DiagnosticLogAdminQuery,
  DiagnosticLogUploadDetail,
  DiagnosticLogUploadSummary,
} from './diagnostic-logs'
import {
  normalizeDiagnosticLogUploadDetail,
  normalizeDiagnosticLogUploadSummary,
} from './diagnostic-logs'

const COLLECTION = 'diagnostic_log_uploads'

export async function listActiveDiagnosticLogUploads(
  db: CloudbaseAdminDb,
  input: DiagnosticLogAdminQuery,
  now = Date.now(),
): Promise<DiagnosticLogUploadSummary[]> {
  const conditions: Record<string, string> = {}
  if (input.supportCode)
    conditions.supportCode = input.supportCode
  else if (input.uid)
    conditions.ownerUid = input.uid

  const query = db.collection(COLLECTION).where(conditions)
  const result = input.supportCode
    ? await query.limit(5).get()
    : await query
        .orderBy('createdAt', 'desc')
        .limit(Math.min(100, input.limit + 20))
        .get()

  return (result.data || [])
    .map(normalizeDiagnosticLogUploadSummary)
    .filter((upload): upload is DiagnosticLogUploadSummary =>
      upload !== null
      && upload.expiresAt > now
      && (!input.uid || upload.ownerUid === input.uid),
    )
    .sort((left, right) => right.createdAt - left.createdAt)
    .slice(0, input.limit)
}

export async function getActiveDiagnosticLogUpload(
  db: CloudbaseAdminDb,
  uploadId: string,
  now = Date.now(),
): Promise<DiagnosticLogUploadDetail | null> {
  const { data } = await db.collection(COLLECTION).doc(uploadId).get()
  const upload = normalizeDiagnosticLogUploadDetail(data?.[0])
  return upload && upload.expiresAt > now ? upload : null
}
