import type {
  ReviewListResponse,
  ReviewRecord,
  ReviewSummary,
  SubmitReportInput,
  SubmitReviewInput,
  SubmitReviewResponse,
} from '~/types/review'

interface ApiResponse<T> {
  code: 0
  data: T
}

interface UseAppReviewsOptions {
  autoLoad?: boolean
}

export function useAppReviews(appKey: MaybeRefOrGetter<string | undefined>, options: UseAppReviewsOptions = {}) {
  const { $api } = useNuxtApp()
  const router = useRouter()
  const toast = useToast()
  const userStore = useUserStore()

  const summary = ref<ReviewSummary>(createEmptySummary())
  const reviews = ref<ReviewListResponse['reviews']>([])
  const myReview = ref<ReviewRecord | null>(null)
  const loading = ref(false)
  const submitting = ref(false)
  const error = ref<string | null>(null)

  function resetReviews() {
    summary.value = createEmptySummary()
    reviews.value = []
    myReview.value = null
  }

  async function load() {
    const key = toValue(appKey)
    if (!key)
      return
    loading.value = true
    error.value = null
    try {
      const res = await $api<ApiResponse<ReviewListResponse>>('/api/reviews', {
        query: { appKey: key },
      })
      summary.value = res.data.summary
      reviews.value = res.data.reviews
      myReview.value = res.data.myReview
    }
    catch (err) {
      console.warn('[reviews] load failed', err)
      resetReviews()
      error.value = null
    }
    finally {
      loading.value = false
    }
  }

  async function submitReview(input: Omit<SubmitReviewInput, 'appKey'>) {
    const key = toValue(appKey)
    if (!key)
      return null
    if (!userStore.isLoggedIn) {
      toast.showError('请先登录后评论')
      await router.push('/login')
      return null
    }

    submitting.value = true
    try {
      const res = await $api<ApiResponse<SubmitReviewResponse>>('/api/reviews', {
        method: 'POST',
        body: {
          appKey: key,
          ...input,
        },
      })
      const message = res.data.message || reviewStatusMessage(res.data.status)
      if (res.data.status === 'rejected')
        toast.showError(message)
      else
        toast.showSuccess(message)
      await load()
      return res.data
    }
    catch (err) {
      const message = getRequestErrorMessage(err, '评论提交失败')
      toast.showError(message)
      return null
    }
    finally {
      submitting.value = false
    }
  }

  async function deleteMyReview() {
    if (!myReview.value)
      return false
    submitting.value = true
    try {
      await $api(`/api/reviews/${myReview.value._id}`, { method: 'DELETE' })
      toast.showSuccess('评论已删除')
      await load()
      return true
    }
    catch (err) {
      toast.showError(getRequestErrorMessage(err, '删除失败'))
      return false
    }
    finally {
      submitting.value = false
    }
  }

  async function submitReport(input: SubmitReportInput) {
    if (!userStore.isLoggedIn) {
      toast.showError('请先登录后举报')
      await router.push('/login')
      return false
    }

    submitting.value = true
    try {
      await $api('/api/reports', {
        method: 'POST',
        body: input,
      })
      toast.showSuccess('举报已提交')
      return true
    }
    catch (err) {
      toast.showError(getRequestErrorMessage(err, '举报提交失败'))
      return false
    }
    finally {
      submitting.value = false
    }
  }

  if (options.autoLoad !== false) {
    watch(() => toValue(appKey), () => {
      load()
    }, { immediate: true })
  }

  return {
    summary,
    reviews,
    myReview,
    loading,
    submitting,
    error,
    load,
    submitReview,
    deleteMyReview,
    submitReport,
  }
}

function createEmptySummary(): ReviewSummary {
  return {
    average: 0,
    count: 0,
    distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 },
  }
}

function reviewStatusMessage(status: SubmitReviewResponse['status']): string {
  if (status === 'published')
    return '评论已发布'
  if (status === 'rejected')
    return '内容涉嫌违规，未能发布'
  return '已提交，审核通过后展示'
}

function getRequestErrorMessage(error: unknown, fallback: string): string {
  if (isRecord(error)) {
    const data = error.data
    if (isRecord(data)) {
      const message = data.statusMessage || data.message
      if (typeof message === 'string' && message)
        return message
    }
    const message = error.statusMessage || error.message
    if (typeof message === 'string' && message)
      return message
  }
  if (error instanceof Error && error.message)
    return error.message
  return fallback
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
