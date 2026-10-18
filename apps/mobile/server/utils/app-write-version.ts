import type { PublicMarketListingRecord } from '../domain/public-market-submission'
import type { AppRecord, AppSubmission } from '~/types/app'
import { createHash } from 'node:crypto'
import { createError } from 'h3'

interface DocumentReader {
  collection: (name: string) => {
    doc: (id: string) => { get: () => Promise<{ data?: unknown }> }
  }
}

export function applicationRevisionIds(app: AppRecord, listing?: PublicMarketListingRecord | null): string[] {
  return [...new Set([app.currentRevisionId, app.publishedSubmissionId, app.activeSubmissionId, listing?.activeSubmissionId, listing?.approvedRevisionId].filter((id): id is string => Boolean(id)))].sort()
}

/** Hash persisted state before owner-view projections. Never persist or expose this token in the public catalog. */
export function applicationWriteVersion(app: AppRecord, listing: PublicMarketListingRecord | null, submissions: Map<string, AppSubmission>): string {
  const state = [app, listing, applicationRevisionIds(app, listing).map(id => [id, submissions.get(id) ?? null])]
  return createHash('sha256').update(JSON.stringify(state, (_key, value: unknown) => {
    if (value && typeof value === 'object' && !Array.isArray(value))
      return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0))
    return value
  })).digest('hex')
}

/** The same reads must execute inside the write transaction, including on every SDK conflict retry. */
export async function readOwnedApplicationState(reader: DocumentReader, id: string, uid: string) {
  const app = first<AppRecord>((await reader.collection('apps').doc(id).get()).data)
  if (!app)
    throw createError({ statusCode: 404, message: '应用不存在' })
  if (app.ownerUid ? app.ownerUid !== uid : app._openid !== uid)
    throw createError({ statusCode: 403, message: '无权管理此应用' })
  const listing = first<PublicMarketListingRecord>((await reader.collection('public_market_listings').doc(id).get()).data)
  const submissions = new Map<string, AppSubmission>()
  // Sequential document reads also work with the SDK's transaction API; no query runs inside a transaction.
  for (const revisionId of applicationRevisionIds(app, listing)) {
    const submission = first<AppSubmission>((await reader.collection('app_submissions').doc(revisionId).get()).data)
    if (submission)
      submissions.set(revisionId, submission)
  }
  return { app, listing, submissions, writeVersion: applicationWriteVersion(app, listing, submissions) }
}

export function requireApplicationWriteVersion(ifMatch: string | undefined, actual: string): void {
  if (!ifMatch)
    throw createError({ statusCode: 428, message: '请刷新作品后重试，当前操作缺少版本信息', data: { code: 'APP_WRITE_VERSION_REQUIRED' } })
  if (!/^"[a-f0-9]{64}"$/.test(ifMatch) || ifMatch !== `"${actual}"`)
    throw createError({ statusCode: 412, message: '作品或审核状态已变化，请刷新后核对；你的草稿尚未提交', data: { code: 'APP_WRITE_CONFLICT' } })
}

function first<T>(data: unknown): T | null {
  if (Array.isArray(data))
    return data[0] as T | undefined || null
  return data && typeof data === 'object' ? data as T : null
}
