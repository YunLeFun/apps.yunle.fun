<script setup lang="ts">
const route = useRoute()

// The root document is served separately. A client-side navigation must load it.
onMounted(() => {
  window.location.replace(route.fullPath)
})
</script>

<template>
  <a href="/">打开云乐坊下载页</a>
</template>
