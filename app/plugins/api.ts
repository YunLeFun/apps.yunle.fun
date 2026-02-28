export default defineNuxtPlugin((nuxtApp) => {
  const userStore = useUserStore()

  const api = $fetch.create({
    // baseURL: import.meta.env.DEV ? '/api' : 'https://api.yunle.fun',
    onRequest({ options }) {
      if (userStore.accessToken) {
        // note that this relies on ofetch >= 1.4.0 - you may need to refresh your lockfile
        options.headers.set('Authorization', `Bearer ${userStore.accessToken}`)
      }
    },
    async onResponseError({ response }) {
      if (response.status === 401) {
        // 尝试通过 refresh token 刷新 access_token
        try {
          const { ensureValidToken } = useCloudbaseAuth()
          const refreshed = await ensureValidToken()
          if (refreshed) {
            // token 已刷新，但 ofetch 不支持自动重试，由调用方处理
            console.warn('[API] Token 已刷新，请重试请求')
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

  // Expose to useNuxtApp().$api
  return {
    provide: {
      api,
    },
  }
})
