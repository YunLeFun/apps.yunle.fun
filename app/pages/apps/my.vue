<script setup lang="ts">
import type { AppRecord } from '~/types/app'
import {
  actionSheetController,
  IonBackButton,
  IonButton,
  IonButtons,
  IonChip,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import { add, chevronForward, ellipsisHorizontal, globe, logoGithub, pencil, trash } from 'ionicons/icons'
import { DEFAULT_EMOJI } from '~/types/app'

const router = useRouter()
const toast = useToast()
const userStore = useUserStore()
const { getMyApps, deleteApp } = useApps()

const loading = ref(true)
const myApps = ref<AppRecord[]>([])
const initialized = ref(false)

async function fetchMyApps() {
  try {
    loading.value = !initialized.value
    myApps.value = await getMyApps()
    initialized.value = true
  }
  catch (err: unknown) {
    toast.showError(err instanceof Error ? err.message : '加载失败')
  }
  finally {
    loading.value = false
  }
}

async function handleRefresh(event: CustomEvent) {
  await fetchMyApps()
  ;(event.target as HTMLIonRefresherElement).complete()
}

async function showAppActions(app: AppRecord) {
  const buttons: any[] = [
    {
      text: '编辑',
      icon: pencil,
      handler: () => {
        router.push(`/apps/${app.slug}/edit`)
      },
    },
  ]

  if (app.websiteUrl) {
    buttons.push({
      text: '打开网站',
      icon: globe,
      handler: () => { window.open(app.websiteUrl, '_blank') },
    })
  }

  if (app.githubRepo) {
    buttons.push({
      text: 'GitHub 仓库',
      icon: logoGithub,
      handler: () => { window.open(`https://github.com/${app.githubRepo}`, '_blank') },
    })
  }

  buttons.push(
    {
      text: '删除',
      role: 'destructive',
      icon: trash,
      handler: async () => {
        try {
          await deleteApp(app._id)
          myApps.value = myApps.value.filter(a => a._id !== app._id)
          toast.showSuccess('已删除')
        }
        catch {
          toast.showError('删除失败')
        }
      },
    },
    { text: '取消', role: 'cancel' },
  )

  const actionSheet = await actionSheetController.create({
    header: app.name,
    buttons,
  })
  await actionSheet.present()
}

function formatDate(ts: number) {
  return new Date(ts).toLocaleDateString('zh-CN', {
    month: 'short',
    day: 'numeric',
  })
}

onMounted(() => {
  if (userStore.isLoggedIn)
    fetchMyApps()
  else
    loading.value = false
})

onIonViewWillEnter(() => {
  if (userStore.isLoggedIn && initialized.value)
    fetchMyApps()
})

watch(() => userStore.isLoggedIn, (loggedIn) => {
  if (loggedIn) {
    fetchMyApps()
  }
  else {
    myApps.value = []
    loading.value = false
  }
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/apps" text="返回" />
        </IonButtons>
        <IonTitle>我的应用</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="userStore.isLoggedIn" @click="router.push('/apps/new')">
            <IonIcon slot="icon-only" :icon="add" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            我的应用
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <IonRefresher slot="fixed" @ion-refresh="handleRefresh">
        <IonRefresherContent />
      </IonRefresher>

      <!-- 未登录 -->
      <div v-if="!userStore.isLoggedIn" class="empty-state">
        <p class="empty-text">
          登录后可以创建和管理你的应用
        </p>
        <IonButton fill="solid" shape="round" @click="router.push('/login')">
          去登录
        </IonButton>
      </div>

      <!-- 加载中 -->
      <div v-else-if="loading" class="flex justify-center pt-20">
        <IonSpinner name="crescent" class="opacity-40" />
      </div>

      <!-- 空状态 -->
      <div v-else-if="myApps.length === 0" class="empty-state">
        <div class="empty-icon">
          📦
        </div>
        <p class="empty-text">
          还没有应用，创建一个吧
        </p>
        <IonButton fill="solid" shape="round" @click="router.push('/apps/new')">
          创建应用
        </IonButton>
      </div>

      <!-- 应用列表 -->
      <div v-else class="app-list">
        <div
          v-for="app in myApps"
          :key="app._id"
          class="app-card"
          @click="router.push(`/apps/${app.slug}/edit`)"
        >
          <div class="app-card-main">
            <!-- 图标 -->
            <div class="app-card-icon" :style="{ backgroundColor: app.themeColor || '#007AFF' }">
              <img
                v-if="app.logo"
                :src="app.logo"
                alt=""
                class="h-full w-full object-cover"
              >
              <span v-else>{{ app.emoji || DEFAULT_EMOJI }}</span>
            </div>

            <!-- 信息 -->
            <div class="app-card-info">
              <div class="app-card-header">
                <h3 class="app-card-name">
                  {{ app.name }}
                </h3>
                <span v-if="!app.isPublic" class="private-badge">私有</span>
              </div>
              <p v-if="app.description" class="app-card-desc">
                {{ app.description }}
              </p>
              <div class="app-card-meta">
                <IonChip v-if="app.category" class="meta-chip">
                  {{ app.category }}
                </IonChip>
                <span class="meta-date">{{ formatDate(app.updatedAt || app.createdAt) }}</span>
              </div>
            </div>

            <!-- 操作 -->
            <div class="app-card-actions">
              <button class="action-more" @click.stop="showAppActions(app)">
                <IonIcon :icon="ellipsisHorizontal" />
              </button>
              <IonIcon :icon="chevronForward" class="action-chevron" />
            </div>
          </div>

          <!-- 标签行 -->
          <div v-if="app.tags && app.tags.length" class="app-card-tags">
            <span
              v-for="tag in app.tags.slice(0, 5)"
              :key="tag"
              class="tag-badge"
            >
              {{ tag }}
            </span>
            <span v-if="app.tags.length > 5" class="tag-more">+{{ app.tags.length - 5 }}</span>
          </div>
        </div>
      </div>

      <!-- 底部统计 -->
      <div v-if="userStore.isLoggedIn && myApps.length > 0" class="list-footer">
        共 {{ myApps.length }} 个应用
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
/* 空状态 */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  padding: 80px 24px 0;
}

.empty-icon {
  font-size: 48px;
  opacity: 0.3;
}

.empty-text {
  text-align: center;
  font-size: 15px;
  opacity: 0.5;
}

/* 应用列表 */
.app-list {
  padding: 8px 16px 0;
}

.app-card {
  background: var(--ion-item-background, var(--ion-background-color, #fff));
  border-radius: 14px;
  padding: 14px;
  margin-bottom: 10px;
  cursor: pointer;
  transition: transform 0.15s ease;
  -webkit-tap-highlight-color: transparent;
}

.app-card:active {
  transform: scale(0.98);
}

.app-card-main {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}

.app-card-icon {
  width: 52px;
  height: 52px;
  border-radius: 13px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 26px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  position: relative;
}

.app-card-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 13px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.app-card-info {
  flex: 1;
  min-width: 0;
}

.app-card-header {
  display: flex;
  align-items: center;
  gap: 6px;
}

.app-card-name {
  font-size: 16px;
  font-weight: 600;
  line-height: 1.3;
  margin: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.private-badge {
  font-size: 10px;
  font-weight: 500;
  padding: 1px 6px;
  border-radius: 4px;
  background: rgba(142, 142, 147, 0.12);
  color: var(--ion-color-medium);
  flex-shrink: 0;
}

.app-card-desc {
  font-size: 13px;
  color: var(--ion-color-medium);
  margin: 2px 0 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-card-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
}

.meta-chip {
  --background: rgba(0, 122, 255, 0.08);
  --color: var(--ion-color-primary);
  font-size: 11px;
  font-weight: 500;
  height: 22px;
  margin: 0;
  padding: 0 8px;
}

.meta-date {
  font-size: 11px;
  color: var(--ion-color-medium);
  opacity: 0.7;
}

.app-card-actions {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding-top: 2px;
  flex-shrink: 0;
}

.action-more {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 50%;
  border: none;
  background: rgba(142, 142, 147, 0.08);
  color: var(--ion-color-medium);
  font-size: 18px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.action-more:active {
  background: rgba(142, 142, 147, 0.16);
}

.action-chevron {
  font-size: 16px;
  color: var(--ion-color-medium);
  opacity: 0.4;
}

/* 标签行 */
.app-card-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 10px;
  padding-top: 10px;
  border-top: 0.5px solid rgba(142, 142, 147, 0.12);
}

.tag-badge {
  font-size: 11px;
  font-weight: 400;
  padding: 2px 8px;
  border-radius: 10px;
  background: rgba(142, 142, 147, 0.08);
  color: var(--ion-color-medium);
}

.tag-more {
  font-size: 11px;
  color: var(--ion-color-medium);
  opacity: 0.6;
  padding: 2px 4px;
}

.list-footer {
  padding: 8px 24px 32px;
  text-align: center;
  font-size: 12px;
  opacity: 0.4;
}

/* 暗色适配 */
.dark .app-card {
  background: var(--ion-item-background, #1c1c1e);
}

.dark .action-more {
  background: rgba(118, 118, 128, 0.16);
}

.dark .tag-badge {
  background: rgba(118, 118, 128, 0.16);
}
</style>
