<script setup lang="ts">
import type { WxUserInfo } from '~/utils/wx/types'

interface Props {
  userInfo?: WxUserInfo
}

defineProps<Props>()
</script>

<template>
  <div class="flex flex-col gap-1 py-4">
    <div class="flex flex-col gap-1">
      <Avatar
        :image="(userInfo as WxUserInfo)?.headimgurl" alt="头像"
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
      <span class="max-w-40 truncate opacity-60">{{ value }}</span>
    </div>
  </div>
</template>
