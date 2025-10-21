<script setup lang="ts">
import consola from 'consola'

import { appName } from '~/constants'

// init log
consola.level = import.meta.env.DEV ? 4 : 3

useHead({
  title: appName,
})
</script>

<template>
  <!-- <VitePwaManifest /> -->

  <!-- <NuxtLayout>
    <NuxtPage />
  </NuxtLayout> -->

  <IonApp>
    <IonRouterOutlet />
  </IonApp>
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
