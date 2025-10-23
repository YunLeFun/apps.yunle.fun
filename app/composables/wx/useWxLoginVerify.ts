import type { YlfWxAuthResponse } from '@yunlefun/auth'
import { createYlfVerifyWxCode } from '@yunlefun/auth'

import { consola } from 'consola'

/**
 * 使用 code 向 api.yunle.fun 换取 access_token
 */
export function useWxLoginVerify(options: {
  success?: (res: YlfWxAuthResponse) => void
}) {
  const route = useRoute()

  /**
   * 有 code 登录鉴权中
   */
  const hasCode = computed(() => !!route.query.code)

  const loading = ref(false)
  const errorMessage = ref('')

  onMounted(async () => {
    if (hasCode.value) {
      const { verifyCode } = createYlfVerifyWxCode()
      const code = route.query.code as string
      const state = route.query.state as string

      loading.value = true
      errorMessage.value = ''

      // jwt 授权重定向成功
      try {
        const res = await verifyCode({
          code,
          state,
        })

        if (res.access_token) {
          options.success?.(res)
        }
        else {
          consola.error(res)
          errorMessage.value = '登录失败，请重试'
        }
      }
      catch (error) {
        consola.error('登录失败:', error)
        errorMessage.value = '登录失败，请检查网络连接后重试'
      }
      finally {
        loading.value = false
      }
    }
  })

  return {
    hasCode,
    loading,
    errorMessage,
  }
}
