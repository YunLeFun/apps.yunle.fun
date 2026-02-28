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
</script>

<template>
  <!-- <VitePwaManifest /> -->

  <k-provider theme="parent" :dark="isDark">
    <IonApp>
      <IonRouterOutlet />
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
}

html.dark {
  background: #222;
  color: white;
}
</style>
