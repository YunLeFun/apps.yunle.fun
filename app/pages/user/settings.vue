<script setup lang="ts">
import type { ThemeMode } from '~/stores/settings'
import {
  checkmarkSharp,
  contrastOutline,
  moonOutline,
  sunnyOutline,
} from 'ionicons/icons'
import {
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'

const settingsStore = useSettingsStore()

const selectedTheme = ref<ThemeMode>(settingsStore.themeMode)

const themeOptions = [
  { value: 'system' as ThemeMode, label: '自动', icon: contrastOutline },
  { value: 'light' as ThemeMode, label: '浅色', icon: sunnyOutline },
  { value: 'dark' as ThemeMode, label: '深色', icon: moonOutline },
]

function selectTheme(value: ThemeMode) {
  selectedTheme.value = value
  settingsStore.applyTheme(value)
}

onMounted(() => {
  settingsStore.initTheme()
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
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
          @click="selectTheme(option.value)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="option.icon" />
            </span>
          </template>
          <template v-if="selectedTheme === option.value" #after>
            <IonIcon :icon="checkmarkSharp" class="text-xl ios-primary-text" />
          </template>
        </k-list-item>
      </k-list>
    </IonContent>
  </IonPage>
</template>

