<script setup lang="ts">
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonLabel,
  IonPage,
  IonPopover,
  IonSearchbar,
  IonSegment,
  IonSegmentButton,
  IonToolbar,
} from '@ionic/vue'
import { addOutline, chevronDownOutline, trashOutline } from 'ionicons/icons'
import { OFFICIAL_MARKET_ID } from '~/stores/marketSources'

const {
  searchQuery,
  selectedCategory,
  categories,
  changeCategory,
  debouncedSearch,
  queryApps,
} = useWorkshop()

// 市场切换
const marketStore = useMarketSourcesStore()

// 下拉菜单
const popoverOpen = ref(false)
const popoverEvent = ref<Event>()

function openPopover(e: Event) {
  popoverEvent.value = e
  popoverOpen.value = true
}

function selectSource(id: string) {
  marketStore.switchSource(id)
  popoverOpen.value = false
}

function removeSource(id: string) {
  marketStore.removeSource(id)
  // 如果删完了，自动关闭 popover
  if (marketStore.sources.length === 0)
    popoverOpen.value = false
}

/** 当前显示的市场名称 */
const activeMarketName = computed(() => {
  if (marketStore.isOfficial)
    return '工坊'
  return marketStore.activeSource?.name || '工坊'
})

// 扫码添加第三方市场
const { showScanner, openScanner, closeScanner } = useScanner()
const { handleScanResult } = useMarketScan()

async function handleMarketScan() {
  popoverOpen.value = false
  const result = await openScanner()
  if (result) {
    handleScanResult(result)
  }
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
        <!-- 左侧：市场切换下拉菜单 -->
        <IonButtons slot="start">
          <IonButton class="market-switcher" @click="openPopover">
            <span class="market-switcher-label">{{ activeMarketName }}</span>
            <IonIcon :icon="chevronDownOutline" class="ml-1 text-xs opacity-60" />
          </IonButton>
        </IonButtons>

        <!-- 市场切换弹出菜单 -->
        <IonPopover
          :is-open="popoverOpen"
          :event="popoverEvent"
          :dismiss-on-select="false"
          @did-dismiss="popoverOpen = false"
        >
          <div class="market-popover">
            <!-- 官方市场 -->
            <button
              class="market-popover-item"
              :class="{ active: marketStore.isOfficial }"
              @click="selectSource(OFFICIAL_MARKET_ID)"
            >
              <span class="market-popover-icon">☁️</span>
              <span class="market-popover-name">云乐坊</span>
              <span v-if="marketStore.isOfficial" class="market-popover-check">✓</span>
            </button>

            <!-- 分隔线（有第三方市场时） -->
            <div v-if="marketStore.sources.length > 0" class="market-popover-divider" />

            <!-- 第三方市场列表 -->
            <div
              v-for="source in marketStore.sources"
              :key="source.id"
              class="market-popover-item"
              :class="{ active: marketStore.activeSourceId === source.id }"
            >
              <button class="flex min-w-0 flex-1 items-center gap-2" @click="selectSource(source.id)">
                <span class="market-popover-icon">{{ source.icon || '📦' }}</span>
                <span class="market-popover-name">{{ source.name }}</span>
                <span v-if="marketStore.activeSourceId === source.id" class="market-popover-check">✓</span>
              </button>
              <button
                class="market-popover-delete"
                @click.stop="removeSource(source.id)"
              >
                <IonIcon :icon="trashOutline" />
              </button>
            </div>

            <!-- 扫码添加入口 -->
            <div class="market-popover-divider" />
            <button class="market-popover-item market-popover-add" @click="handleMarketScan">
              <IonIcon :icon="addOutline" class="text-base" />
              <span>添加应用市场</span>
            </button>
          </div>
        </IonPopover>
      </IonToolbar>

      <!-- 搜索栏工具栏（仅官方市场） -->
      <IonToolbar v-if="marketStore.isOfficial">
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

      <!-- 分类筛选工具栏（仅官方市场） -->
      <IonToolbar v-if="marketStore.isOfficial">
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
            <IonLabel class="inline-flex gap-2">
              <span>{{ category.icon }}</span>
              <span>{{ category.name }}</span>
            </IonLabel>
          </IonSegmentButton>
        </IonSegment>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div class="content-wrapper">
        <!-- 官方市场 -->
        <AppList v-if="marketStore.isOfficial" />

        <!-- 第三方市场应用列表 -->
        <AppMarketSection v-else :source="marketStore.activeSource" />
      </div>

      <!-- 扫码界面 -->
      <ScannerBarcode
        :is-visible="showScanner"
        :show-flashlight="true"
        @cancel="closeScanner"
        @result="handleScanResult"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
/* ==================== 市场切换器 ==================== */
.market-switcher {
  --padding-start: 12px;
  --padding-end: 8px;
  font-weight: 600;
  font-size: 17px;
  text-transform: none;
  letter-spacing: 0;
}

.market-switcher-label {
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* ==================== 市场弹出菜单 ==================== */
.market-popover {
  padding: 6px 0;
}

.market-popover-item {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 10px 16px;
  font-size: 15px;
  text-align: left;
  background: none;
  border: none;
  cursor: pointer;
  transition: background-color 0.15s;
}

.market-popover-item:active {
  background-color: rgba(0, 0, 0, 0.05);
}

.market-popover-item.active {
  color: #007aff;
}

.market-popover-icon {
  font-size: 18px;
  width: 24px;
  text-align: center;
  flex-shrink: 0;
}

.market-popover-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.market-popover-check {
  color: #007aff;
  font-size: 16px;
  font-weight: 600;
  flex-shrink: 0;
}

.market-popover-delete {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 4px;
  border: none;
  background: none;
  color: #8e8e93;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.15s;
  flex-shrink: 0;
}

.market-popover-delete:hover {
  color: #ff3b30;
  background-color: rgba(255, 59, 48, 0.1);
}

.market-popover-add {
  color: #007aff;
}

.market-popover-divider {
  height: 1px;
  margin: 4px 16px;
  background: rgba(60, 60, 67, 0.12);
}

/* ==================== 搜索栏 ==================== */
.app-store-searchbar {
  --background: rgba(142, 142, 147, 0.12);
  --border-radius: 10px;
  --box-shadow: none;
  --cancel-button-color: #007aff;
  --placeholder-color: rgba(60, 60, 67, 0.6);
  --icon-color: rgba(60, 60, 67, 0.6);
  --clear-button-color: rgba(60, 60, 67, 0.6);
  padding: 0 16px;
  font-size: 17px;
  font-weight: 400;
}

.app-store-searchbar::part(native) {
  height: 36px;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.app-store-searchbar::part(native):focus-within {
  --background: rgba(142, 142, 147, 0.18);
}

.dark .app-store-searchbar {
  --background: rgba(118, 118, 128, 0.24);
  --placeholder-color: rgba(235, 235, 245, 0.6);
  --icon-color: rgba(235, 235, 245, 0.6);
  --clear-button-color: rgba(235, 235, 245, 0.6);
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

/* ==================== Dark mode ==================== */
.dark .market-popover-item:active {
  background-color: rgba(255, 255, 255, 0.08);
}

.dark .market-popover-item.active {
  color: #0a84ff;
}

.dark .market-popover-check {
  color: #0a84ff;
}

.dark .market-popover-divider {
  background: rgba(235, 235, 245, 0.15);
}

.dark .market-popover-add {
  color: #0a84ff;
}
</style>
