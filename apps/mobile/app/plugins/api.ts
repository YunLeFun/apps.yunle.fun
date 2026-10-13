import { Capacitor } from '@capacitor/core'
import { NATIVE_API_BASE_URL } from '~/constants/api'

export default defineNuxtPlugin((nuxtApp) => {
  const userStore = useUserStore()
  const config = useRuntimeConfig()

  /**
   * 打包进原生壳后页面 origin 是 capacitor://localhost（无 Nitro server），
   * /api 默认回退到线上 Web 部署；live reload（cap run -l，origin 为局域网
   * dev server）不回退，仍走同源的本地 Nitro。
   */
  const isPackagedNative = typeof window !== 'undefined'
    && Capacitor.isNativePlatform()
    && window.location.hostname === 'localhost'
  const baseURL = config.public.apiBaseUrl
    || (isPackagedNative ? NATIVE_API_BASE_URL : undefined)

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
