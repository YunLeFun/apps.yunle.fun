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
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>
          云乐坊
        </IonTitle>
        <IonButtons slot="end">
          <IonButton>
            <IonIcon slot="icon-only" :icon="personCircleOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <div class="p-4">
        <!-- 今日推荐 -->
        <AppFeatured />

        <!-- 可以添加更多首页内容 -->
        <!-- <YlfHouse /> -->
      </div>
    </IonContent>
  </IonPage>
</template>
