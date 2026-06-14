import type { MyReportItem, MyReportListResponse } from '~/types/review'

interface ApiResponse<T> {
  code: 0
  data: T
}

/** 「我的举报」数据源：拉取当前用户提交的举报及处理状态。 */
export function useMyReports() {
  const { $api } = useNuxtApp()
  const userStore = useUserStore()

  const reports = ref<MyReportItem[]>([])
  const loading = ref(false)
  const loaded = ref(false)

  async function load() {
    if (!userStore.isLoggedIn) {
      reports.value = []
      loaded.value = true
      return
    }
    loading.value = true
    try {
      const res = await $api<ApiResponse<MyReportListResponse>>('/api/reports')
      reports.value = res.data.reports
    }
    catch (err) {
      console.warn('[my-reports] load failed', err)
      reports.value = []
    }
    finally {
      loading.value = false
      loaded.value = true
    }
  }

  return {
    reports,
    loading,
    loaded,
    load,
  }
}
