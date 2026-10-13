<script setup lang="ts">
import {
  documentTextOutline,
  informationCircleOutline,
  listOutline,
  shieldCheckmarkOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kList,
  kListItem,
} from 'konsta/vue'
import { config } from '~/config'
import { APP_CHANGELOG } from '~/constants'

const appVersion = '0.0.1'

const { handleLogoClick } = useDeveloperMode()

/**
 * 版本更新日志是否展开
 */
const showChangelog = ref(false)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>关于</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <!-- App Logo + 名称（连续点击 5 次进入开发者模式） -->
      <k-block class="mt-8">
        <div
          class="flex flex-col items-center py-4 text-center select-none"
          role="button"
          tabindex="0"
          @click="handleLogoClick"
        >
          <div class="mb-3 h-20 w-20 flex items-center justify-center overflow-hidden rounded-full" style="background-color: var(--ion-color-primary, #007aff)">
            <span class="text-3xl font-bold text-white">☁️</span>
          </div>
          <h2 class="text-lg font-semibold">
            云乐坊
          </h2>
          <p class="mt-1 text-sm ios-secondary-text">
            版本 {{ appVersion }}
          </p>
        </div>
      </k-block>

      <!-- 应用信息 -->
      <k-list strong inset>
        <k-list-item
          title="版本"
          :after="appVersion"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-gray">
              <IonIcon :icon="informationCircleOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="版本更新"
          after="查看日志"
          @click="showChangelog = !showChangelog"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="listOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 更新日志展开 -->
      <Transition name="changelog">
        <k-block v-if="showChangelog" strong inset class="mt-0!">
          <div v-for="entry in APP_CHANGELOG" :key="entry.version" class="mb-4 last:mb-0">
            <div class="mb-1.5 flex items-center gap-2">
              <span class="text-sm font-semibold">v{{ entry.version }}</span>
              <span class="text-xs ios-secondary-text">{{ entry.date }}</span>
            </div>
            <ul class="ml-0 list-none space-y-1">
              <li v-for="(change, idx) in entry.changes" :key="idx" class="flex items-start gap-1.5 text-sm ios-secondary-text">
                <span class="mt-0.5 shrink-0 text-xs text-blue-500">•</span>
                <span>{{ change }}</span>
              </li>
            </ul>
          </div>
        </k-block>
      </Transition>

      <!-- 法律信息 -->
      <k-list strong inset>
        <k-list-item
          link
          title="服务条款"
          @click="openInAppBrowser(config.legal.terms)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-gray">
              <IonIcon :icon="documentTextOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="隐私政策"
          @click="openInAppBrowser(config.legal.privacy)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-teal">
              <IonIcon :icon="shieldCheckmarkOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 社交媒体 -->
      <AppSocialList />

      <!-- 底部版权 -->
      <k-block class="mt-8">
        <p class="text-center text-xs ios-secondary-text">
          &copy; {{ new Date().getFullYear() }} 云乐坊 YunLeFun
        </p>
      </k-block>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.changelog-enter-active,
.changelog-leave-active {
  transition: all 0.3s ease;
  overflow: hidden;
}
.changelog-enter-from,
.changelog-leave-to {
  opacity: 0;
  max-height: 0;
}
.changelog-enter-to,
.changelog-leave-from {
  opacity: 1;
  max-height: 500px;
}
</style>
