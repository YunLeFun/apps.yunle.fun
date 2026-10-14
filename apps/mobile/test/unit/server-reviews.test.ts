import { describe, expect, it, vi } from 'vitest'
import {
  checkCooldown,
  computeReviewSummary,
  mapSuggestionToStatus,
  summarizeRatingGroups,
  validateReportInput,
  validateReviewInput,
} from '../../server/utils/reviews'

function createCooldownCollection(latest?: Record<string, unknown>) {
  return {
    where: vi.fn().mockReturnThis(),
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    get: vi.fn().mockResolvedValue({ data: latest ? [latest] : [] }),
  }
}

describe('review server utils', () => {
  it('validates review input boundaries', () => {
    expect(validateReviewInput({
      appKey: 'cook',
      rating: 5,
      title: '好用',
      content: '很稳定',
    })).toEqual({
      appKey: 'cook',
      rating: 5,
      title: '好用',
      content: '很稳定',
    })

    expect(() => validateReviewInput({ appKey: 'cook', rating: 0, content: 'x' })).toThrow()
    expect(() => validateReviewInput({ appKey: 'cook', rating: 4.5, content: 'x' })).toThrow()
    expect(() => validateReviewInput({ appKey: 'cook', rating: 5, content: '' })).toThrow()
    expect(() => validateReviewInput({ appKey: 'cook', rating: 5, content: 'x'.repeat(1001) })).toThrow()
  })

  it('validates report input', () => {
    expect(validateReportInput({
      targetType: 'review',
      targetId: 'review-1',
      reason: 'spam',
      detail: '垃圾广告',
    })).toEqual({
      targetType: 'review',
      targetId: 'review-1',
      reason: 'spam',
      detail: '垃圾广告',
      appKey: undefined,
    })

    expect(() => validateReportInput({ targetType: 'review', targetId: 'r1', reason: 'bad' })).toThrow()
    expect(() => validateReportInput({ targetType: 'review', targetId: '', reason: 'spam' })).toThrow()
  })

  it('maps moderation suggestion to review status', () => {
    expect(mapSuggestionToStatus('Pass')).toBe('published')
    expect(mapSuggestionToStatus('Review')).toBe('pending')
    expect(mapSuggestionToStatus('Block')).toBe('rejected')
    expect(mapSuggestionToStatus('Unexpected')).toBe('pending')
  })

  it('computes review summary with one decimal average and distribution', () => {
    expect(computeReviewSummary([])).toEqual({
      average: 0,
      count: 0,
      distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 },
    })

    expect(computeReviewSummary([5, 5, 4, 2])).toEqual({
      average: 4,
      count: 4,
      distribution: { 1: 0, 2: 1, 3: 0, 4: 1, 5: 2 },
    })
    expect(computeReviewSummary([5, 4, 4])).toEqual(expect.objectContaining({ average: 4.3 }))
  })

  it('summarizes aggregated rating groups', () => {
    expect(summarizeRatingGroups([])).toEqual({
      average: 0,
      count: 0,
      distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 },
    })

    expect(summarizeRatingGroups([
      { _id: 5, count: 2 },
      { _id: 4, count: 1 },
      { _id: 2, count: 1 },
    ])).toEqual({
      average: 4,
      count: 4,
      distribution: { 1: 0, 2: 1, 3: 0, 4: 1, 5: 2 },
    })

    // 非法分组（脏数据 / 越界评分 / 非数字 count）应被忽略
    expect(summarizeRatingGroups([
      { _id: 6, count: 3 },
      { _id: 'x', count: 1 },
      { _id: 3, count: '2' },
      null,
      { _id: 5, count: 1 },
    ])).toEqual({
      average: 5,
      count: 1,
      distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 1 },
    })
  })

  it('rejects cooldown hits', async () => {
    const collection = createCooldownCollection({ updatedAt: Date.now() - 1000 })
    await expect(checkCooldown(collection, 'uid-1', 60_000)).rejects.toMatchObject({ statusCode: 429 })
    expect(collection.where).toHaveBeenCalledWith({ uid: 'uid-1' })
  })

  it('allows old or missing activity', async () => {
    await expect(checkCooldown(createCooldownCollection(), 'uid-1', 60_000)).resolves.toBeUndefined()
    await expect(checkCooldown(createCooldownCollection({ updatedAt: Date.now() - 120_000 }), 'uid-1', 60_000)).resolves.toBeUndefined()
  })
})
