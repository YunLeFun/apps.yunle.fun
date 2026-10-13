import type { CloudBase, ICloudBaseConfig } from '@cloudbase/node-sdk'
import { createRequire } from 'node:module'
import { resolveCloudbaseAdminInitConfig } from './cloudbase-config'

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
export type CloudbaseAdminDb = ReturnType<CloudbaseAdminApp['database']>
export interface CloudbaseTransaction {
  collection: (name: string) => ReturnType<CloudbaseAdminDb['collection']>
}

let cachedApp: CloudbaseAdminApp | null = null
let cachedDb: CloudbaseAdminDb | null = null
let cachedKey = ''

export function useCloudbaseAdmin(): { app: CloudbaseAdminApp, db: CloudbaseAdminDb } {
  const config = useRuntimeConfig()
  const initConfig = resolveCloudbaseAdminInitConfig(config)

  const cacheKey = `${String(initConfig.env || '')}:${initConfig.secretId || 'default'}`
  if (cachedApp && cachedDb && cachedKey === cacheKey) {
    return { app: cachedApp, db: cachedDb }
  }

  cachedApp = loadCloudbase().init(initConfig)
  cachedDb = cachedApp.database()
  cachedKey = cacheKey

  return { app: cachedApp, db: cachedDb }
}
