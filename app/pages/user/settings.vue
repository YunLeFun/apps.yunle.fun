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
    <IonHeader class="ion-no-border" :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>设置</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="settings-content">
      <IonListHeader>
        外观
      </IonListHeader>

      <!-- 外观设置 -->
      <IonList inset>
        <IonRadioGroup v-model="selectedTheme">
          <IonItem
            v-for="option in themeOptions"
            :key="option.value"
            button
            :detail="false"
            class="theme-item"
            lines="full"
            @click="selectedTheme = option.value"
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
              <IonNote class="ion-color ion-color-medium text-xs">
                {{ option.description }}
              </IonNote>
            </IonLabel>
            <IonRadio
              slot="end"
              :value="option.value"
            />
          </IonItem>
        </IonRadioGroup>
      </IonList>
    </IonContent>
  </IonPage>
</template>

<style>
/* (Optional) This is added to prevent the flashing that happens when toggling between palettes */
ion-item {
  --transition: none;
}
</style>
