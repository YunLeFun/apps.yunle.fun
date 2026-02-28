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
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>
          云乐坊
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
        <!-- 今日推荐 -->
        <AppFeatured />

        <!-- 本周热门排行榜 -->
        <AppWeeklyChart />
      </div>
    </IonContent>
  </IonPage>
</template>
