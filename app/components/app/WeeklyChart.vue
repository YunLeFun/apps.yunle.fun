<script lang="ts" setup>
import type { YlfAppInfo } from '@yunlefun/types'

const props = withDefaults(defineProps<Props>(), { managed: false })

const router = useRouter()

interface Props {
  /** 是否由父组件提供数据（避免重复加载） */
  managed?: boolean
}
const { weeklyApps, loadWeeklyChart } = useDiscovery()

// 非 managed 模式下自行加载
if (!props.managed) {
  onMounted(() => loadWeeklyChart())
}

function openAppDetail(app: YlfAppInfo) {
  router.push(`/app/${app.id}`)
}

function viewAllChart() {
  router.push('/charts/weekly')
}
</script>

<template>
  <div class="app-weekly-chart">
    <div class="chart-card">
      <div
        class="chart-header mb-3 cursor-pointer"
        @click="viewAllChart"
      >
        <h2 class="text-xl font-bold">
          本周热门
        </h2>
        <div class="chart-header-more">
          查看全部
          <svg viewBox="0 0 16 16" fill="none" class="chart-header-arrow">
            <path d="M6 4l4 4-4 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </div>
      </div>
      <div class="chart-list">
        <div
          v-for="app in weeklyApps"
          :key="app.id"
          class="chart-item"
          @click="openAppDetail(app)"
        >
          <!-- 应用图标 -->
          <AppIconBox
            class="chart-icon"
            :icon="app.logo"
            :icon-assets="app.iconAssets"
            :emoji="app.emoji"
            :color="app.themeColor"
            size="md"
          />

          <!-- 应用信息 -->
          <div class="app-info">
            <h3 class="app-name">
              {{ app.name }}
            </h3>
            <p class="app-description">
              {{ app.description }}
            </p>
            <div class="app-meta">
              <span class="app-category">{{ app.category }}</span>
            </div>
          </div>

          <!-- 安装按钮 -->
          <div class="app-action">
            <AppInstallButton :app="app" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.chart-card {
  background: var(--ion-background-color-step-100);
  border-radius: 16px;
  padding: 16px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
  transition: box-shadow 0.2s ease;
}

.chart-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.chart-header-more {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  font-size: 13px;
  font-weight: 500;
  color: var(--ion-color-primary);
  cursor: pointer;
}

.chart-header-arrow {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
}

.chart-list {
  display: flex;
  flex-direction: column;
}

.chart-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 0;
  cursor: pointer;
  transition: opacity 0.15s ease;
  position: relative;
}

/* iOS 风格分隔线：从图标右边缘起始，不延伸到左侧 */
.chart-item:not(:last-child)::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 76px; /* 图标宽64 + gap12 */
  right: 0;
  height: 0.5px;
  background: var(--ion-border-color, rgba(0, 0, 0, 0.1));
}

.chart-item:active {
  opacity: 0.7;
}

.chart-icon {
  flex-shrink: 0;
}

.app-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.app-name {
  font-size: 16px;
  font-weight: 600;
  margin: 0;
  color: var(--ion-text-color);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-description {
  font-size: 13px;
  color: var(--ion-color-medium);
  margin: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 2px;
}

.app-category {
  font-size: 12px;
  color: var(--ion-color-medium);
}

.app-action {
  flex-shrink: 0;
}

/* 深色模式适配 */
@media (prefers-color-scheme: dark) {
  .chart-card {
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.3);
  }

  .chart-item:not(:last-child)::after {
    background: rgba(255, 255, 255, 0.1);
  }
}
</style>
