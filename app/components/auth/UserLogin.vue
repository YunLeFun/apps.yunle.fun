<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonCardContent } from '@ionic/vue'

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
  <DarkToggle class="absolute right-4 top-4" />

  <div
    class="w-full flex items-center justify-center"
    m="auto"
    max-w-md
  >
    <IonCardContent class="p-6">
      <LoginForApp v-if="appInfo" :app-info="appInfo" />

      <WxLoginCard />
    </IonCardContent>
  </div>
</template>
