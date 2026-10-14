import type { ReviewStatus, ReviewSummary, SubmitReportInput, SubmitReviewInput } from '~/types/review'
import { createError } from 'h3'

export interface ValidReviewInput {
  appKey: string
  rating: number
  title?: string
  content: string
}

export interface ValidReportInput {
  targetType: 'app' | 'review'
  targetId: string
  appKey?: string
  reason: SubmitReportInput['reason']
  detail?: string
}

export interface TimestampedRecord {
  createdAt?: number
  updatedAt?: number
}

export function validateReviewInput(body: unknown): ValidReviewInput {
  if (!isRecord(body)) {
    throw createError({ statusCode: 400, message: '请求数据格式错误' })
  }
  const appKey = stringField(body, 'appKey').trim()
  const title = optionalStringField(body, 'title')?.trim()
  const content = stringField(body, 'content').trim()
  const rating = body.rating

  if (!appKey)
    throw createError({ statusCode: 400, message: '缺少应用标识' })
  if (typeof rating !== 'number' || !Number.isInteger(rating) || rating < 1 || rating > 5)
    throw createError({ statusCode: 400, message: '评分必须是 1-5 的整数' })
  if (!content || content.length > 1000)
    throw createError({ statusCode: 400, message: '评论内容需为 1-1000 字符' })
  if (title && title.length > 100)
    throw createError({ statusCode: 400, message: '评论标题不能超过 100 字符' })

  return {
    appKey,
    rating,
    title: title || undefined,
    content,
  }
}

export function validateReportInput(body: unknown): ValidReportInput {
  if (!isRecord(body)) {
    throw createError({ statusCode: 400, message: '请求数据格式错误' })
  }
  const targetType = body.targetType
  const targetId = stringField(body, 'targetId').trim()
  const appKey = optionalStringField(body, 'appKey')?.trim()
  const reason = body.reason
  const detail = optionalStringField(body, 'detail')?.trim()

  if (targetType !== 'app' && targetType !== 'review')
    throw createError({ statusCode: 400, message: '举报对象类型错误' })
  if (!targetId)
    throw createError({ statusCode: 400, message: '缺少举报对象' })
  if (!isReportReason(reason))
    throw createError({ statusCode: 400, message: '举报原因错误' })
  if (detail && detail.length > 500)
    throw createError({ statusCode: 400, message: '举报说明不能超过 500 字符' })

  return {
    targetType,
    targetId,
    appKey: appKey || undefined,
    reason,
    detail: detail || undefined,
  }
}

export function mapSuggestionToStatus(suggestion: string): ReviewStatus {
  if (suggestion === 'Pass')
    return 'published'
  if (suggestion === 'Block')
    return 'rejected'
  return 'pending'
}

export function computeReviewSummary(ratings: number[]): ReviewSummary {
  const distribution = emptyDistribution()
  for (const rating of ratings) {
    if (isRatingKey(rating))
      distribution[rating] += 1
  }
  return finalizeSummary(distribution)
}

/**
 * 由数据库聚合分组结果汇总评分摘要
 * groups 形如 [{ _id: 5, count: 12 }, ...]（group by rating）
 */
export function summarizeRatingGroups(groups: unknown[]): ReviewSummary {
  const distribution = emptyDistribution()
  for (const group of groups) {
    if (!isRecord(group))
      continue
    const rating = group._id
    const count = group.count
    if (typeof rating === 'number' && isRatingKey(rating) && typeof count === 'number' && count > 0)
      distribution[rating] += count
  }
  return finalizeSummary(distribution)
}

function emptyDistribution(): ReviewSummary['distribution'] {
  return { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 }
}

function finalizeSummary(distribution: ReviewSummary['distribution']): ReviewSummary {
  let count = 0
  let sum = 0
  for (const key of [1, 2, 3, 4, 5] as const) {
    count += distribution[key]
    sum += key * distribution[key]
  }
  const average = count > 0 ? Math.round((sum / count) * 10) / 10 : 0
  return { average, count, distribution }
}

export async function checkCooldown(
  collection: {
    where: (query: Record<string, unknown>) => {
      orderBy: (field: string, order: 'asc' | 'desc') => {
        limit: (count: number) => {
          get: () => Promise<{ data?: unknown[] }>
        }
      }
    }
  },
  uid: string,
  cooldownMs = 60_000,
): Promise<void> {
  const result = await collection
    .where({ uid })
    .orderBy('updatedAt', 'desc')
    .limit(1)
    .get()
  const latest = result.data?.[0]
  if (isRecord(latest)) {
    const lastAt = numberField(latest, 'updatedAt') || numberField(latest, 'createdAt') || 0
    if (Date.now() - lastAt < cooldownMs) {
      throw createError({
        statusCode: 429,
        message: '操作太频繁，请稍后再试',
      })
    }
  }
}

export function publicReviewFields() {
  return {
    _id: true,
    appKey: true,
    authorName: true,
    authorAvatar: true,
    rating: true,
    title: true,
    content: true,
    createdAt: true,
    updatedAt: true,
    publishedAt: true,
  }
}

function isRatingKey(value: number): value is 1 | 2 | 3 | 4 | 5 {
  return value === 1 || value === 2 || value === 3 || value === 4 || value === 5
}

function stringField(value: Record<string, unknown>, key: keyof SubmitReviewInput | 'targetId'): string {
  const field = value[key]
  return typeof field === 'string' ? field : ''
}

function optionalStringField(value: Record<string, unknown>, key: keyof SubmitReviewInput | keyof SubmitReportInput): string | undefined {
  const field = value[key]
  return typeof field === 'string' ? field : undefined
}

function numberField(value: Record<string, unknown>, key: keyof TimestampedRecord): number | undefined {
  const field = value[key]
  return typeof field === 'number' ? field : undefined
}

function isReportReason(value: unknown): value is SubmitReportInput['reason'] {
  return value === 'illegal'
    || value === 'porn'
    || value === 'abuse'
    || value === 'spam'
    || value === 'privacy'
    || value === 'other'
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
