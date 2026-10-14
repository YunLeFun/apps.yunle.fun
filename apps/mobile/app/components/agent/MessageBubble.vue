<script setup lang="ts">
import type { AgentChatMessage } from '~/types/agent'
import { IonIcon, IonSpinner } from '@ionic/vue'
import { checkmarkCircleOutline, copyOutline } from 'ionicons/icons'
import AgentMarkdownPreview from './MarkdownPreview.vue'

const props = defineProps<{
  message: AgentChatMessage
}>()

const { showSuccess } = useToast()
const copied = shallowRef(false)
let copiedTimer: ReturnType<typeof setTimeout> | null = null

const isAssistant = computed(() => props.message.role === 'assistant')
const hasCards = computed(() => (props.message.appCards?.length ?? 0) > 0)
const canCopy = computed(() => isAssistant.value && props.message.content.trim().length > 0)
const isMessageFinal = computed(() => props.message.status !== 'streaming')
const statusLabel = computed(() => {
  if (props.message.toolStatus)
    return props.message.toolStatus
  if (props.message.status === 'streaming' && !props.message.content)
    return '正在响应'
  if (props.message.status === 'error')
    return '请求失败'
  return ''
})

async function copyMessage() {
  const content = props.message.content.trim()
  if (!content)
    return

  await navigator.clipboard?.writeText(content)
  copied.value = true
  showSuccess('已复制')
  if (copiedTimer)
    clearTimeout(copiedTimer)
  copiedTimer = setTimeout(() => {
    copied.value = false
  }, 1500)
}

onUnmounted(() => {
  if (copiedTimer)
    clearTimeout(copiedTimer)
})
</script>

<template>
  <div class="agent-message" :class="isAssistant ? 'agent-message-assistant' : 'agent-message-user'">
    <div v-if="message.content || statusLabel" class="agent-message-bubble">
      <AgentMarkdownPreview
        v-if="message.content && isAssistant"
        :content="message.content"
        :final="isMessageFinal"
      />
      <p v-else-if="message.content" class="agent-message-content">
        {{ message.content }}
      </p>
      <div v-if="statusLabel" class="agent-message-status">
        <IonSpinner v-if="message.status === 'streaming'" name="dots" />
        <span>{{ statusLabel }}</span>
      </div>
    </div>

    <div v-if="hasCards" class="agent-message-cards">
      <AgentAppCard
        v-for="card in message.appCards"
        :key="card.slug"
        :card="card"
      />
    </div>

    <div v-if="canCopy" class="agent-message-actions">
      <button class="agent-message-action" type="button" @click="copyMessage">
        <IonIcon :icon="copied ? checkmarkCircleOutline : copyOutline" />
        <span>{{ copied ? '已复制' : '复制' }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.agent-message {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.agent-message-user {
  align-items: flex-end;
}

.agent-message-assistant {
  align-items: flex-start;
}

.agent-message-bubble {
  max-width: min(82%, 560px);
  border-radius: 18px;
  padding: 10px 13px;
  color: var(--agent-text, var(--ion-text-color));
  background: var(--agent-panel, rgba(255, 255, 255, 0.74));
  box-shadow: var(--agent-shadow, 0 10px 24px rgba(0, 0, 0, 0.04));
}

.agent-message-user .agent-message-bubble {
  color: #fff;
  background: var(--ion-color-primary);
}

.agent-message-content {
  margin: 0;
  overflow-wrap: anywhere;
  white-space: pre-wrap;
  font-size: 14px;
  line-height: 1.55;
}

.agent-message-status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 20px;
  margin-top: 2px;
  color: var(--agent-muted, var(--ion-color-medium));
  font-size: 12px;
  font-weight: 700;
}

.agent-message-status ion-spinner {
  width: 18px;
  height: 18px;
}

.agent-message-cards {
  display: grid;
  width: min(100%, 560px);
  gap: 10px;
}

.agent-message-actions {
  display: flex;
  width: min(100%, 560px);
  justify-content: flex-start;
}

.agent-message-action {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-height: 28px;
  border: 0;
  border-radius: 999px;
  padding: 0 9px;
  color: var(--agent-muted, var(--ion-color-medium));
  background: transparent;
  font-size: 12px;
  font-weight: 700;
}

.agent-message-action:active {
  opacity: 0.72;
}
</style>
