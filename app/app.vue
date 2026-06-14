<script setup lang="ts">
import consola from 'consola'
import { kProvider } from 'konsta/vue'

import { appName } from '~/constants'

// init log
consola.level = import.meta.env.DEV ? 4 : 3

useHead({
  title: appName,
})

const colorMode = useColorMode()
const isDark = computed(() => colorMode.value === 'dark')

// 登录态长期保持：应用启动时检查、从后台恢复时自动刷新、网络恢复时自动刷新
if (import.meta.client) {
  const { checkAuthStatus, ensureValidToken } = useCloudbaseAuth()
  const userStore = useUserStore()

  // 应用启动时：无条件检查会话。cookie 可能在原生壳重启/更新后丢失，
  // 但 CloudBase refresh_token（localStorage）仍在时可恢复登录态，不能以 isLoggedIn 把门
  onMounted(async () => {
    await checkAuthStatus()
  })

  // 应用从后台恢复时：检查 token 有效性并自动刷新
  onMounted(() => {
    const handleVisibilityChange = async () => {
      if (document.visibilityState === 'visible' && userStore.isLoggedIn) {
        consola.debug('[Auth] 应用恢复前台，检查 token 有效性')
        await ensureValidToken()
      }
    }
    document.addEventListener('visibilitychange', handleVisibilityChange)
    onUnmounted(() => {
      document.removeEventListener('visibilitychange', handleVisibilityChange)
    })
  })

  // 网络恢复时：自动刷新 token（应对离线后 token 过期的场景）
  onMounted(() => {
    const handleOnline = async () => {
      if (userStore.isLoggedIn) {
        consola.debug('[Auth] 网络恢复，检查 token 有效性')
        await ensureValidToken()
      }
    }
    window.addEventListener('online', handleOnline)
    onUnmounted(() => {
      window.removeEventListener('online', handleOnline)
    })
  })
}
</script>

<template>
  <!-- <VitePwaManifest /> -->

  <k-provider theme="parent" :dark="isDark">
    <IonApp>
      <IonRouterOutlet />
      <AppToast />
    </IonApp>
  </k-provider>
</template>

<style lang="scss">
@use 'sass:color';
@use '~/styles/scss/3d-room/vars' as *;

html,
body,
#__nuxt {
  width: 100%;
  height: 100vh;
  margin: 0;
  padding: 0;
  overflow: hidden;
}

html.dark {
  background: #222;
  color: white;
}
</style>
