/**
 * CloudBase SDK 初始化 composable
 * 参考 www.yunle.fun 的实现，使用 cloudbase.init() + useNuxtApp() 缓存
 */
import cloudbase from '@cloudbase/js-sdk'

type TcbApp = ReturnType<typeof cloudbase.init>
type TcbAuth = ReturnType<TcbApp['auth']>

export function useCloudbase() {
  const nuxtApp = useNuxtApp()
  const config = useRuntimeConfig()

  // SSR 时返回空占位，CloudBase 认证仅在客户端使用
  if (import.meta.server) {
    return { app: null as unknown as TcbApp, auth: null as unknown as TcbAuth }
  }

  // 已初始化则直接返回缓存
  const cachedApp = nuxtApp._cloudbaseApp as TcbApp | undefined
  const cachedAuth = nuxtApp._cloudbaseAuth as TcbAuth | undefined
  if (cachedApp && cachedAuth) {
    return { app: cachedApp, auth: cachedAuth }
  }

  // 初始化 CloudBase SDK
  const app: TcbApp = cloudbase.init({
    env: config.public.tcbEnvId as string,
    region: config.public.cloudbaseRegion as string || undefined,
    accessKey: config.public.cloudbaseAccessKey as string || undefined,
    persistence: 'local' as const,
    auth: {
      detectSessionInUrl: true,
    },
  })
  const auth: TcbAuth = app.auth({ persistence: 'local' })

  nuxtApp._cloudbaseApp = app
  nuxtApp._cloudbaseAuth = auth

  return { app, auth }
}

export type { TcbApp, TcbAuth }
