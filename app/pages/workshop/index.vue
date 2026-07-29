<script setup lang="ts">
import type { AppRecord, AppSubmissionAccess } from '~/types/app'
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
import { getYunLeFunSubmissionState } from '~/utils/yunlefunSubmission'

const router = useRouter()
const toast = useToast()
const userStore = useUserStore()
const { getMyApps, deleteApp, getSubmissionAccess } = useApps()

const loading = ref(true)
const myApps = ref<AppRecord[]>([])
const submissionAccess = ref<AppSubmissionAccess | null>(null)
const canCreateFirstParty = computed(() => submissionAccess.value?.canSubmitFirstParty === true)
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

async function fetchSubmissionAccess() {
  try {
    submissionAccess.value = await getSubmissionAccess()
  }
  catch {
    submissionAccess.value = null
  }
}

async function fetchWorkshop() {
  await Promise.all([fetchMyApps(), fetchSubmissionAccess()])
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
    openInAppBrowser(app.websiteUrl, { trustedHosts: app.trustedHosts })
}

async function confirmDeleteApp(app: AppRecord, slidingItem?: any) {
  slidingItem?.close()
  const alert = await alertController.create({
    header: '下架应用',
    message: `确定要下架「${app.name}」吗？应用会从目录移除，提交与审核记录仍会保留。`,
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: '下架',
        role: 'destructive',
        handler: async () => {
          try {
            await deleteApp(app._id)
            myApps.value = myApps.value.filter(a => a._id !== app._id)
            toast.showSuccess('已下架')
          }
          catch (err: unknown) {
            toast.showError(err instanceof Error ? err.message : '下架失败')
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

function yunlefunStateFor(app: AppRecord) {
  return getYunLeFunSubmissionState(app)
}

function yunlefunStateTone(app: AppRecord) {
  const status = yunlefunStateFor(app).status
  if (status === 'listed')
    return 'success'
  if (status === 'pending' || status === 'in_review' || status === 'awaiting_publication')
    return 'warning'
  if (status === 'changes_requested' || status === 'rejected' || status === 'suspended')
    return 'danger'
  return 'default'
}

onMounted(() => {
  if (userStore.isLoggedIn)
    fetchWorkshop()
  else
    loading.value = false
})

onIonViewWillEnter(() => {
  if (!userStore.isLoggedIn || !initialized.value)
    return
  // 子页面标记了数据变更，或超过过期阈值，才重新查询
  if (workshopDirty.value || Date.now() - lastFetchedAt.value > STALE_THRESHOLD)
    fetchWorkshop()
})

watch(() => userStore.isLoggedIn, (loggedIn) => {
  if (loggedIn) {
    fetchWorkshop()
  }
  else {
    myApps.value = []
    submissionAccess.value = null
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
          <IonButton v-if="userStore.isLoggedIn && canCreateFirstParty" @click="router.push('/workshop/new')">
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
          {{ canCreateFirstParty ? '创建你的第一个一方应用吧' : '第三方应用入驻敬请期待' }}
        </p>
        <IonButton v-if="canCreateFirstParty" fill="solid" shape="round" @click="router.push('/workshop/new')">
          创建应用
        </IonButton>
      </div>

      <!-- 应用列表 -->
      <IonList v-else inset class="app-list">
        <IonItemSliding v-for="app in myApps" :key="app._id">
          <IonItem button :detail="true" class="app-item" @click="viewApp(app)">
            <!-- 图标 -->
            <AppIconBox
              slot="start"
              class="workshop-app-icon"
              :icon="app.logo"
              :emoji="app.emoji || DEFAULT_EMOJI"
              :color="app.themeColor || '#007AFF'"
              size="list"
            />

            <IonLabel>
              <h2 class="app-name">
                {{ app.name }}
                <span v-if="app.releaseStage === 'beta'" class="private-badge">Beta</span>
                <span v-if="app.accessMode === 'login_required'" class="private-badge">需登录</span>
                <span v-if="app.accessMode === 'invite_only'" class="private-badge">仅限受邀</span>
                <span
                  class="status-badge"
                  :class="`status-badge--${yunlefunStateTone(app)}`"
                >{{ yunlefunStateFor(app).statusLabel }}</span>
              </h2>
              <p v-if="app.description">
                {{ app.description }}
              </p>
              <p
                v-if="['changes_requested', 'rejected'].includes(yunlefunStateFor(app).status)"
                class="reject-reason"
              >
                审核意见：{{ yunlefunStateFor(app).detail }}
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
        <p>共 {{ myApps.length }} 个应用 · 左滑查看更多操作</p>
        <p v-if="!canCreateFirstParty">
          第三方应用入驻敬请期待
        </p>
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

.workshop-app-icon {
  flex-shrink: 0;
  margin-inline-end: 12px;
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

.status-badge--default {
  background: var(--ylf-fill-tertiary);
  color: var(--ion-color-medium);
}

.status-badge--success {
  background: rgba(var(--ion-color-success-rgb), 0.14);
  color: var(--ion-color-success-shade);
}

.status-badge--warning {
  background: rgba(var(--ion-color-warning-rgb), 0.16);
  color: var(--ion-color-warning-shade);
}

.status-badge--danger {
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
