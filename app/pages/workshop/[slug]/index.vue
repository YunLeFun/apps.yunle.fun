<script setup lang="ts">
import type { AppRecord } from '~/types/app'
import {
  alertController,
  IonBackButton,
  IonButton,
  IonButtons,
  IonChip,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonNote,
  IonPage,
  IonSpinner,
  IonTitle,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import {
  createOutline,
  globeOutline,
  linkOutline,
  logoGithub,
  openOutline,
  trashOutline,
} from 'ionicons/icons'
import { DEFAULT_EMOJI } from '~/types/app'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const { getMyAppBySlug, deleteApp } = useApps()

/**
 * 从路由参数获取 slug
 * 注意：Ionic 页面栈中 useRoute() 返回全局路由，
 * 在 onIonViewWillEnter 触发时 route.params 可能尚未同步，
 * 因此 loadApp 接受显式传入 slug 作为优先值
 */
const slug = computed(() => (route.params as { slug?: string }).slug ?? '')
const loading = ref(true)
const loadError = ref('')
const app = ref<AppRecord | null>(null)
/** 当前页面绑定的 slug（首次解析后锁定） */
const pageSlug = ref('')

/** 从 URL 路径中提取 slug：/workshop/{slug} 或 /workshop/{slug}/... */
function resolveSlugFromUrl(): string {
  const match = window.location.pathname.match(/\/workshop\/([^/]+)/)
  return match?.[1] ?? ''
}

async function loadApp(explicitSlug?: string) {
  // 优先级：显式传入 > URL 解析 > route.params
  const currentSlug = explicitSlug || resolveSlugFromUrl() || slug.value
  if (!currentSlug)
    return

  pageSlug.value = currentSlug

  try {
    app.value = null
    loading.value = true
    loadError.value = ''
    app.value = await getMyAppBySlug(currentSlug)
    if (!app.value) {
      loadError.value = '应用不存在或无权访问'
    }
  }
  catch {
    loadError.value = '加载失败，请稍后重试'
  }
  finally {
    loading.value = false
  }
}

function openWebsite() {
  if (app.value?.websiteUrl)
    openInAppBrowser(app.value.websiteUrl, { trustedHosts: app.value.trustedHosts })
}

function openGitHub() {
  if (app.value?.githubRepo)
    window.open(`https://github.com/${app.value.githubRepo}`, '_blank')
}

function openBackupUrl() {
  if (app.value?.backupUrl)
    openInAppBrowser(app.value.backupUrl, { trustedHosts: app.value.trustedHosts })
}

function goEdit() {
  if (app.value)
    router.push(`/workshop/${app.value.slug}/edit`)
}

/** 标记列表页需要刷新 */
const workshopDirty = useState('workshop:dirty', () => false)

async function confirmDelete() {
  if (!app.value)
    return

  const alert = await alertController.create({
    header: '下架应用',
    message: `确定要下架「${app.value.name}」吗？应用会从目录移除，提交与审核记录仍会保留。`,
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: '下架',
        role: 'destructive',
        handler: async () => {
          try {
            await deleteApp(app.value!._id)
            workshopDirty.value = true
            toast.showSuccess('已下架')
            router.replace('/workshop')
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
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
}

onIonViewWillEnter(() => {
  // 直接从 URL 解析 slug，不依赖 Vue Router 响应式时序
  loadApp()
})

// 兜底：路由参数延迟更新时（如直接刷新），watch 确保触发加载
watch(slug, (val) => {
  if (val && val !== pageSlug.value)
    loadApp(val)
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/workshop" text="返回" />
        </IonButtons>
        <IonTitle>应用详情</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="app" @click="goEdit">
            <IonIcon slot="icon-only" :icon="createOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <!-- 加载中 -->
      <div v-if="loading" class="flex justify-center pt-20">
        <IonSpinner name="crescent" class="opacity-40" />
      </div>

      <!-- 加载失败 -->
      <div v-else-if="loadError" class="error-state">
        <div class="error-icon">
          😵
        </div>
        <p class="error-title">
          {{ loadError }}
        </p>
        <div class="error-actions">
          <IonButton fill="outline" shape="round" @click="loadApp">
            重试
          </IonButton>
          <IonButton fill="clear" shape="round" @click="router.replace('/workshop')">
            返回列表
          </IonButton>
        </div>
      </div>

      <div v-else-if="app" class="detail-content">
        <!-- 应用头部 -->
        <div class="app-hero">
          <div class="app-hero-icon" :style="{ backgroundColor: app.themeColor || '#007AFF' }">
            <img v-if="app.logo" :src="app.logo" alt="" class="h-full w-full object-cover">
            <span v-else class="app-hero-emoji">{{ app.emoji || DEFAULT_EMOJI }}</span>
          </div>
          <h1 class="app-hero-name">
            {{ app.name }}
          </h1>
          <div class="app-hero-badges">
            <IonChip v-if="app.category" class="hero-chip">
              {{ app.category }}
            </IonChip>
            <IonChip v-if="!app.isPublic" class="hero-chip hero-chip--private">
              未上架
            </IonChip>
            <IonChip v-if="app.releaseStage === 'beta'" class="hero-chip">
              Beta
            </IonChip>
            <IonChip v-if="app.accessMode === 'login_required'" class="hero-chip hero-chip--private">
              需登录
            </IonChip>
            <IonChip v-if="app.accessMode === 'invite_only'" class="hero-chip hero-chip--private">
              仅限受邀
            </IonChip>
          </div>
          <p v-if="app.description" class="app-hero-desc">
            {{ app.description }}
          </p>

          <!-- 主要操作按钮 -->
          <div v-if="app.websiteUrl" class="app-hero-actions">
            <IonButton expand="block" shape="round" class="open-btn" @click="openWebsite">
              <IonIcon slot="start" :icon="openOutline" />
              打开应用
            </IonButton>
          </div>
        </div>

        <!-- 标签 -->
        <div v-if="app.tags && app.tags.length" class="tags-section">
          <span v-for="tag in app.tags" :key="tag" class="tag-item">
            {{ tag }}
          </span>
        </div>

        <!-- 链接 -->
        <div v-if="app.websiteUrl || app.githubRepo || app.backupUrl" class="section-header">
          链接
        </div>
        <IonList v-if="app.websiteUrl || app.githubRepo || app.backupUrl" inset>
          <IonItem v-if="app.websiteUrl" button :detail="true" @click="openWebsite">
            <IonIcon slot="start" :icon="globeOutline" color="primary" />
            <IonLabel>
              <h3>网站</h3>
              <p>{{ app.websiteUrl }}</p>
            </IonLabel>
          </IonItem>

          <IonItem v-if="app.githubRepo" button :detail="true" @click="openGitHub">
            <IonIcon slot="start" :icon="logoGithub" />
            <IonLabel>
              <h3>GitHub</h3>
              <p>{{ app.githubRepo }}</p>
            </IonLabel>
          </IonItem>

          <IonItem v-if="app.backupUrl" button :detail="true" @click="openBackupUrl">
            <IonIcon slot="start" :icon="linkOutline" color="medium" />
            <IonLabel>
              <h3>备用链接</h3>
              <p>{{ app.backupUrl }}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <!-- 信息 -->
        <div class="section-header">
          信息
        </div>
        <IonList inset>
          <IonItem>
            <IonLabel>标识符</IonLabel>
            <IonNote slot="end" class="font-mono">
              {{ app.slug }}
            </IonNote>
          </IonItem>
          <IonItem>
            <IonLabel>目录状态</IonLabel>
            <IonNote slot="end">
              {{ app.publicationStatus === 'published' ? '已上架' : '未上架' }}
            </IonNote>
          </IonItem>
          <IonItem>
            <IonLabel>访问方式</IonLabel>
            <IonNote slot="end">
              {{ app.accessMode === 'invite_only' ? '仅限受邀' : app.accessMode === 'login_required' ? '需登录' : '公开访问' }}
            </IonNote>
          </IonItem>
          <IonItem>
            <IonLabel>审核状态</IonLabel>
            <IonNote slot="end">
              {{ app.latestSubmission?.reviewStatus || app.status }}
            </IonNote>
          </IonItem>
          <IonItem>
            <IonLabel>创建时间</IonLabel>
            <IonNote slot="end">
              {{ formatDate(app.createdAt) }}
            </IonNote>
          </IonItem>
          <IonItem>
            <IonLabel>更新时间</IonLabel>
            <IonNote slot="end">
              {{ formatDate(app.updatedAt || app.createdAt) }}
            </IonNote>
          </IonItem>
        </IonList>

        <!-- 操作 -->
        <div class="section-header">
          管理
        </div>
        <IonList inset>
          <IonItem button :detail="true" @click="goEdit">
            <IonIcon slot="start" :icon="createOutline" color="primary" />
            <IonLabel>编辑应用</IonLabel>
          </IonItem>
          <IonItem button :detail="false" class="delete-item" @click="confirmDelete">
            <IonIcon slot="start" :icon="trashOutline" color="danger" />
            <IonLabel color="danger">
              下架应用
            </IonLabel>
          </IonItem>
        </IonList>

        <div class="page-footer" />
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.detail-content {
  padding-bottom: env(safe-area-inset-bottom, 0);
}

/* Error State */
.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 80px 24px 0;
}

.error-icon {
  font-size: 48px;
  opacity: 0.4;
  margin-bottom: 4px;
}

.error-title {
  font-size: 17px;
  font-weight: 500;
  color: var(--ion-color-medium);
  text-align: center;
}

.error-actions {
  display: flex;
  gap: 8px;
  margin-top: 8px;
}

/* Hero */
.app-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 24px 24px 20px;
}

.app-hero-icon {
  width: 80px;
  height: 80px;
  border-radius: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1);
  position: relative;
}

.app-hero-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 20px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.app-hero-emoji {
  font-size: 40px;
}

.app-hero-name {
  font-size: 22px;
  font-weight: 700;
  margin: 12px 0 0;
  text-align: center;
}

.app-hero-badges {
  display: flex;
  gap: 6px;
  margin-top: 8px;
}

.hero-chip {
  --background: rgba(0, 122, 255, 0.08);
  --color: var(--ion-color-primary);
  font-size: 12px;
  font-weight: 500;
  height: 26px;
  margin: 0;
}

.hero-chip--private {
  --background: rgba(142, 142, 147, 0.12);
  --color: var(--ion-color-medium);
}

.app-hero-desc {
  font-size: 15px;
  color: var(--ion-color-medium);
  text-align: center;
  margin: 8px 0 0;
  max-width: 320px;
  line-height: 1.5;
}

.app-hero-actions {
  width: 100%;
  max-width: 300px;
  margin-top: 20px;
}

.open-btn {
  --border-radius: 14px;
  font-weight: 600;
  font-size: 17px;
  height: 50px;
}

/* Tags */
.tags-section {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 0 20px 16px;
  justify-content: center;
}

.tag-item {
  font-size: 13px;
  font-weight: 400;
  padding: 4px 12px;
  border-radius: 12px;
  background: rgba(142, 142, 147, 0.08);
  color: var(--ion-color-medium);
}

/* Section */
.section-header {
  padding: 24px 20px 6px;
  font-size: 13px;
  font-weight: 400;
  color: var(--ion-color-medium);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.page-footer {
  height: 40px;
}

/* Dark */
.dark .tag-item {
  background: rgba(118, 118, 128, 0.16);
}
</style>
