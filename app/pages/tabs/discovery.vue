<script setup lang="ts">
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { useStorage } from '@vueuse/core'
import { arrowBackOutline, personCircleOutline, sparklesOutline } from 'ionicons/icons'

definePageMeta({
  // discovery 页面不需要别名
})

const { loading, loadAll } = useDiscovery()

/** AI 找应用助手（寻乐页的智能发现入口） */
const showAgent = ref(false)
// 与 tabs.vue 联动：AI 助手打开时隐藏底部 TabBar，给对话界面完整高度
const agentScreenOpen = useState('agent:screen-open', () => false)

// ==================== AI 入口首次引导 ====================
// 纯 ✨ 图标可发现性偏低，首次进寻乐页弹一次 coach-mark 介绍，看过即不再出现。
// 用红点会被误读为"待办/未读"，这里用一次性气泡，语义是"介绍"而非"通知"。
const aiFinderHinted = useStorage('ylf:ai-finder-hinted', false)
const showAiHint = ref(false)
let hintShowTimer: ReturnType<typeof setTimeout> | null = null
let hintAutoDismissTimer: ReturnType<typeof setTimeout> | null = null

function dismissAiHint() {
  if (hintShowTimer) {
    clearTimeout(hintShowTimer)
    hintShowTimer = null
  }
  if (hintAutoDismissTimer) {
    clearTimeout(hintAutoDismissTimer)
    hintAutoDismissTimer = null
  }
  showAiHint.value = false
  aiFinderHinted.value = true
}

watch(showAgent, (value) => {
  agentScreenOpen.value = value
})

function openAgent() {
  dismissAiHint()
  showAgent.value = true
}

function closeAgent() {
  showAgent.value = false
}

onMounted(() => {
  loadAll()

  if (!aiFinderHinted.value) {
    // 等页面稳定后再弹，避免与首屏加载/动画抢镜；点 ✨ / 点气泡即打开，否则数秒后自动消失
    hintShowTimer = setTimeout(() => {
      hintShowTimer = null
      if (showAgent.value || aiFinderHinted.value)
        return
      showAiHint.value = true
      hintAutoDismissTimer = setTimeout(dismissAiHint, 6000)
    }, 600)
  }
})

onUnmounted(() => {
  agentScreenOpen.value = false
  if (hintShowTimer)
    clearTimeout(hintShowTimer)
  if (hintAutoDismissTimer)
    clearTimeout(hintAutoDismissTimer)
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <button
            v-if="showAgent"
            class="discovery-header-icon-button"
            type="button"
            aria-label="返回寻乐"
            @click="closeAgent"
          >
            <IonIcon aria-hidden="true" :icon="arrowBackOutline" />
          </button>
          <button
            v-else
            class="discovery-header-icon-button"
            type="button"
            aria-label="AI 找应用"
            @click="openAgent"
          >
            <IonIcon aria-hidden="true" :icon="sparklesOutline" />
          </button>
        </IonButtons>
        <IonTitle>{{ showAgent ? 'AI 找应用' : '寻乐' }}</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="!showAgent" router-link="/tabs/me">
            <IonIcon slot="icon-only" :icon="personCircleOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <!-- AI 入口首次引导气泡（看过即不再出现） -->
    <button
      v-if="showAiHint && !showAgent"
      class="ai-finder-hint"
      type="button"
      @click="openAgent"
    >
      <span class="ai-finder-hint-arrow" />
      <IonIcon aria-hidden="true" class="ai-finder-hint-icon" :icon="sparklesOutline" />
      <span>让 AI 帮你找应用</span>
    </button>

    <IonContent :class="{ 'discovery-agent-host': showAgent }">
      <!-- AI 找应用助手 -->
      <AgentScreen v-if="showAgent" />

      <!-- 浏览式发现 -->
      <div v-else class="px-4 pb-4 pt-2">
        <!-- 加载骨架屏 -->
        <div v-if="loading" class="space-y-4">
          <div class="h-80 animate-pulse rounded-2xl bg-gray-200 dark:bg-gray-800" />
          <div class="h-64 animate-pulse rounded-2xl bg-gray-200 dark:bg-gray-800" />
        </div>

        <template v-else>
          <!-- 今日推荐 -->
          <AppFeatured managed />

          <!-- 本周热门排行榜 -->
          <AppWeeklyChart managed />
        </template>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
/* AI 助手打开时由 AgentScreen 自己管理纵向滚动，IonContent 不再滚动 */
.discovery-agent-host {
  --overflow: hidden;
}

.discovery-header-icon-button {
  display: inline-grid;
  place-items: center;
  width: 44px;
  height: 44px;
  border: 0;
  padding: 0;
  color: var(--ion-color-primary);
  background: transparent;
  font: inherit;
  font-size: 22px;
}

.discovery-header-icon-button:active {
  opacity: 0.62;
}

/* ==================== AI 入口首次引导气泡 ==================== */
.ai-finder-hint {
  position: fixed;
  top: calc(var(--ion-safe-area-top, 0px) + 50px);
  left: 8px;
  z-index: 1000;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  max-width: calc(100vw - 16px);
  padding: 9px 13px;
  border: 0;
  border-radius: 12px;
  color: #fff;
  background: var(--ion-color-primary);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.22);
  font: inherit;
  font-size: 13px;
  font-weight: 600;
  white-space: nowrap;
  animation: ai-finder-hint-in 0.24s cubic-bezier(0.22, 1, 0.36, 1);
}

.ai-finder-hint:active {
  opacity: 0.82;
}

.ai-finder-hint-arrow {
  position: absolute;
  top: -4px;
  left: 18px;
  width: 10px;
  height: 10px;
  background: inherit;
  border-radius: 2px;
  transform: rotate(45deg);
}

.ai-finder-hint-icon {
  font-size: 15px;
}

@keyframes ai-finder-hint-in {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (prefers-reduced-motion: reduce) {
  .ai-finder-hint {
    animation: none;
  }
}
</style>
