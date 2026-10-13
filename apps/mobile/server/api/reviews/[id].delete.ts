import type { ReviewRecord } from '~/types/review'
import { createError, getRouterParam } from 'h3'
import { recomputeAppRating } from '../../utils/app-rating'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireCloudbaseUser(event)
  const id = getRouterParam(event, 'id')?.trim()
  if (!id) {
    throw createError({
      statusCode: 400,
      message: '缺少评论 ID',
    })
  }

  const { db } = useCloudbaseAdmin()
  const collection = db.collection('app_reviews')
  const { data } = await collection
    .where({ _id: id })
    .limit(1)
    .get()
  const review = normalizeReviewRecord(data?.[0])
  if (!review) {
    throw createError({
      statusCode: 404,
      message: '评论不存在',
    })
  }
  if (review.uid !== user.uid) {
    throw createError({
      statusCode: 403,
      message: '无权删除此评论',
    })
  }

  await collection.doc(id).remove()

  // 删除后重算应用评分聚合，失败不阻断
  if (review.appKey)
    await recomputeAppRating(db, review.appKey, review.appId).catch(() => {})

  return { code: 0 }
})

function normalizeReviewRecord(value: unknown): Pick<ReviewRecord, '_id' | 'uid' | 'appKey' | 'appId'> | null {
  if (!isRecord(value))
    return null
  const _id = stringProp(value, '_id')
  const uid = stringProp(value, 'uid')
  return _id && uid
    ? { _id, uid, appKey: stringProp(value, 'appKey') || '', appId: stringProp(value, 'appId') || '' }
    : null
}

function stringProp(value: Record<string, unknown>, key: string): string | undefined {
  const prop = value[key]
  return typeof prop === 'string' && prop ? prop : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
