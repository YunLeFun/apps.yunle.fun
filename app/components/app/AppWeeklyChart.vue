<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonButton } from '@ionic/vue'

const router = useRouter()

// 本周热门应用排行榜
const weeklyChartApps = ref<YlfAppInfo[]>([
  {
    id: '2001',
    code: 'music-master',
    name: 'Music Master',
    description: '专业音乐制作工具，支持多轨录音和混音',
    icon: '🎵',
    emoji: '🎵',
    color: '#FF2D55',
    url: '/app/music-master',
    category: '音乐',
    rating: 4.8,
    downloads: '100万+',
    size: '156.2 MB',
    age: '4+',
  },
  {
    id: '2002',
    code: 'photo-editor-pro',
    name: 'Photo Editor Pro',
    description: '强大的图片编辑工具，AI 智能修图',
    icon: '📷',
    emoji: '📷',
    color: '#5856D6',
    url: '/app/photo-editor-pro',
    category: '摄影与录像',
    rating: 4.9,
    downloads: '200万+',
    size: '98.5 MB',
    age: '4+',
  },
  {
    id: '2003',
    code: 'task-manager',
    name: 'Task Manager',
    description: '高效任务管理，让工作井井有条',
    icon: '✅',
    emoji: '✅',
    color: '#34C759',
    url: '/app/task-manager',
    category: '效率',
    rating: 4.7,
    downloads: '80万+',
    size: '45.3 MB',
    age: '4+',
  },
  {
    id: '2004',
    code: 'language-learn',
    name: 'Language Learn',
    description: '轻松学习多国语言，AI 对话练习',
    icon: '🌍',
    emoji: '🌍',
    color: '#FF9500',
    url: '/app/language-learn',
    category: '教育',
    rating: 4.8,
    downloads: '150万+',
    size: '112.7 MB',
    age: '4+',
  },
  {
    id: '2005',
    code: 'meditation-plus',
    name: 'Meditation Plus',
    description: '冥想放松，改善睡眠质量',
    icon: '🧘',
    emoji: '🧘',
    color: '#30B0C7',
    url: '/app/meditation-plus',
    category: '健康健身',
    rating: 4.9,
    downloads: '120万+',
    size: '67.8 MB',
    age: '4+',
  },
])

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
          v-for="(app) in weeklyChartApps"
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

          <!-- 获取按钮 -->
          <div class="app-action">
            <IonButton
              fill="clear"
              size="small"
              color="primary"
              @click.stop="openAppDetail(app)"
            >
              获取
            </IonButton>
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
    border-bottom-color: var(--ion-color-step-200);
  }

  .app-icon {
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
  }
}
</style>
