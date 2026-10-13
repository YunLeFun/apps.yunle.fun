<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import { IonAvatar, IonChip, IonLabel } from '@ionic/vue'

const props = defineProps<{
  appInfo: YlfAppInfo
}>()

const { resolvedSrc: appIconSrc } = useAppIconSource(
  () => props.appInfo.iconAssets,
  () => props.appInfo.logo,
)
</script>

<template>
  <div class="mb-6 flex flex-col items-center">
    <div class="mb-4 text-center">
      <p class="mb-3 text-sm text-gray-500 dark:text-gray-400">
        正在为以下应用登录
      </p>
      <a
        :href="appInfo.websiteUrl"
        target="_blank"
        class="inline-block"
      >
        <IonChip color="primary" class="text-base">
          <IonAvatar v-if="appIconSrc">
            <img
              :src="appIconSrc"
              alt="icon"
            >
          </IonAvatar>
          <IonLabel class="font-bold">
            {{ appInfo.name }}
          </IonLabel>
        </IonChip>
      </a>
      <p class="mt-1 text-xs text-gray-400">
        {{ appInfo.slug }}
      </p>
    </div>
  </div>
</template>
