<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import type { AgentAppCard } from '~/types/agent'
import { IonIcon } from '@ionic/vue'
import { addCircleOutline, arrowForwardOutline, openOutline, starOutline } from 'ionicons/icons'

const props = defineProps<{
  card: AgentAppCard
  compact?: boolean
}>()

const router = useRouter()
const homeScreenStore = useHomeScreenStore()
const { getApp, ensureLoaded } = useAppCatalog()
const { installApp } = useHomeScreen()
const { openApp } = useOpenApp()
const { showSuccess } = useToast()

onMounted(() => {
  ensureLoaded()
})

const resolvedApp = computed(() => getApp(props.card.slug || props.card.id || ''))

const appInfo = computed<YlfAppInfo>(() => {
  if (resolvedApp.value)
    return resolvedApp.value

  return {
    id: props.card.id || props.card.slug,
    slug: props.card.slug,
    name: props.card.name,
    description: props.card.description,
    logo: props.card.logo,
    emoji: props.card.emoji || '📱',
    themeColor: props.card.themeColor || '#007AFF',
    websiteUrl: props.card.websiteUrl || '',
    category: props.card.category,
    rating: props.card.rating,
    ratingCount: props.card.ratingCount,
    coinCost: props.card.coinCost,
    requiresMembership: props.card.requiresMembership,
    trustedHosts: props.card.trustedHosts ? [...props.card.trustedHosts] : undefined,
  }
})

const appKey = computed(() => appInfo.value.slug || appInfo.value.id)
const installed = computed(() => homeScreenStore.isInstalled(appKey.value))
const canOpenDirectly = computed(() => Boolean(appInfo.value.websiteUrl))
const primaryActionLabel = computed(() => {
  if (!installed.value)
    return '添加'
  return canOpenDirectly.value ? '打开' : '详情'
})
const normalizedReason = computed(() => {
  const reason = props.card.reason?.trim()
  if (!reason || reason === appInfo.value.description || reason === appInfo.value.name)
    return ''
  return reason
})
const metaItems = computed(() => {
  const items: string[] = []
  if (appInfo.value.category)
    items.push(appInfo.value.category)
  if (typeof appInfo.value.rating === 'number' && appInfo.value.rating > 0)
    items.push(appInfo.value.rating.toFixed(1))
  if (appInfo.value.requiresMembership)
    items.push('会员')
  else if (appInfo.value.coinCost)
    items.push(`${appInfo.value.coinCost} 云币`)
  return items
})

function goDetail() {
  router.push(`/app/${appKey.value}`)
}

async function handlePrimary() {
  if (installed.value) {
    if (canOpenDirectly.value) {
      await openApp(appInfo.value)
    }
    else {
      goDetail()
    }
    return
  }

  installApp(appKey.value)
  showSuccess(`已添加「${appInfo.value.name}」`)
}
</script>

<template>
  <article class="agent-app-card" :class="{ 'agent-app-card-compact': compact }">
    <button class="agent-app-card-main" type="button" @click="goDetail">
      <AppIconBox
        class="agent-app-card-icon"
        :icon="appInfo.logo"
        :emoji="appInfo.emoji"
        :color="appInfo.themeColor"
        size="list"
      />

      <div class="agent-app-card-body">
        <div class="agent-app-card-title-row">
          <h3 class="agent-app-card-title">
            {{ appInfo.name }}
          </h3>
        </div>
        <div v-if="metaItems.length > 0" class="agent-app-card-meta">
          <template v-for="item in metaItems" :key="item">
            <span class="agent-app-card-meta-item">
              <IonIcon v-if="item.includes('.')" :icon="starOutline" />
              {{ item }}
            </span>
          </template>
        </div>
        <p v-if="appInfo.description" class="agent-app-card-desc">
          {{ appInfo.description }}
        </p>
        <p v-if="normalizedReason" class="agent-app-card-reason">
          {{ normalizedReason }}
        </p>
      </div>
    </button>

    <div class="agent-app-card-actions">
      <button class="agent-app-card-action" type="button" @click="handlePrimary">
        <IonIcon :icon="installed ? openOutline : addCircleOutline" />
        <span>{{ primaryActionLabel }}</span>
      </button>
      <button
        v-if="!compact"
        class="agent-app-card-action agent-app-card-action-secondary"
        type="button"
        @click="goDetail"
      >
        <IonIcon :icon="arrowForwardOutline" />
        <span>详情</span>
      </button>
    </div>
  </article>
</template>

<style scoped>
.agent-app-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  width: 100%;
  padding: 12px;
  border: 1px solid var(--agent-border, rgba(0, 0, 0, 0.08));
  border-radius: 14px;
  color: var(--agent-text, var(--ion-text-color));
  background: var(--agent-card-bg, rgba(255, 255, 255, 0.82));
  box-shadow: var(--agent-shadow, 0 12px 30px rgba(0, 0, 0, 0.05));
}

.agent-app-card-compact {
  gap: 10px;
}

.agent-app-card-main {
  display: flex;
  gap: 12px;
  min-width: 0;
  border: 0;
  padding: 0;
  color: inherit;
  text-align: left;
  background: transparent;
}

.agent-app-card-main:active {
  opacity: 0.72;
}

.agent-app-card-icon {
  flex-shrink: 0;
}

.agent-app-card-body {
  min-width: 0;
  flex: 1;
}

.agent-app-card-title-row {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
}

.agent-app-card-title {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  font-size: 15px;
  font-weight: 800;
  line-height: 1.3;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-app-card-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
  margin-top: 4px;
}

.agent-app-card-meta-item {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  min-height: 18px;
  border-radius: 999px;
  padding: 0 6px;
  color: var(--agent-muted, var(--ion-color-medium));
  background: var(--agent-meta-bg, var(--ylf-fill-tertiary));
  font-size: 10px;
  font-weight: 800;
}

.agent-app-card-desc,
.agent-app-card-reason {
  display: -webkit-box;
  margin: 5px 0 0;
  overflow: hidden;
  color: var(--agent-muted, var(--ion-color-medium));
  font-size: 12px;
  line-height: 1.45;
  -webkit-box-orient: vertical;
}

.agent-app-card-desc {
  -webkit-line-clamp: 2;
  line-clamp: 2;
}

.agent-app-card-reason {
  color: var(--agent-accent-text, color-mix(in srgb, var(--ion-color-primary) 72%, var(--ion-color-medium)));
  -webkit-line-clamp: 2;
  line-clamp: 2;
}

.agent-app-card-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.agent-app-card-compact .agent-app-card-actions {
  grid-template-columns: 1fr;
}

.agent-app-card-action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 5px;
  min-height: 34px;
  border: 0;
  border-radius: 11px;
  color: #fff;
  background: var(--ion-color-primary);
  font-size: 13px;
  font-weight: 800;
}

.agent-app-card-action-secondary {
  color: var(--ion-color-primary);
  background: var(--agent-panel-soft, var(--ylf-fill-tertiary));
}

.agent-app-card-action:active {
  opacity: 0.72;
}
</style>
