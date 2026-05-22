import consola from 'consola'

/**
 * 腾讯云 RUM（前端性能监控 / 错误上报）
 *
 * 接入步骤详见 docs/dev/rum.md
 *
 * 启用条件：
 *   - 环境变量 NUXT_PUBLIC_RUM_APP_ID 非空
 *   - 安装了 rum-mp-vue 依赖（按需，未安装则 plugin 安静跳过）
 *
 * 默认行为：
 *   - 上报 JS 异常 / 资源错误 / Web Vitals / PV / 用户操作链路
 *   - 不上报 PII（用户 ID 默认不带，需要业务代码主动 setUid）
 *
 * 关闭：直接清空 NUXT_PUBLIC_RUM_APP_ID 即可
 */
export default defineNuxtPlugin(async () => {
  const config = useRuntimeConfig()
  const appId = (config.public as any).rumAppId as string | undefined
  const debug = (config.public as any).rumDebug === true

  if (!appId) {
    if (debug)
      consola.info('[RUM] disabled: NUXT_PUBLIC_RUM_APP_ID 未配置')
    return
  }

  try {
    // 按需加载，避免没接入时增加包体积
    // @ts-expect-error 包未安装时 vite 会在构建时跳过，运行时也走 catch
    const mod = await import('rum-mp-vue')
    const Aegis = mod.default ?? mod

    const rum = new Aegis({
      id: appId,
      uin: '',
      reportApiSpeed: true,
      reportAssetSpeed: true,
      spa: true,
      hostUrl: 'https://rumt-zh.com',
      pvUrl: location.origin + location.pathname,
      env: import.meta.dev ? 'dev' : 'production',
    })

    // 暴露到全局供业务代码使用（auth/cloudbase 调用失败时手动上报）
    if (typeof window !== 'undefined') {
      ;(window as any).$rum = rum
    }

    if (debug)
      consola.info('[RUM] initialized with appId', appId)
  }
  catch (err) {
    consola.warn('[RUM] init skipped:', (err as Error).message)
  }
})
