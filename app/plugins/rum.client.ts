import Aegis from 'aegis-web-sdk'
import consola from 'consola'

/**
 * 腾讯云 RUM（前端性能监控 / 错误上报）
 *
 * 接入步骤详见 docs/dev/rum.md
 *
 * 启用条件：
 *   - 环境变量 NUXT_PUBLIC_RUM_APP_ID 非空（默认已填线上 AppID）
 *   - 非本地开发环境（本地默认不上报；设 NUXT_PUBLIC_RUM_DEBUG=true 可强制开启用于联调）
 *
 * 默认行为：
 *   - 上报 JS 异常 / unhandledrejection / 资源加载错误
 *   - 上报接口测速、静态资源测速、Web Vitals、SPA pv
 *   - 用户登录后自动用 userStore.userInfo.id 作为 uin，便于按用户聚合错误
 *
 * 关闭：清空 `nuxt.config.ts` 的 `runtimeConfig.public.rumAppId` 即可
 */
export default defineNuxtPlugin(() => {
  if (import.meta.env?.MODE === 'test')
    return

  const config = useRuntimeConfig()
  const appId = (config.public as any).rumAppId as string | undefined
  const debug = (config.public as any).rumDebug === true

  if (!appId) {
    if (debug)
      consola.info('[RUM] disabled: rumAppId 未配置')
    return
  }

  // 本地开发默认不上报，避免消耗免费额度、污染线上数据；rumDebug=true 时强制开启用于联调
  if (import.meta.dev && !debug) {
    return
  }

  try {
    const aegis = new Aegis({
      id: appId,
      uin: '',
      reportApiSpeed: true, // 接口测速
      reportAssetSpeed: true, // 静态资源测速
      spa: true, // SPA pv 自动追踪
      hostUrl: 'https://rumt-zh.com',
      // 环境标记，便于在 RUM 控制台过滤
      env: import.meta.dev ? 'dev' : 'production',
    } as any)

    // 用户登录态变化时同步 uin（用于按用户聚合错误）
    const userStore = useUserStore()
    watchEffect(() => {
      const uid = userStore.userInfo?.id
      if (uid) {
        try {
          aegis.setConfig?.({ uin: uid })
        }
        catch {
          // setConfig 在某些 SDK 版本叫别的名，静默忽略
        }
      }
    })

    // 暴露到全局，业务代码可手动 captureException / captureMessage
    if (typeof window !== 'undefined') {
      ;(window as any).$rum = aegis
    }

    if (debug)
      consola.info('[RUM] initialized with appId', appId)
  }
  catch (err) {
    consola.warn('[RUM] init failed:', (err as Error).message)
  }
})
