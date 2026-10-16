import type { ReviewRecord } from '~/types/review'
import { createError, readBody, setResponseHeader } from 'h3'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireCloudbaseUser } from '../../utils/cloudbase-auth'
import { buildModerationContent, logModerationTask, moderateText } from '../../utils/moderation'
import { getPublicAppByKey } from '../../utils/public-apps'
import { checkCooldown, validateReportInput } from '../../utils/reviews'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const user = await requireCloudbaseUser(event)
  const input = validateReportInput(await readBody(event))
  const { db } = useCloudbaseAdmin()
  const reportsCollection = db.collection('app_reports')

  let appKey = input.appKey || ''
  if (input.targetType === 'app') {
    const app = await getPublicAppByKey(input.targetId, db)
    if (!app) {
      throw createError({
        statusCode: 404,
        message: '应用不存在或尚未公开',
      })
    }
    appKey = app.marketShortName || app._id
    input.targetId = appKey
  }
  else {
    const { data } = await db.collection('app_reviews')
      .where({ _id: input.targetId })
      .limit(1)
      .get()
    const review = normalizeReviewRecord(data?.[0])
    if (!review) {
      throw createError({
        statusCode: 404,
        message: '评论不存在',
      })
    }
    appKey = review.appKey
  }

  const { data: duplicates } = await reportsCollection
    .where({ uid: user.uid, targetType: input.targetType, targetId: input.targetId })
    .limit(1)
    .get()
  if (duplicates?.length) {
    throw createError({
      statusCode: 409,
      message: '你已举报过该内容',
    })
  }

  await checkCooldown(reportsCollection, user.uid)

  const now = Date.now()
  let reasonModeration: Record<string, unknown> | undefined
  if (input.detail) {
    const content = buildModerationContent([input.detail])
    const moderationStartedAt = Date.now()
    const moderation = await moderateText({
      content,
      userId: user.uid,
      dataId: `report-${input.targetType}-${input.targetId}-${user.uid}`,
      scene: 'report',
    })
    await logModerationTask(db, {
      scene: 'report',
      targetId: input.targetId,
      uid: user.uid,
      contentLength: content.length,
      result: moderation,
      durationMs: Date.now() - moderationStartedAt,
    })
    reasonModeration = {
      suggestion: moderation.suggestion,
      label: moderation.label || '',
      subLabel: moderation.subLabel || '',
      keywords: moderation.keywords || [],
      requestId: moderation.requestId || '',
      error: moderation.error || '',
    }
  }

  const inserted = await reportsCollection.add({
    uid: user.uid,
    targetType: input.targetType,
    targetId: input.targetId,
    appKey,
    reason: input.reason,
    detail: input.detail || '',
    reasonModeration,
    status: 'open',
    createdAt: now,
    updatedAt: now,
  }) as unknown

  return {
    code: 0,
    data: {
      id: extractInsertedId(inserted),
    },
  }
})

function normalizeReviewRecord(value: unknown): Pick<ReviewRecord, '_id' | 'appKey'> | null {
  if (!isRecord(value))
    return null
  const _id = stringProp(value, '_id')
  const appKey = stringProp(value, 'appKey')
  return _id && appKey ? { _id, appKey } : null
}

function extractInsertedId(value: unknown): string {
  if (!isRecord(value))
    return ''
  return stringProp(value, '_id') || stringProp(value, 'id') || ''
}

function stringProp(value: Record<string, unknown>, key: string): string | undefined {
  const prop = value[key]
  return typeof prop === 'string' && prop ? prop : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
