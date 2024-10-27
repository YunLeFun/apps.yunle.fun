<script setup lang="ts">
import { appName } from '~/constants'

useHead({
  title: appName,
})
</script>

<template>
  <VitePwaManifest />
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

body {
  display: flex;
  justify-content: center;
  align-items: center;

  overflow: hidden;
  background-image: radial-gradient(circle, $bg-1, color.adjust($bg-1, $lightness: -20%));
}
</style>
