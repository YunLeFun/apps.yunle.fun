import type { CloudBase, ICloudBaseConfig } from '@cloudbase/node-sdk'
import { createRequire } from 'node:module'

interface CloudbaseModule {
  init: (config?: ICloudBaseConfig) => CloudBase
}

let cloudbaseModule: CloudbaseModule | null = null

// 惰性加载：prerender 阶段 nitro 以虚拟入口执行顶层代码，require 会解析失败
function loadCloudbase(): CloudbaseModule {
  if (!cloudbaseModule) {
    const require = createRequire(import.meta.url)
    cloudbaseModule = require('@cloudbase/node-sdk') as CloudbaseModule
  }
  return cloudbaseModule
}

type CloudbaseAdminApp = CloudBase
type CloudbaseAdminDb = ReturnType<CloudbaseAdminApp['database']>

let cachedApp: CloudbaseAdminApp | null = null
let cachedDb: CloudbaseAdminDb | null = null
let cachedKey = ''

export function useCloudbaseAdmin(): { app: CloudbaseAdminApp, db: CloudbaseAdminDb } {
  const config = useRuntimeConfig()
  const env = config.public.tcbEnvId
  const secretId = config.tencentApiSecretId
  const secretKey = config.tencentApiSecretKey

  if (!env) {
    throw createError({
      statusCode: 500,
      message: 'CloudBase 环境未配置',
    })
  }
  if (!secretId || !secretKey) {
    throw createError({
      statusCode: 500,
      message: 'CloudBase 管理端凭证未配置',
    })
  }

  const cacheKey = `${env}:${secretId}`
  if (cachedApp && cachedDb && cachedKey === cacheKey) {
    return { app: cachedApp, db: cachedDb }
  }

  cachedApp = loadCloudbase().init({
    env,
    secretId,
    secretKey,
  })
  cachedDb = cachedApp.database()
  cachedKey = cacheKey

  return { app: cachedApp, db: cachedDb }
}
