import type { ReviewListResponse, ReviewPublic, ReviewRecord } from '~/types/review'
import { createError, getQuery } from 'h3'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { tryGetCloudbaseUser } from '../../utils/cloudbase-auth'
import { summarizeRatingGroups } from '../../utils/reviews'

export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const appKey = typeof query.appKey === 'string' ? query.appKey.trim() : ''
  if (!appKey) {
    throw createError({
      statusCode: 400,
      message: '缺少应用标识',
    })
  }

  const user = await tryGetCloudbaseUser(event)
  const { db } = useCloudbaseAdmin()
  const reviewsCollection = db.collection('app_reviews')

  // 评分统计用聚合分组（group by rating），不受拉取条数限制，也省去整表读取
  const [listResult, summaryResult, myResult] = await Promise.all([
    reviewsCollection
      .where({ appKey, status: 'published' })
      .orderBy('updatedAt', 'desc')
      .limit(50)
      .get(),
    reviewsCollection
      .aggregate()
      .match({ appKey, status: 'published' })
      .group({ _id: '$rating', count: db.command.aggregate.sum(1) })
      .end(),
    user
      ? reviewsCollection.where({ appKey, uid: user.uid }).limit(1).get()
      : Promise.resolve(null),
  ])

  const myReview: ReviewRecord | null = myResult
    ? normalizeReviewRecord(myResult.data?.[0])
    : null

  const reviews = (listResult.data || [])
    .map(normalizePublicReview)
    .filter((review): review is ReviewPublic => Boolean(review))

  const data: ReviewListResponse = {
    summary: summarizeRatingGroups(summaryResult?.data || []),
    reviews,
    myReview,
  }

  return { code: 0, data }
})

function normalizePublicReview(value: unknown): ReviewPublic | null {
  const record = normalizeReviewRecord(value)
  if (!record || record.status !== 'published')
    return null
  return {
    _id: record._id,
    appKey: record.appKey,
    authorName: record.authorName,
    authorAvatar: record.authorAvatar,
    rating: record.rating,
    title: record.title,
    content: record.content,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    publishedAt: record.publishedAt,
  }
}

function normalizeReviewRecord(value: unknown): ReviewRecord | null {
  if (!isRecord(value))
    return null
  const _id = stringProp(value, '_id')
  const appKey = stringProp(value, 'appKey')
  const uid = stringProp(value, 'uid')
  const authorName = stringProp(value, 'authorName')
  const content = stringProp(value, 'content')
  const status = stringProp(value, 'status')
  const rating = numberProp(value, 'rating')
  const createdAt = numberProp(value, 'createdAt')
  const updatedAt = numberProp(value, 'updatedAt')
  if (!_id || !appKey || !uid || !authorName || !content || !status || !rating || !createdAt || !updatedAt)
    return null
  if (status !== 'published' && status !== 'pending' && status !== 'rejected')
    return null
  return {
    _id,
    appKey,
    appId: stringProp(value, 'appId') || '',
    uid,
    authorName,
    authorAvatar: stringProp(value, 'authorAvatar'),
    rating,
    title: stringProp(value, 'title'),
    content,
    status,
    rejectedReason: stringProp(value, 'rejectedReason'),
    createdAt,
    updatedAt,
    publishedAt: numberProp(value, 'publishedAt'),
  }
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
