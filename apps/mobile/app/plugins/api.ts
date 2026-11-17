export default defineNuxtPlugin((nuxtApp) => {
  const userStore = useUserStore()
  const config = useRuntimeConfig()

  const baseURL = config.public.apiBaseUrl || undefined

  const api = $fetch.create({
    baseURL,
    // 401 时先在 onResponseError 中刷新 token，再由 ofetch 自动重试一次
    // （重试会重新走 onRequest，自动带上刷新后的 token）
    retry: 1,
    retryStatusCodes: [401],
    onRequest({ options }) {
      if (userStore.accessToken) {
        options.headers.set('Authorization', `Bearer ${userStore.accessToken}`)
      }
    },
    async onResponseError({ options, response }) {
      if (response.status !== 401)
        return

      // 强制刷新 access_token：服务端已明确拒绝当前 token，
      // 本地过期记录不可信（时钟偏差/服务端撤销/store 与 SDK token 不一致）
      try {
        const { ensureValidToken } = useCloudbaseAuth()
        if (await ensureValidToken({ force: true }))
          return
      }
      catch (err) {
        console.error('[API] Token 刷新失败:', err)
      }

      // 刷新失败：取消重试。仅当登录态确已清除（凭证失效）时跳登录页；
      // 临时网络失败保留登录态，本次请求错误交由调用方处理
      options.retry = false
      if (!userStore.isLoggedIn)
        await nuxtApp.runWithContext(() => navigateTo('/login'))
    },
  })

  return {
    provide: {
      api,
    },
  }
})
