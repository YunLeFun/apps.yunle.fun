<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonButton } from '@ionic/vue'

const router = useRouter()

// 今日推荐应用
const featuredApp = ref<YlfAppInfo>({
  id: '1003',
  code: 'fitness-pro',
  name: 'Fitness Pro',
  description: '专业健身教练，定制您的训练计划。AI 智能分析，个性化训练方案',
  emoji: '💪',
  color: '#FF3B30',
  url: '/apps/fitness-pro',
  category: '健康健身',
  rating: 4.9,
  downloads: '50万+',
  size: '125.8 MB',
  age: '12+',
  subtitle: '编辑精选',
  tagline: '让健身更科学',
})

function openAppDetail() {
  router.push(`/app/${featuredApp.value.id}`)
}

const todayDateStr = computed(() => {
  const date = new Date()
  const month = date.getMonth() + 1
  const day = date.getDate()
  return `${month}月${day}日`
})
</script>

<template>
  <div class="app-featured pb-4">
    <div class="mb-3 flex items-center justify-between">
      <h2 class="section text-3xl font-bold">
        今日推荐
        <small class="opacity-55">
          {{ todayDateStr }}
        </small>
      </h2>
    </div>

    <div
      class="featured-card cursor-pointer overflow-hidden rounded-2xl"
      @click="openAppDetail"
    >
      <div
        class="featured-gradient relative h-80 p-5"
        :style="{ background: `linear-gradient(135deg, ${featuredApp.color}dd 0%, ${featuredApp.color}88 100%)` }"
      >
        <div class="h-full flex flex-col justify-between">
          <div>
            <div class="mb-2 text-xs text-white/90 font-semibold tracking-wider uppercase">
              {{ featuredApp.subtitle }}
            </div>
            <h3 class="mb-2 text-3xl text-white font-bold">
              {{ featuredApp.name }}
            </h3>
            <p class="text-base text-white/90">
              {{ featuredApp.tagline }}
            </p>
          </div>

          <div class="flex items-end justify-between">
            <div
              class="h-20 w-20 flex items-center justify-center rounded-2xl text-4xl shadow-lg"
              style="background: rgba(255, 255, 255, 0.95)"
            >
              {{ featuredApp.emoji }}
            </div>
            <IonButton color="light" size="default">
              查看
            </IonButton>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.featured-card {
  border-radius: 16px;
  overflow: hidden;
  transition: transform 0.2s ease;
}

.featured-card:active {
  transform: scale(0.98);
}

.featured-gradient {
  position: relative;
}
</style>
