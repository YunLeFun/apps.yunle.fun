<script setup lang="ts">
import type { ThemeMode } from '~/stores/settings'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { moon, phonePortraitOutline, sunny } from 'ionicons/icons'
import {
  kBlockTitle,
  kList,
  kListItem,
  kRadio,
} from 'konsta/vue'

const settingsStore = useSettingsStore()

const selectedTheme = ref<ThemeMode>(settingsStore.themeMode)

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

watch(selectedTheme, (newTheme) => {
  settingsStore.applyTheme(newTheme)
})

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

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            设置
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <k-block-title>外观</k-block-title>

      <k-list strong inset>
        <k-list-item
          v-for="option in themeOptions"
          :key="option.value"
          :title="option.label"
          :subtitle="option.description"
          @click="selectedTheme = option.value"
        >
          <template #media>
            <span
              class="ios-icon-box"
              :class="selectedTheme === option.value ? 'ios-icon-blue' : 'ios-icon-gray'"
            >
              <IonIcon :icon="option.icon" />
            </span>
          </template>
          <template #after>
            <k-radio
              :checked="selectedTheme === option.value"
              @change="selectedTheme = option.value"
            />
          </template>
        </k-list-item>
      </k-list>
    </IonContent>
  </IonPage>
</template>

