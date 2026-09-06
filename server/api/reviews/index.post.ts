import type { ReviewModerationInfo, ReviewRecord, SubmitReviewResponse } from '~/types/review'
import { createError, readBody } from 'h3'
import { recomputeAppRating } from '../../utils/app-rating'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireCloudbaseUser } from '../../utils/cloudbase-auth'
import { buildModerationContent, logModerationTask, moderateText } from '../../utils/moderation'
import { getPublicAppByKey } from '../../utils/public-apps'
import { checkCooldown, mapSuggestionToStatus, validateReviewInput } from '../../utils/reviews'

export default defineEventHandler(async (event) => {
  const user = await requireCloudbaseUser(event)
  const input = validateReviewInput(await readBody(event))
  const { db } = useCloudbaseAdmin()
  const reviewsCollection = db.collection('app_reviews')

  const app = await getPublicAppByKey(input.appKey, db)
  if (!app) {
    throw createError({
      statusCode: 404,
      message: '应用不存在或尚未公开',
    })
  }

  input.appKey = app.marketShortName || app._id
  await checkCooldown(reviewsCollection, user.uid)

  const content = buildModerationContent([input.title, input.content])
  const moderationStartedAt = Date.now()
  const moderation = await moderateText({
    content,
    userId: user.uid,
    dataId: `review-${input.appKey}-${user.uid}`,
    scene: 'review',
  })
  await logModerationTask(db, {
    scene: 'review',
    targetId: input.appKey,
    uid: user.uid,
    contentLength: content.length,
    result: moderation,
    durationMs: Date.now() - moderationStartedAt,
  })

  const status = mapSuggestionToStatus(moderation.suggestion)
  const now = Date.now()
  const moderationInfo: ReviewModerationInfo = {
    suggestion: moderation.suggestion,
    label: moderation.label,
    subLabel: moderation.subLabel,
    keywords: moderation.keywords,
    requestId: moderation.requestId,
    error: moderation.error,
  }
  const nextFields = {
    appKey: input.appKey,
    appId: app._id,
    uid: user.uid,
    authorName: user.name || '云乐坊用户',
    authorAvatar: user.picture || '',
    rating: input.rating,
    title: input.title || '',
    content: input.content,
    status,
    rejectedReason: status === 'rejected'
      ? [moderation.label, moderation.subLabel].filter(Boolean).join(' / ') || '内容涉嫌违规'
      : '',
    moderation: moderationInfo,
    updatedAt: now,
    publishedAt: status === 'published' ? now : 0,
  }

  const { data: existingRows } = await reviewsCollection
    .where({ appKey: input.appKey, uid: user.uid })
    .limit(1)
    .get()
  const existing = normalizeReviewRecord(existingRows?.[0])

  let review: ReviewRecord
  if (existing) {
    await reviewsCollection.doc(existing._id).update(nextFields)
    review = {
      ...existing,
      ...nextFields,
      _id: existing._id,
      createdAt: existing.createdAt,
    }
  }
  else {
    const inserted = await reviewsCollection.add({
      ...nextFields,
      createdAt: now,
    }) as unknown
    review = {
      _id: extractInsertedId(inserted),
      ...nextFields,
      createdAt: now,
    }
  }

  // 去规范化回写应用评分聚合（列表展示用），失败不阻断评论提交
  await recomputeAppRating(db, input.appKey, app._id).catch(() => {})

  const data: SubmitReviewResponse = {
    status,
    message: statusMessage(status),
    review,
  }

  return { code: 0, data }
})

function statusMessage(status: ReviewRecord['status']): string {
  if (status === 'published')
    return '评论已发布'
  if (status === 'rejected')
    return '内容涉嫌违规，未能发布'
  return '已提交，审核通过后展示'
}

function normalizeReviewRecord(value: unknown): Pick<ReviewRecord, '_id' | 'createdAt'> | null {
  if (!isRecord(value))
    return null
  const _id = stringProp(value, '_id')
  const createdAt = numberProp(value, 'createdAt')
  return _id && createdAt ? { _id, createdAt } : null
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

function numberProp(value: Record<string, unknown>, key: string): number | undefined {
  const prop = value[key]
  return typeof prop === 'number' ? prop : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
