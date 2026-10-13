<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'

const router = useRouter()
const { weeklyApps, loadWeeklyChart } = useDiscovery()

onMounted(() => loadWeeklyChart())

function openAppDetail(app: YlfAppInfo) {
  router.push(`/app/${app.slug || app.id}`)
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/discovery" text="返回" />
        </IonButtons>
        <IonTitle>本周热门</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div v-if="weeklyApps.length" class="weekly-list">
        <div
          v-for="(app, index) in weeklyApps"
          :key="app.slug || app.id"
          class="weekly-item"
          role="link"
          tabindex="0"
          @click="openAppDetail(app)"
          @keydown.enter="openAppDetail(app)"
          @keydown.space.prevent="openAppDetail(app)"
        >
          <span class="weekly-rank" :class="{ 'weekly-rank--top': index < 3 }">
            {{ index + 1 }}
          </span>
          <AppIconBox
            class="weekly-icon"
            :icon="app.logo"
            :icon-assets="app.iconAssets"
            :emoji="app.emoji"
            :color="app.themeColor"
            size="md"
          />
          <span class="weekly-info">
            <strong class="weekly-name">{{ app.name }}</strong>
            <span class="weekly-description">{{ app.description }}</span>
            <span class="weekly-category">{{ app.category }}</span>
          </span>
          <AppInstallButton :app="app" />
        </div>
      </div>

      <div v-else class="weekly-empty">
        本周榜单暂未更新
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.weekly-list {
  margin: 12px 16px 24px;
  overflow: hidden;
  border-radius: 16px;
  background: var(--ion-background-color-step-100);
  box-shadow: 0 2px 12px rgb(0 0 0 / 8%);
}

.weekly-item {
  position: relative;
  display: flex;
  width: 100%;
  align-items: center;
  gap: 12px;
  border: 0;
  padding: 12px;
  color: var(--ion-text-color);
  background: transparent;
  text-align: left;
  font: inherit;
}

.weekly-item:not(:last-child)::after {
  position: absolute;
  right: 12px;
  bottom: 0;
  left: 104px;
  height: 0.5px;
  background: var(--ion-border-color, rgb(0 0 0 / 10%));
  content: '';
}

.weekly-item:active {
  opacity: 0.7;
}

.weekly-rank {
  width: 20px;
  flex-shrink: 0;
  color: var(--ion-color-medium);
  font-size: 17px;
  font-weight: 700;
  text-align: center;
}

.weekly-rank--top {
  color: var(--ion-color-primary);
}

.weekly-icon {
  flex-shrink: 0;
}

.weekly-info {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-direction: column;
  gap: 2px;
}

.weekly-name,
.weekly-description {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.weekly-name {
  font-size: 16px;
}

.weekly-description,
.weekly-category {
  color: var(--ion-color-medium);
}

.weekly-description {
  font-size: 13px;
}

.weekly-category {
  font-size: 12px;
}

.weekly-empty {
  padding: 64px 24px;
  color: var(--ion-color-medium);
  text-align: center;
}

@media (prefers-color-scheme: dark) {
  .weekly-list {
    box-shadow: 0 2px 12px rgb(0 0 0 / 30%);
  }
}
</style>
