<script lang="ts" setup>
import { IonButton } from '@ionic/vue'

const props = withDefaults(defineProps<Props>(), { managed: false })

const router = useRouter()

interface Props {
  /** 是否由父组件提供数据（避免重复加载） */
  managed?: boolean
}
const { featuredApp, loadFeatured } = useDiscovery()

// 非 managed 模式下自行加载
if (!props.managed) {
  onMounted(() => loadFeatured())
}

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
