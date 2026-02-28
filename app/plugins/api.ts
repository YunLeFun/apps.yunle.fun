export default defineNuxtPlugin((nuxtApp) => {
  const userStore = useUserStore()

  const api = $fetch.create({
    onRequest({ options }) {
      if (userStore.accessToken) {
        options.headers.set('Authorization', `Bearer ${userStore.accessToken}`)
      }
    },
    async onResponseError({ request, options, response }) {
      if (response.status === 401) {
        // 尝试通过 refresh token 刷新 access_token
        try {
          const { ensureValidToken } = useCloudbaseAuth()
          const refreshed = await ensureValidToken()
          if (refreshed) {
            // token 已刷新，用新 token 重试原请求
            const retryHeaders = new Headers(options.headers)
            retryHeaders.set('Authorization', `Bearer ${userStore.accessToken}`)
            const retryResponse = await $fetch.raw(request, {
              ...options,
              headers: retryHeaders,
              method: options.method as 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH',
            })
            // 将重试结果写回 response（ofetch 会使用此数据）
            Object.defineProperty(response, '_data', { value: retryResponse._data })
            return
          }
        }
        catch (err) {
          console.error('[API] Token 刷新失败:', err)
        }
        // 刷新失败，跳转登录页
        await nuxtApp.runWithContext(() => navigateTo('/login'))
      }
    },
  })

  return {
    provide: {
      api,
    },
  }
})
