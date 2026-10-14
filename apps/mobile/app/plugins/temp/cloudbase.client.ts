import cloudbase from '@cloudbase/js-sdk'
import { consola } from 'consola'

/**
 * CloudBase SDK 客户端插件
 * 通过 CDN 加载 CloudBase SDK
 */
export default defineNuxtPlugin(() => {
  // 仅在客户端加载
  if (import.meta.server)
    return

  const config = useRuntimeConfig()
  const tcbEnvId = config.public.tcbEnvId
  if (!tcbEnvId) {
    consola.error('未设置 TCB_ENV_ID')
    return
  }

  const tcbApp = cloudbase.init({
    env: tcbEnvId,
  })
  const tcbAuth = tcbApp.auth()
  consola.success('Init CloudBase SDK')

  return {
    provide: {
      tcbApp,
      tcbAuth,
    },
  }
})
