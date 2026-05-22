<script setup lang="ts">
import type { AppRecord } from '~/types/app'
import {
  alertController,
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonItemOption,
  IonItemOptions,
  IonItemSliding,
  IonLabel,
  IonList,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import {
  add,
  createOutline,
  globeOutline,
  trashOutline,
} from 'ionicons/icons'
import { DEFAULT_EMOJI } from '~/types/app'

const router = useRouter()
const toast = useToast()
const userStore = useUserStore()
const { getMyApps, deleteApp } = useApps()

const loading = ref(true)
const myApps = ref<AppRecord[]>([])
const initialized = ref(false)
/** 上次成功获取数据的时间戳 */
const lastFetchedAt = ref(0)
/** 数据过期阈值（毫秒），短时间返回不重新查询 */
const STALE_THRESHOLD = 30_000
/** 跨页面通信：子页面做了增删改后标记需要刷新 */
const workshopDirty = useState('workshop:dirty', () => false)

async function fetchMyApps() {
  try {
    loading.value = !initialized.value
    myApps.value = await getMyApps()
    initialized.value = true
    lastFetchedAt.value = Date.now()
    workshopDirty.value = false
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

function viewApp(app: AppRecord) {
  router.push(`/workshop/${app.slug}`)
}

function editApp(app: AppRecord, slidingItem?: any) {
  slidingItem?.close()
  router.push(`/workshop/${app.slug}/edit`)
}

function openApp(app: AppRecord, slidingItem?: any) {
  slidingItem?.close()
  if (app.websiteUrl)
    openInAppBrowser(app.websiteUrl)
}

async function confirmDeleteApp(app: AppRecord, slidingItem?: any) {
  slidingItem?.close()
  const alert = await alertController.create({
    header: '删除应用',
    message: `确定要删除「${app.name}」吗？此操作不可撤销。`,
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: '删除',
        role: 'destructive',
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
    ],
  })
  await alert.present()
}

function formatDate(ts: number) {
  return new Date(ts).toLocaleDateString('zh-CN', {
    month: 'short',
    day: 'numeric',
  })
}

function statusLabel(status: AppRecord['status']) {
  switch (status) {
    case 'pending': return '审核中'
    case 'rejected': return '已拒绝'
    case 'approved': return ''
    default: return ''
  }
}

onMounted(() => {
  if (userStore.isLoggedIn)
    fetchMyApps()
  else
    loading.value = false
})

onIonViewWillEnter(() => {
  if (!userStore.isLoggedIn || !initialized.value)
    return
  // 子页面标记了数据变更，或超过过期阈值，才重新查询
  if (workshopDirty.value || Date.now() - lastFetchedAt.value > STALE_THRESHOLD)
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
    <IonHeader>
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/apps" text="返回" />
        </IonButtons>
        <IonTitle>我的应用</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="userStore.isLoggedIn" @click="router.push('/workshop/new')">
            <IonIcon slot="icon-only" :icon="add" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <IonRefresher slot="fixed" @ion-refresh="handleRefresh">
        <IonRefresherContent />
      </IonRefresher>

      <!-- 未登录 -->
      <div v-if="!userStore.isLoggedIn" class="empty-state">
        <div class="empty-icon">
          🔒
        </div>
        <p class="empty-title">
          登录后管理你的应用
        </p>
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
        <p class="empty-title">
          还没有应用
        </p>
        <p class="empty-text">
          创建你的第一个应用吧
        </p>
        <IonButton fill="solid" shape="round" @click="router.push('/workshop/new')">
          创建应用
        </IonButton>
      </div>

      <!-- 应用列表 -->
      <IonList v-else inset class="app-list">
        <IonItemSliding v-for="app in myApps" :key="app._id">
          <IonItem button :detail="true" class="app-item" @click="viewApp(app)">
            <!-- 图标 -->
            <div slot="start" class="app-icon" :style="{ backgroundColor: app.themeColor || '#007AFF' }">
              <img v-if="app.logo" :src="app.logo" alt="" class="h-full w-full object-cover">
              <span v-else>{{ app.emoji || DEFAULT_EMOJI }}</span>
            </div>

            <IonLabel>
              <h2 class="app-name">
                {{ app.name }}
                <span v-if="!app.isPublic" class="private-badge">私有</span>
                <span
                  v-if="app.status && app.status !== 'approved'"
                  class="status-badge"
                  :class="`status-badge--${app.status}`"
                >{{ statusLabel(app.status) }}</span>
              </h2>
              <p v-if="app.description">
                {{ app.description }}
              </p>
              <p v-if="app.status === 'rejected' && app.rejectedReason" class="reject-reason">
                被拒原因：{{ app.rejectedReason }}
              </p>
              <p class="app-meta">
                <span v-if="app.category" class="meta-category">{{ app.category }}</span>
                <span class="meta-date">{{ formatDate(app.updatedAt || app.createdAt) }}</span>
              </p>
            </IonLabel>
          </IonItem>

          <!-- 左滑操作 -->
          <IonItemOptions side="end">
            <IonItemOption v-if="app.websiteUrl" color="primary" @click="openApp(app, $event.target?.closest('ion-item-sliding') as any)">
              <IonIcon slot="icon-only" :icon="globeOutline" />
            </IonItemOption>
            <IonItemOption color="warning" @click="editApp(app, $event.target?.closest('ion-item-sliding') as any)">
              <IonIcon slot="icon-only" :icon="createOutline" />
            </IonItemOption>
            <IonItemOption color="danger" @click="confirmDeleteApp(app, $event.target?.closest('ion-item-sliding') as any)">
              <IonIcon slot="icon-only" :icon="trashOutline" />
            </IonItemOption>
          </IonItemOptions>
        </IonItemSliding>
      </IonList>

      <!-- 底部统计 -->
      <div v-if="userStore.isLoggedIn && myApps.length > 0" class="list-footer">
        共 {{ myApps.length }} 个应用 · 左滑查看更多操作
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
  gap: 8px;
  padding: 80px 24px 0;
}

.empty-icon {
  font-size: 56px;
  opacity: 0.3;
  margin-bottom: 4px;
}

.empty-title {
  font-size: 20px;
  font-weight: 600;
  margin: 0;
}

.empty-text {
  text-align: center;
  font-size: 15px;
  opacity: 0.5;
  margin: 0 0 8px;
}

/* 列表 */
.app-list {
  margin-top: 8px;
}

.app-item {
  --padding-top: 10px;
  --padding-bottom: 10px;
}

.app-icon {
  width: 48px;
  height: 48px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 24px;
  overflow: hidden;
  flex-shrink: 0;
  position: relative;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
  margin-inline-end: 12px;
}

.app-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 12px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.app-name {
  display: flex;
  align-items: center;
  gap: 6px;
  font-weight: 600;
}

.private-badge {
  font-size: 10px;
  font-weight: 500;
  padding: 1px 6px;
  border-radius: 4px;
  background: var(--ylf-fill-tertiary);
  color: var(--ion-color-medium);
  flex-shrink: 0;
  vertical-align: middle;
}

.status-badge {
  font-size: 10px;
  font-weight: 500;
  padding: 1px 6px;
  border-radius: 4px;
  flex-shrink: 0;
  vertical-align: middle;
}

.status-badge--pending {
  background: rgba(var(--ion-color-warning-rgb), 0.16);
  color: var(--ion-color-warning-shade);
}

.status-badge--rejected {
  background: rgba(var(--ion-color-danger-rgb), 0.16);
  color: var(--ion-color-danger);
}

.reject-reason {
  font-size: 12px;
  color: var(--ion-color-danger);
  margin: 4px 0 0;
}

.app-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 2px;
}

.meta-category {
  font-size: 12px;
  font-weight: 500;
  color: var(--ion-color-primary);
}

.meta-date {
  font-size: 12px;
  color: var(--ion-color-medium);
  opacity: 0.7;
}

.list-footer {
  padding: 12px 24px 32px;
  text-align: center;
  font-size: 12px;
  opacity: 0.4;
}
</style>
