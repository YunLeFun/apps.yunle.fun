<script setup lang="ts">
import { IonButton, IonIcon, IonSpinner, IonTextarea } from '@ionic/vue'
import {
  chatbubbleEllipsesOutline,
  lockClosedOutline,
  refreshOutline,
  sendOutline,
  shieldCheckmarkOutline,
  sparklesOutline,
  stopCircleOutline,
  trashOutline,
} from 'ionicons/icons'
import { AGENT_EXAMPLE_PROMPTS } from '~/composables/useAgentChat'

const router = useRouter()
const userStore = useUserStore()
const { catalog, ensureLoaded } = useAppCatalog()
const { account, isMember, refresh } = useCoin()
const chat = useAgentChat()
const threadEnd = useTemplateRef<HTMLElement>('threadEnd')

onMounted(async () => {
  await ensureLoaded()
  if (userStore.isLoggedIn && !account.value)
    await refresh()
})

const locked = computed(() => !userStore.isLoggedIn || !isMember.value)
const statusLabel = computed(() => {
  if (!chat.configurationReady.value)
    return '配置缺失'
  if (!userStore.isLoggedIn)
    return '未登录'
  if (!isMember.value)
    return '会员专属'
  if (chat.running.value)
    return chat.reasoning.value ? '思考中' : '生成中'
  return '已连接'
})
const statusTone = computed(() => ({
  'agent-status-ready': chat.configurationReady.value && userStore.isLoggedIn && isMember.value && !chat.running.value,
  'agent-status-busy': chat.running.value,
  'agent-status-locked': locked.value || !chat.configurationReady.value,
}))
const accessLabel = computed(() => userStore.isLoggedIn ? '开通会员' : '登录')
const inputPlaceholder = computed(() => locked.value ? '会员可发送真实请求' : '搜索或描述你想找的应用')
const sampleCards = computed(() => catalog.value.slice(0, 2).map(app => ({
  id: app.id,
  slug: app.slug,
  name: app.name,
  description: app.description,
  logo: app.logo,
  emoji: app.emoji,
  themeColor: app.themeColor,
  category: app.category,
  rating: app.rating,
  ratingCount: app.ratingCount,
  coinCost: app.coinCost,
  requiresMembership: app.requiresMembership,
  websiteUrl: app.websiteUrl,
  trustedHosts: app.trustedHosts,
  reason: app.tagline && app.tagline !== app.description ? app.tagline : undefined,
})))
const scrollSignature = computed(() => {
  const lastMessage = chat.messages.value.at(-1)
  return [
    chat.messages.value.length,
    lastMessage?.content.length ?? 0,
    lastMessage?.appCards?.length ?? 0,
    lastMessage?.toolStatus ?? '',
    chat.running.value ? 'running' : 'idle',
  ].join(':')
})

watch(scrollSignature, async () => {
  await nextTick()
  threadEnd.value?.scrollIntoView({ block: 'end', behavior: 'smooth' })
}, { flush: 'post' })

async function sendCurrent() {
  await chat.sendMessage()
}

async function sendExample(prompt: string) {
  chat.input.value = prompt
  await chat.sendMessage(prompt)
}

function handleEnter(event: KeyboardEvent) {
  if (event.isComposing || event.shiftKey)
    return
  event.preventDefault()
  sendCurrent()
}

function goAccess() {
  router.push(userStore.isLoggedIn ? '/membership' : '/login')
}
</script>

