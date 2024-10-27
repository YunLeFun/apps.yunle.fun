<script setup lang="ts">
import type { WxUserInfo } from '../utils'

defineProps<{
  userInfo?: WxUserInfo
}>()
</script>

<template>
  <div flex="~ col" class="gap-1">
    <div
      v-for="(value, key) in userInfo"
      :key="key"
    >
      <span>{{ key }}: </span>
      <span>{{ value }}</span>
    </div>
  </div>
</template>
