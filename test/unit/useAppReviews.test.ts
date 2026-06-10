import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ref, toValue } from 'vue'
import { useAppReviews } from '../../app/composables/useAppReviews'

const mockApi = vi.fn()
const mockPush = vi.fn()
const mockToast = {
  showSuccess: vi.fn(),
  showError: vi.fn(),
  showWarning: vi.fn(),
  showInfo: vi.fn(),
}
let mockUserStore: { isLoggedIn: boolean }

vi.stubGlobal('useNuxtApp', () => ({ $api: mockApi }))
vi.stubGlobal('useRouter', () => ({ push: mockPush }))
vi.stubGlobal('useToast', () => mockToast)
vi.stubGlobal('useUserStore', () => mockUserStore)
vi.stubGlobal('toValue', toValue)

describe('useAppReviews', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockUserStore = { isLoggedIn: true }
  })

  it('loads reviews and summary from API', async () => {
    mockApi.mockResolvedValueOnce({
      code: 0,
      data: {
        summary: { average: 4.5, count: 2, distribution: { 1: 0, 2: 0, 3: 0, 4: 1, 5: 1 } },
        reviews: [{ _id: 'r1', appKey: 'cook', authorName: 'A', rating: 5, content: 'x', createdAt: 1, updatedAt: 1 }],
        myReview: null,
      },
    })

    const reviews = useAppReviews(ref('cook'))
    await reviews.load()

    expect(mockApi).toHaveBeenCalledWith('/api/reviews', { query: { appKey: 'cook' } })
    expect(reviews.summary.value.average).toBe(4.5)
    expect(reviews.reviews.value).toHaveLength(1)
  })

  it('redirects unauthenticated users before submit', async () => {
    mockUserStore.isLoggedIn = false
    const reviews = useAppReviews(ref('cook'))

    await expect(reviews.submitReview({ rating: 5, content: 'x' })).resolves.toBeNull()

    expect(mockApi).not.toHaveBeenCalled()
    expect(mockToast.showError).toHaveBeenCalledWith('请先登录后评论')
    expect(mockPush).toHaveBeenCalledWith('/login')
  })

  it('submits review, shows status message, then reloads', async () => {
    mockApi
      .mockResolvedValueOnce({
        code: 0,
        data: {
          status: 'pending',
          message: '已提交，审核通过后展示',
          review: { _id: 'r1' },
        },
      })
      .mockResolvedValueOnce({
        code: 0,
        data: {
          summary: { average: 0, count: 0, distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 } },
          reviews: [],
          myReview: { _id: 'r1', status: 'pending' },
        },
      })

    const reviews = useAppReviews(ref('cook'))
    const result = await reviews.submitReview({ rating: 4, title: '不错', content: '体验稳定' })

    expect(result?.status).toBe('pending')
    expect(mockApi).toHaveBeenNthCalledWith(1, '/api/reviews', {
      method: 'POST',
      body: {
        appKey: 'cook',
        rating: 4,
        title: '不错',
        content: '体验稳定',
      },
    })
    expect(mockToast.showSuccess).toHaveBeenCalledWith('已提交，审核通过后展示')
  })

  it('maps report duplicate errors to toast message', async () => {
    mockApi.mockRejectedValueOnce({ data: { statusMessage: '你已举报过该内容' } })
    const reviews = useAppReviews(ref('cook'))

    await expect(reviews.submitReport({
      targetType: 'app',
      targetId: 'cook',
      reason: 'spam',
    })).resolves.toBe(false)

    expect(mockToast.showError).toHaveBeenCalledWith('你已举报过该内容')
  })
})
