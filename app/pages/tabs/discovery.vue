<script setup lang="ts">
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { personCircleOutline } from 'ionicons/icons'

definePageMeta({
  // discovery 页面不需要别名
})

const { loading, loadAll } = useDiscovery()

onMounted(() => loadAll())
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>
          寻乐
        </IonTitle>
        <IonButtons slot="end">
          <IonButton router-link="/tabs/me">
            <IonIcon slot="icon-only" :icon="personCircleOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <div class="px-4 pb-4 pt-2">
        <!-- 加载骨架屏 -->
        <div v-if="loading" class="space-y-4">
          <div class="h-80 animate-pulse rounded-2xl bg-gray-200 dark:bg-gray-800" />
          <div class="h-64 animate-pulse rounded-2xl bg-gray-200 dark:bg-gray-800" />
        </div>

        <template v-else>
          <!-- 今日推荐 -->
          <AppFeatured managed />

          <!-- 本周热门排行榜 -->
          <AppWeeklyChart managed />
        </template>
      </div>
    </IonContent>
  </IonPage>
</template>
