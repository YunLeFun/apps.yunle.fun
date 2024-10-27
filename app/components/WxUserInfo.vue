<script setup lang="ts">
import type { WxUserInfo } from '../utils'

defineProps<{
  userInfo?: WxUserInfo
}>()
</script>

<template>
  <div flex="~ col" class="gap-1">
    <div flex="~ col" class="gap-1">
      <Avatar
        :image="userInfo?.headimgurl" alt="头像"
        shape="circle"
        size="large"
      />

      <div>
        {{ userInfo?.nickname }}
      </div>
    </div>

    <div
      v-for="(value, key) in userInfo"
      :key="key"
      class="flex gap-1"
    >
      <span>{{ key }}:</span>
      <span class="max-w-25 truncate op-60">{{ value }}</span>
    </div>
  </div>
</template>
