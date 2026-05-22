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
import { chevronBackOutline, homeOutline } from 'ionicons/icons'

const router = useRouter()
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonButton @click="router.back()">
            <IonIcon slot="icon-only" :icon="chevronBackOutline" />
          </IonButton>
        </IonButtons>
        <IonTitle>页面未找到</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="ion-padding">
      <div class="not-found">
        <div class="not-found__icon">
          <IonIcon :icon="homeOutline" />
        </div>
        <h2 class="not-found__title">
          404
        </h2>
        <p class="not-found__desc">
          页面不存在或已被移除
        </p>
        <IonButton expand="block" @click="router.replace('/tabs/home')">
          返回首页
        </IonButton>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped lang="scss">
.not-found {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 60vh;
  padding: 24px;
  text-align: center;

  &__icon {
    font-size: 64px;
    color: var(--ion-color-medium);
    margin-bottom: 16px;
  }

  &__title {
    font-size: 48px;
    font-weight: 700;
    margin: 0 0 8px;
    color: var(--ion-text-color);
  }

  &__desc {
    color: var(--ion-color-medium);
    margin: 0 0 32px;
  }
}
</style>
