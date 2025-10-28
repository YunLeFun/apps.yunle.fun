<script setup lang="ts">
import type { ThemeMode } from '~/stores/settings'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonNote,
  IonPage,
  IonRadio,
  IonRadioGroup,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { moon, phonePortraitOutline, sunny } from 'ionicons/icons'

const settingsStore = useSettingsStore()

const selectedTheme = ref<ThemeMode>(settingsStore.themeMode)

// 主题选项配置
const themeOptions = [
  {
    value: 'system' as ThemeMode,
    label: '跟随系统',
    description: '根据系统设置自动切换',
    icon: phonePortraitOutline,
  },
  {
    value: 'light' as ThemeMode,
    label: '浅色',
    description: '始终使用浅色外观',
    icon: sunny,
  },
  {
    value: 'dark' as ThemeMode,
    label: '深色',
    description: '始终使用深色外观',
    icon: moon,
  },
]

// 监听主题变化并应用
watch(selectedTheme, (newTheme) => {
  settingsStore.applyTheme(newTheme)
})

// 初始化主题
onMounted(() => {
  settingsStore.initTheme()
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="" />
        </IonButtons>
        <IonTitle>设置</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="settings-content">
      <!-- 外观设置 -->
      <IonList inset class="settings-list">
        <IonListHeader>
          <IonLabel class="settings-section-title">
            外观
          </IonLabel>
        </IonListHeader>

        <IonRadioGroup v-model="selectedTheme">
          <IonItem
            v-for="option in themeOptions"
            :key="option.value"
            button
            :detail="false"
            class="theme-item"
            lines="full"
          >
            <IonIcon
              slot="start"
              :icon="option.icon"
              class="theme-icon"
            />
            <IonLabel>
              <h3 class="theme-label">
                {{ option.label }}
              </h3>
              <IonNote class="theme-description">
                {{ option.description }}
              </IonNote>
            </IonLabel>
            <IonRadio
              slot="end"
              :value="option.value"
              mode="ios"
            />
          </IonItem>
        </IonRadioGroup>
      </IonList>

      <!-- 当前主题预览 -->
      <div class="theme-preview">
        <IonNote class="preview-note">
          当前外观：{{ selectedTheme === 'system' ? '跟随系统' : selectedTheme === 'light' ? '浅色' : '深色' }}
        </IonNote>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
/* ==================== Content 区域 ==================== */
.settings-content {
  --background: #f2f2f7;
}

.dark .settings-content {
  --background: #000000;
}

/* ==================== List 样式 ==================== */
.settings-list {
  margin-top: 20px;
  margin-bottom: 20px;
}

.settings-section-title {
  font-size: 13px;
  font-weight: 400;
  text-transform: uppercase;
  letter-spacing: -0.08px;
  color: rgba(60, 60, 67, 0.6);
}

.dark .settings-section-title {
  color: rgba(235, 235, 245, 0.6);
}

/* ==================== 主题选项样式 ==================== */
.theme-item {
  --padding-start: 16px;
  --padding-end: 16px;
  --inner-padding-end: 8px;
  --min-height: 64px;
}

.theme-icon {
  font-size: 24px;
  margin-right: 12px;
  color: #007aff;
}

.dark .theme-icon {
  color: #0a84ff;
}

.theme-label {
  font-size: 17px;
  font-weight: 400;
  letter-spacing: -0.41px;
  color: #000000;
  margin: 0 0 2px 0;
}

.dark .theme-label {
  color: #ffffff;
}

.theme-description {
  font-size: 13px;
  font-weight: 400;
  letter-spacing: -0.08px;
  color: rgba(60, 60, 67, 0.6);
  margin: 0;
}

.dark .theme-description {
  color: rgba(235, 235, 245, 0.6);
}

/* ==================== Radio 样式 ==================== */
ion-radio {
  --color-checked: #007aff;
}

.dark ion-radio {
  --color-checked: #0a84ff;
}

/* ==================== 主题预览 ==================== */
.theme-preview {
  padding: 0 32px;
  margin-top: 12px;
}

.preview-note {
  font-size: 13px;
  font-weight: 400;
  letter-spacing: -0.08px;
  color: rgba(60, 60, 67, 0.6);
  display: block;
}

.dark .preview-note {
  color: rgba(235, 235, 245, 0.6);
}

/* ==================== 动画效果 ==================== */
.theme-item {
  transition: background-color 0.2s ease;
}

.theme-item:active {
  --background-activated: rgba(0, 0, 0, 0.05);
}

.dark .theme-item:active {
  --background-activated: rgba(255, 255, 255, 0.05);
}
</style>
