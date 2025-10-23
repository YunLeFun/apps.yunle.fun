<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonCardContent } from '@ionic/vue'

defineProps<{
  /**
   * 是否微信登录
   */
  wxLogin: boolean
}>()

const appInfo = ref<YlfAppInfo>()

const route = useRoute()

onMounted(() => {
  $fetch('/api/app/search', {
    method: 'GET',
    query: {
      id: route.query.appId,
    },
  }).then((res) => {
    if ('data' in res) {
      appInfo.value = res.data
    }
  })
})
</script>

<template>
  <div
    class="w-full flex items-center justify-center"
    m="auto"
    max-w-md
  >
    <IonCardContent class="p-6">
      <LoginForApp v-if="appInfo" :app-info="appInfo" />

      <WxLoginCard v-if="wxLogin" />
    </IonCardContent>
  </div>
</template>
