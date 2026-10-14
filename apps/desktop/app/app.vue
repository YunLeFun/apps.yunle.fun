<script setup lang="ts">
const colorMode = useColorMode()
function syncTheme() {
  const preference = colorMode.preference
  if (preference === 'system' || preference === 'light' || preference === 'dark')
    void window.desktop?.setTheme(preference).catch(() => undefined)
}
onMounted(syncTheme)
watch(() => colorMode.preference, syncTheme)
</script>

<template>
  <NuxtPage />
</template>