<template>
  <div class="agent-screen">
    <div class="agent-status-strip">
      <div class="agent-status-main">
        <span class="agent-status-dot" :class="statusTone">
          <IonSpinner v-if="chat.running.value" name="dots" />
          <IonIcon v-else :icon="chat.configurationReady.value ? shieldCheckmarkOutline : lockClosedOutline" />
        </span>
        <span class="agent-status-label">{{ statusLabel }}</span>
      </div>

      <button
        v-if="locked"
        class="agent-status-action"
        type="button"
        @click="goAccess"
      >
        {{ accessLabel }}
      </button>
      <button
        v-else-if="chat.hasMessages.value"
        class="agent-status-action"
        type="button"
        @click="chat.reset"
      >
        <IonIcon :icon="trashOutline" />
        <span>新对话</span>
      </button>
    </div>

    <div class="agent-thread" :class="{ 'agent-thread-empty': !chat.hasMessages.value }">
      <template v-if="chat.hasMessages.value">
        <AgentMessageBubble
          v-for="message in chat.messages.value"
          :key="message.id"
          :message="message"
        />
      </template>

      <div v-else class="agent-empty">
        <div class="agent-empty-mark">
          <IonIcon :icon="locked ? lockClosedOutline : sparklesOutline" />
        </div>
        <div class="agent-empty-copy">
          <p class="agent-empty-kicker">
            YUNLEFUN AGENT
          </p>
          <h2 class="agent-empty-title">
            云乐坊 AI
          </h2>
        </div>
        <div class="agent-examples">
          <button
            v-for="prompt in AGENT_EXAMPLE_PROMPTS"
            :key="prompt"
            class="agent-example-chip"
            type="button"
            @click="sendExample(prompt)"
          >
            <IonIcon :icon="chatbubbleEllipsesOutline" />
            <span>{{ prompt }}</span>
          </button>
        </div>
        <div v-if="sampleCards.length > 0" class="agent-sample-cards">
          <AgentAppCard
            v-for="card in sampleCards"
            :key="card.slug"
            :card="card"
            compact
          />
        </div>
      </div>

      <div ref="threadEnd" class="agent-thread-end" />
    </div>

    <div v-if="chat.error.value" class="agent-error-bar">
      <span>{{ chat.error.value }}</span>
      <button type="button" @click="chat.retryLast">
        <IonIcon :icon="refreshOutline" />
        <span>重试</span>
      </button>
    </div>

    <div class="agent-input-bar">
      <IonTextarea
        v-model="chat.input.value"
        class="agent-input"
        :auto-grow="true"
        :rows="1"
        :maxlength="500"
        :placeholder="inputPlaceholder"
        @keydown.enter.exact="handleEnter"
      />
      <IonButton
        class="agent-send-button"
        shape="round"
        :disabled="!chat.canSend.value && !chat.running.value"
        @click="chat.running.value ? chat.stop() : sendCurrent()"
      >
        <IonIcon slot="icon-only" :icon="chat.running.value ? stopCircleOutline : sendOutline" />
      </IonButton>
    </div>
  </div>
</template>

<style scoped>
.agent-screen {
  --agent-text: var(--ion-text-color);
  --agent-muted: color-mix(in srgb, var(--ion-text-color) 56%, transparent);
  --agent-subtle: color-mix(in srgb, var(--ion-text-color) 42%, transparent);
  --agent-panel: rgba(255, 255, 255, 0.74);
  --agent-panel-strong: rgba(255, 255, 255, 0.86);
  --agent-panel-soft: var(--ylf-fill-secondary);
  --agent-border: rgba(0, 122, 255, 0.12);
  --agent-shadow: 0 12px 30px rgba(0, 0, 0, 0.05);
  --agent-card-bg: var(--agent-panel-strong);
  --agent-chip-bg: rgba(255, 255, 255, 0.78);
  --agent-meta-bg: var(--ylf-fill-tertiary);
  --agent-input-bg: var(--ylf-fill-secondary);
  --agent-input-bar-bg: color-mix(in srgb, var(--ion-background-color) 92%, transparent);
  --agent-accent-text: color-mix(in srgb, var(--ion-color-primary) 72%, var(--agent-text));
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  color: var(--agent-text);
  background:
    linear-gradient(180deg, rgba(0, 122, 255, 0.08) 0%, transparent 184px),
    linear-gradient(135deg, rgba(255, 149, 0, 0.08) 0%, transparent 42%), var(--ion-background-color);
}

:global(html.dark .agent-screen) {
  --agent-text: rgba(255, 255, 255, 0.94);
  --agent-muted: rgba(226, 232, 240, 0.76);
  --agent-subtle: rgba(226, 232, 240, 0.58);
  --agent-panel: rgba(25, 28, 34, 0.88);
  --agent-panel-strong: rgba(30, 34, 42, 0.94);
  --agent-panel-soft: rgba(42, 47, 58, 0.92);
  --agent-border: rgba(139, 164, 214, 0.24);
  --agent-shadow: 0 18px 42px rgba(0, 0, 0, 0.34);
  --agent-card-bg: rgba(28, 32, 40, 0.96);
  --agent-chip-bg: rgba(34, 39, 48, 0.96);
  --agent-meta-bg: rgba(52, 59, 72, 0.95);
  --agent-input-bg: rgba(46, 51, 62, 0.94);
  --agent-input-bar-bg: rgba(20, 22, 27, 0.92);
  --agent-accent-text: #8fb8ff;
  background:
    linear-gradient(180deg, rgba(0, 122, 255, 0.12) 0%, transparent 196px),
    linear-gradient(135deg, rgba(255, 149, 0, 0.09) 0%, transparent 40%), var(--ion-background-color);
}

