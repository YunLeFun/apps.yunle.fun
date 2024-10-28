<script setup lang="ts">
import consola from 'consola'
import Toast from 'primevue/toast'

import { appName } from '~/constants'

// init log
consola.level = import.meta.env.DEV ? 4 : 3

const isMobile = useMediaQuery('(max-width: 768px)')
const position = computed(() => {
  return isMobile.value ? 'bottom-center' : 'top-right'
})

useHead({
  title: appName,
})
</script>

<template>
  <!-- <VitePwaManifest /> -->
  <ClientOnly>
    <Toast :position="position" />
  </ClientOnly>

  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
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
}

html.dark {
  background: #222;
  color: white;
}
</style>
