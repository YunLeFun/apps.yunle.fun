import type { MyReportItem, ReportReason, ReportStatus } from '~/types/review'
import { setResponseHeader } from 'h3'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireCloudbaseUser } from '../../utils/cloudbase-auth'
import { getPublicAppsByKeys } from '../../utils/public-apps'

const REPORT_REASONS: ReportReason[] = ['illegal', 'porn', 'abuse', 'spam', 'privacy', 'other']
const REPORT_STATUSES: ReportStatus[] = ['open', 'resolved', 'dismissed']

/**
 * 「我的举报」：返回当前登录用户提交过的举报及其处理状态，形成反馈闭环。
 *
 * app_reports 安全规则为 server-only（客户端不可直读），故必须经管理端 SDK + 鉴权代理。
 * 仅投影对举报人安全的字段，机审 / 处理人 / 处理备注等内部信息不下发。
 */
export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const user = await requireCloudbaseUser(event)
  const { db } = useCloudbaseAdmin()

  const { data } = await db.collection('app_reports')
    .where({ uid: user.uid })
    .orderBy('createdAt', 'desc')
    .limit(50)
    .get()

  const reports = (data || [])
    .map(normalizeMyReport)
    .filter((report): report is MyReportItem => Boolean(report))

  // appKey uses the public market name or record ID, never a workshop-local slug.
  const keys = reports.map(report => report.appKey).filter((key): key is string => Boolean(key))
  if (keys.length) {
    const apps = await getPublicAppsByKeys(keys, db)
    for (const report of reports) {
      if (report.appKey)
        report.appName = apps.get(report.appKey)?.name
    }
  }

  return { code: 0, data: { reports } }
})

function normalizeMyReport(value: unknown): MyReportItem | null {
  if (!isRecord(value))
    return null
  const _id = stringProp(value, '_id')
  const targetId = stringProp(value, 'targetId')
  const targetType = stringProp(value, 'targetType')
  const reason = stringProp(value, 'reason')
  const createdAt = numberProp(value, 'createdAt')
  if (!_id || !targetId || !reason || !createdAt)
    return null
  if (targetType !== 'app' && targetType !== 'review')
    return null
  if (!REPORT_REASONS.includes(reason as ReportReason))
    return null

  const status = stringProp(value, 'status')
  return {
    _id,
    targetType,
    targetId,
    appKey: stringProp(value, 'appKey'),
    reason: reason as ReportReason,
    detail: stringProp(value, 'detail'),
    status: REPORT_STATUSES.includes(status as ReportStatus) ? (status as ReportStatus) : 'open',
    createdAt,
    handledAt: numberProp(value, 'handledAt'),
  }
}

function stringProp(value: unknown, key: string): string | undefined {
  if (!isRecord(value))
    return undefined
  const prop = value[key]
  return typeof prop === 'string' && prop ? prop : undefined
}

function numberProp(value: unknown, key: string): number | undefined {
  if (!isRecord(value))
    return undefined
  const prop = value[key]
  return typeof prop === 'number' ? prop : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