.agent-status-strip {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-shrink: 0;
  padding: 14px 16px 6px;
}

.agent-status-main {
  display: inline-flex;
  align-items: center;
  min-width: 0;
  gap: 8px;
}

.agent-status-dot {
  display: inline-grid;
  place-items: center;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  color: var(--agent-muted);
  background: var(--agent-panel-soft);
  font-size: 15px;
}

.agent-status-ready {
  color: #0a7f44;
  background: rgba(52, 199, 89, 0.15);
}

.agent-status-busy {
  color: var(--ion-color-primary);
  background: rgba(0, 122, 255, 0.12);
}

.agent-status-locked {
  color: #d99226;
  background: rgba(255, 149, 0, 0.16);
}

.agent-status-label {
  overflow: hidden;
  color: var(--agent-muted);
  font-size: 13px;
  font-weight: 700;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-status-action {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  min-height: 30px;
  border: 0;
  border-radius: 999px;
  padding: 0 11px;
  color: var(--ion-color-primary);
  background: var(--agent-panel-soft);
  font-size: 13px;
  font-weight: 800;
}

.agent-status-action:active {
  opacity: 0.72;
}

.agent-thread {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 14px;
  min-height: 0;
  padding: 12px 16px 16px;
  overflow-y: auto;
  overscroll-behavior: contain;
  -webkit-overflow-scrolling: touch;
}

.agent-thread-empty {
  justify-content: flex-start;
}

.agent-thread-end {
  width: 1px;
  height: 1px;
}

.agent-empty {
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: min(100%, 680px);
  margin: 0 auto;
}

.agent-empty-mark {
  display: grid;
  place-items: center;
  width: 60px;
  height: 60px;
  border: 1px solid var(--agent-border);
  border-radius: 18px;
  color: var(--ion-color-primary);
  background: var(--agent-panel);
  box-shadow: 0 14px 34px rgba(0, 122, 255, 0.12);
  font-size: 28px;
}

.agent-empty-copy {
  display: grid;
  gap: 2px;
}

.agent-empty-kicker {
  margin: 0;
  color: var(--agent-muted);
  font-size: 11px;
  font-weight: 800;
  letter-spacing: 0.12em;
}

.agent-empty-title {
  margin: 0;
  font-size: 34px;
  font-weight: 900;
  letter-spacing: 0;
  line-height: 1.08;
}

.agent-examples {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.agent-example-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  max-width: 100%;
  min-height: 36px;
  border: 1px solid var(--agent-border);
  border-radius: 999px;
  padding: 0 12px;
  color: var(--ion-color-primary);
  background: var(--agent-chip-bg);
  font-size: 13px;
  font-weight: 800;
  box-shadow: var(--agent-shadow);
}

.agent-example-chip span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-example-chip:active {
  opacity: 0.72;
}

.agent-sample-cards {
  display: grid;
  gap: 10px;
}

.agent-error-bar {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin: 0 16px 10px;
  padding: 10px 12px;
  border: 1px solid color-mix(in srgb, var(--ion-color-danger) 32%, transparent);
  border-radius: 12px;
  color: var(--ion-color-danger);
  background: var(--agent-panel-strong);
  font-size: 13px;
}

.agent-error-bar button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  border: 0;
  color: inherit;
  background: transparent;
  font-weight: 800;
}

.agent-input-bar {
  flex-shrink: 0;
  display: flex;
  align-items: flex-end;
  gap: 10px;
  padding: 10px 14px calc(10px + var(--ion-safe-area-bottom, 0px));
  border-top: 1px solid var(--agent-border);
  background: var(--agent-input-bar-bg);
  box-shadow: 0 -14px 34px rgba(0, 0, 0, 0.06);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}

.agent-input {
  min-height: 42px;
  max-height: 112px;
  --background: var(--agent-input-bg);
  --border-radius: 18px;
  --color: var(--agent-text);
  --placeholder-color: var(--agent-muted);
  --placeholder-opacity: 1;
  --padding-start: 14px;
  --padding-end: 14px;
  --padding-top: 9px;
  --padding-bottom: 9px;
  font-size: 15px;
}

.agent-send-button {
  width: 42px;
  height: 42px;
  margin: 0;
  --padding-start: 0;
  --padding-end: 0;
}
</style>
