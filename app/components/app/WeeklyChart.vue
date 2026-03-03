<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'

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
        class="chart-header mb-4 cursor-pointer"
        @click="viewAllChart"
      >
        <h2 class="text-xl font-bold">
          本周热门
        </h2>
      </div>
      <div class="chart-list">
        <div
          v-for="app in weeklyApps"
          :key="app.id"
          class="chart-item"
          @click="openAppDetail(app)"
        >
          <!-- 应用图标 -->
          <div
            class="app-icon"
            :style="{ background: `linear-gradient(135deg, ${app.color}dd 0%, ${app.color}88 100%)` }"
          >
            <span class="icon-emoji">{{ app.icon || app.emoji }}</span>
          </div>

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
            <AppInstallButton :app-id="app.code || app.id" source="static" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.text-primary {
  color: var(--ion-color-primary);
}

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
  gap: 8px;
}

.chart-list {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.chart-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  cursor: pointer;
  transition: opacity 0.2s ease;
}

.chart-item:last-child {
  padding-bottom: 0;
}

.chart-item:first-child {
  padding-top: 0;
}

.chart-item:active {
  opacity: 0.6;
}

.app-icon {
  width: 64px;
  height: 64px;
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}

.icon-emoji {
  font-size: 32px;
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

  .chart-header {
    border-bottom-color: var(--ion-background-color-step-200);
  }

  .app-icon {
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
  }
}
</style>
