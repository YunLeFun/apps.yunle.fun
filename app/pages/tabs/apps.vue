<script setup lang="ts">
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonLabel,
  IonPage,
  IonSearchbar,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { peopleOutline, qrCodeOutline } from 'ionicons/icons'

const {
  searchQuery,
  selectedCategory,
  categories,
  changeCategory,
  debouncedSearch,
  queryApps,
} = useWorkshop()

const router = useRouter()
const { navigateToScan } = useScanBridge()
const { handleScanResult } = useWorkshopScan()

function startScanFlow() {
  navigateToScan(handleScanResult)
}

onMounted(() => queryApps(true))

function handleSegmentChange(event: CustomEvent) {
  changeCategory(event.detail.value)
}

function handleSearchInput() {
  debouncedSearch()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>公共市场</IonTitle>
        <IonButtons slot="end">
          <IonButton aria-label="已加入的工坊" @click="router.push('/user/workshops')">
            <IonIcon slot="icon-only" :icon="peopleOutline" />
          </IonButton>
          <IonButton aria-label="扫码加入个人工坊" @click="startScanFlow">
            <IonIcon slot="icon-only" :icon="qrCodeOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>

      <IonToolbar>
        <IonSearchbar
          v-model="searchQuery"
          placeholder="游戏、App 等"
          :animated="true"
          show-cancel-button="focus"
          class="app-store-searchbar"
          mode="ios"
          @ion-input="handleSearchInput"
          @ion-clear="handleSearchInput"
        />
      </IonToolbar>

      <IonToolbar>
        <IonSegment
          :value="selectedCategory"
          scrollable
          mode="ios"
          @ion-change="handleSegmentChange"
        >
          <IonSegmentButton
            v-for="category in categories"
            :key="category.id"
            :value="category.name"
          >
            <IonLabel>{{ category.name }}</IonLabel>
          </IonSegmentButton>
        </IonSegment>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div class="content-wrapper">
        <AppList />
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
/* ==================== 搜索栏 ==================== */
.app-store-searchbar {
  --background: var(--ylf-fill-tertiary);
  --border-radius: 10px;
  --box-shadow: none;
  --cancel-button-color: var(--ion-color-primary);
  --placeholder-color: var(--ylf-label-secondary);
  --icon-color: var(--ylf-label-secondary);
  --clear-button-color: var(--ylf-label-secondary);
  padding: 0 16px;
  font-size: 17px;
  font-weight: 400;
}

.app-store-searchbar::part(native) {
  height: 36px;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.app-store-searchbar::part(native):focus-within {
  --background: var(--ylf-fill-secondary);
}

/* ==================== Content 区域 ==================== */
.content-wrapper {
  padding: 0 16px 16px;
}

/* ==================== 响应式设计 ==================== */
@media (min-width: 768px) {
  .content-wrapper {
    max-width: 980px;
    margin: 0 auto;
    padding: 0 24px 24px;
  }
}

@media (min-width: 1024px) {
  .content-wrapper {
    max-width: 1200px;
    padding: 0 32px 32px;
  }
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .app-store-searchbar::part(native) {
    transition: none;
  }
}

/* Dark mode 不再需要单独覆盖 —— 所有颜色已经通过 CSS 变量
   在浅/深色之间自动切换（见 css-vars.css 与 Ionic 调色板） */
</style>
