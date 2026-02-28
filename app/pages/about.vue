<script setup lang="ts">
import {
  cloudOutline,
  informationCircleOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'
import { YLF_LINKS } from '~/constants'

const appVersion = '0.0.1'

function openLink(url: string) {
  window.open(url, '_blank')
}
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

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            关于
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- App Logo + 名称 -->
      <k-block class="mt-8">
        <div class="flex flex-col items-center py-4 text-center">
          <div class="mb-3 h-20 w-20 flex items-center justify-center overflow-hidden rounded-[22px] bg---ion-color-primary,#007aff">
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

      <!-- 链接 -->
      <k-list strong inset>
        <k-list-item
          link
          title="云乐坊工作室"
          :after="YLF_LINKS.studio.text"
          @click="openLink(YLF_LINKS.studio.url)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="cloudOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 信息 -->
      <k-block-title>信息</k-block-title>
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
      </k-list>

      <!-- 底部版权 -->
      <k-block class="mt-8">
        <p class="text-center text-xs ios-secondary-text">
          &copy; {{ new Date().getFullYear() }} 云乐坊 YunLeFun
        </p>
      </k-block>
    </IonContent>
  </IonPage>
</template>
