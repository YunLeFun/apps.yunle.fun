<script setup lang="ts">
import type { WorkshopPublicInfo } from '~/types/workshop'
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonPage,
  IonTitle,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import {
  alertCircleOutline,
  chevronForwardOutline,
  peopleOutline,
  refreshOutline,
} from 'ionicons/icons'

const router = useRouter()
const workshopModule = usePersonalWorkshop()
const loading = ref(true)
const workshops = ref<WorkshopPublicInfo[]>([])
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    workshops.value = await workshopModule.getJoined()
  }
  catch (reason: unknown) {
    workshops.value = []
    error.value = reason instanceof Error ? reason.message : '已加入的工坊加载失败'
  }
  finally {
    loading.value = false
  }
}

onIonViewWillEnter(load)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="" />
        </IonButtons>
        <IonTitle>已加入的工坊</IonTitle>
      </IonToolbar>
    </IonHeader>
    <IonContent :fullscreen="true">
      <AppPageLoading v-if="loading" label="正在加载已加入的工坊" />
      <div v-else-if="error" class="joined-empty">
        <IonIcon :icon="alertCircleOutline" />
        <h1>无法加载已加入的工坊</h1>
        <p>{{ error }}</p>
        <IonButton fill="outline" @click="load">
          <IonIcon slot="start" :icon="refreshOutline" />
          重试
        </IonButton>
      </div>
      <IonList v-else-if="workshops.length" inset>
        <IonItem
          v-for="workshop in workshops"
          :key="workshop._id"
          button
          :detail="false"
          @click="router.push(`/w/${workshop._id}`)"
        >
          <IonIcon slot="start" :icon="peopleOutline" color="primary" />
          <IonLabel>
            <h2>{{ workshop.name }}</h2>
            <p>{{ workshop.ownerName }} · {{ workshop.description || '个人工坊' }}</p>
          </IonLabel>
          <IonIcon slot="end" :icon="chevronForwardOutline" color="medium" />
        </IonItem>
      </IonList>
      <div v-else class="joined-empty">
        <IonIcon :icon="peopleOutline" />
        <h1>还没有加入个人工坊</h1>
        <p>扫描坊主分享的二维码，申请通过后会显示在这里。</p>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.joined-empty {
  min-height: 60vh;
  padding: 72px 28px 32px;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: center;
}

.joined-empty ion-icon {
  font-size: 40px;
  color: var(--ion-color-primary);
}

.joined-empty h1 {
  margin: 18px 0 6px;
}

.joined-empty p {
  margin: 0;
  color: var(--ion-color-medium);
  line-height: 1.5;
}
</style>
