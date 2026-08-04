<script setup lang="ts">
import type { ReviewSummary } from '~/types/review'
import {
  actionSheetController,
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonToolbar,
} from '@ionic/vue'
import { chevronForward, ellipsisHorizontal, globeOutline, share } from 'ionicons/icons'

const route = useRoute()
const router = useRouter()
const { ensureLoaded, getAppsByDeveloper } = useAppCatalog()

function resolveAppIdFromUrl(): string {
  if (!import.meta.client)
    return ''
  const pathId = window.location.pathname.match(/\/app\/([^/]+)/)?.[1]
  return pathId ? decodeURIComponent(pathId) : ''
}

const appId = computed(() => {
  const routeId = route.params.id
  const paramId = Array.isArray(routeId) ? routeId[0] : routeId
  if (paramId)
    return paramId

  return resolveAppIdFromUrl()
})
const appReportOpen = ref(false)
const reviewSummary = ref<ReviewSummary | null>(null)

// 使用 useAppDetail composable 获取应用数据
const { appData, loading, error, refresh } = useAppDetail(appId)

const reviewAppKey = computed(() => appData.value?.slug || appData.value?.id || '')
// 评分一律以真实评论聚合为准：无评论显示「暂无评分」，不再回退运营预设
const hasRating = computed(() => (reviewSummary.value?.count ?? 0) > 0)
const ratingCount = computed(() => reviewSummary.value?.count ?? 0)
const displayRating = computed(() => (hasRating.value ? reviewSummary.value!.average : 0))

// 扩展展示数据
const displayData = computed(() => {
  if (!appData.value)
    return null

  const urlHost = getUrlHost(appData.value.websiteUrl)

  return {
    ...appData.value,
    previewPanels: [
      {
        id: 'overview',
        eyebrow: appData.value.category || '应用',
        title: appData.value.name,
        body: appData.value.description || appData.value.tagline || '打开应用，开始体验。',
      },
      {
        id: 'launch',
        eyebrow: '立即访问',
        title: urlHost || '站内应用',
        body: appData.value.websiteUrl || '应用暂未配置打开地址',
      },
      {
        id: 'meta',
        eyebrow: appData.value.developer || '开发者',
        title: '了解更多',
        body: appData.value.tagline || appData.value.description || '打开应用，开始体验。',
      },
    ],
  }
})

function getUrlHost(url?: string) {
  if (!url)
    return ''
  if (!url.startsWith('http'))
    return 'yunle.fun'
  try {
    return new URL(url).host
  }
  catch {
    return url
  }
}

// 头部副标题：优先标语，回退分类
const subtitle = computed(() => displayData.value?.tagline || displayData.value?.category || '网页应用')

// 开发者：'Unknown' / 空 视为不可跳转
const developer = computed(() => displayData.value?.developer || '')
const developerActive = computed(() => Boolean(developer.value) && developer.value !== 'Unknown')

// 开发者展示名：应用记录 developerName > GitHub 资料 name > 登录名
const { profile: devProfile } = useGithubProfile(developer)
const developerDisplay = computed(() =>
  displayData.value?.developerName || devProfile.value?.name || developer.value,
)

// 网站域名（信息区「网站」行展示）
const websiteHost = computed(() => getUrlHost(displayData.value?.websiteUrl))

// 真实截图（预览区），缺省回退占位面板
const screenshots = computed(() => displayData.value?.screenshots ?? [])

// App 内购买项目 / 会员专属 / 价格
const coinCost = computed(() => displayData.value?.coinCost ?? 0)
const requiresMembership = computed(() => displayData.value?.requiresMembership === true)
const hasIap = computed(() => coinCost.value > 0 || requiresMembership.value)
const priceText = computed(() => {
  if (coinCost.value > 0)
    return `${coinCost.value} 云币`
  if (requiresMembership.value)
    return '会员专属'
  return '免费'
})

// 同一开发者的其他应用（排除当前应用）
const otherApps = computed(() => {
  if (!developerActive.value)
    return []
  return getAppsByDeveloper(developer.value)
    .filter(a => a.slug !== displayData.value?.slug && a.id !== displayData.value?.id)
    .slice(0, 12)
})

// 嵌入态：详情页被原生容器以 sheet 盖在应用之上打开（window.ylf 注入）
const isEmbedded = ref(false)

// 目录用于「其他 App」聚合，确保运行时已从集合回填 developer
onMounted(() => {
  ensureLoaded()
  isEmbedded.value = typeof window !== 'undefined' && Boolean((window as any).ylf?.inYunleApp)
  // 从「查看评价」入口进来时定位到评价区
  if (typeof window !== 'undefined' && window.location.hash === '#reviews') {
    nextTick(() => document.getElementById('app-reviews')?.scrollIntoView({ block: 'start' }))
  }
})

// 嵌入态「回到应用」：收起详情 sheet 回到下层应用容器
function backToApp() {
  ;(window as any).ylf?.invoke?.('close')
}

function goDeveloper() {
  if (developerActive.value)
    router.push(`/developer/${encodeURIComponent(developer.value)}`)
}

function goApp(app: { id: string, slug: string }) {
  router.push(`/app/${app.slug || app.id}`)
}

// 在内置浏览器中打开应用网站
function openWebsite() {
  const url = displayData.value?.websiteUrl
  if (!url || !url.startsWith('http'))
    return
  openCatalogAppInBrowser({ ...displayData.value, websiteUrl: url })
}

// 打开 GitHub 仓库
function openGithub() {
  const repo = displayData.value?.githubRepo
  if (!repo)
    return
  openInAppBrowser(`https://github.com/${repo}`)
}

function openPolicyUrl(url?: string) {
  if (url?.startsWith('https://'))
    openInAppBrowser(url)
}

function formatRating(rating: number) {
  return Number.isInteger(rating) ? String(rating) : rating.toFixed(1)
}

// 分享应用
const { shareApp: shareAppAction } = useAppActions()
async function shareApp() {
  if (!appData.value)
    return
  await shareAppAction(appData.value)
}

/**
 * 应用详情更多操作菜单（举报）
 *
 * App Store 审核指南 1.2 要求 UGC 内容必须提供举报入口
 */
async function openMoreMenu() {
  const app = appData.value
  if (!app)
    return

  const sheet = await actionSheetController.create({
    header: app.name,
    buttons: [
      {
        text: '举报此应用',
        role: 'destructive',
        handler: () => {
          appReportOpen.value = true
        },
      },
      { text: '取消', role: 'cancel' },
    ],
  })
  await sheet.present()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/apps" text="" />
        </IonButtons>
        <IonButtons slot="end">
          <IonButton @click="shareApp">
            <IonIcon slot="icon-only" :icon="share" />
          </IonButton>
          <IonButton aria-label="更多" @click="openMoreMenu">
            <IonIcon slot="icon-only" :icon="ellipsisHorizontal" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="app-detail-content">
      <!-- 加载骨架屏 -->
      <div v-if="loading" class="app-detail-container">
        <div class="app-header">
          <div class="app-header-content">
            <div class="app-icon-large skeleton-pulse" />
            <div class="app-header-info">
              <div class="skeleton-line skeleton-pulse" style="width: 70%; height: 22px;" />
              <div class="skeleton-line skeleton-pulse" style="width: 45%; height: 15px;" />
              <div class="skeleton-line skeleton-pulse" style="width: 40%; height: 14px;" />
            </div>
            <div class="skeleton-button skeleton-pulse" />
          </div>
        </div>
      </div>

      <!-- 应用详情 -->
      <div v-else-if="displayData" class="app-detail-container">
        <!-- 应用头部信息 -->
        <div class="app-header">
          <div class="app-header-content">
            <AppIconBox
              class="app-header-icon flex-shrink-0"
              :icon="displayData.logo"
              :emoji="displayData.emoji"
              :color="displayData.themeColor"
              size="xl"
            />

            <div class="app-header-info">
              <div class="app-name-row">
                <h1 class="app-name">
                  {{ displayData.name }}
                </h1>
                <AppVerifiedBadge v-if="displayData.official" size="20px" />
              </div>
              <p class="app-subtitle">
                {{ subtitle }}
              </p>
              <button
                v-if="developerActive"
                type="button"
                class="app-developer-link"
                @click="goDeveloper"
              >
                <span class="truncate">{{ developerDisplay }}</span>
                <IonIcon :icon="chevronForward" class="developer-link-chevron" />
              </button>
              <p v-else class="app-developer-static">
                {{ developerDisplay || '未知开发者' }}
              </p>
            </div>

            <!-- 获取 → 打开（与列表同款按钮），置于图标右侧；嵌入态改「回到应用」 -->
            <div class="app-header-action">
              <IonButton v-if="isEmbedded" size="small" shape="round" @click="backToApp">
                回到应用
              </IonButton>
              <template v-else>
                <AppInstallButton :app="displayData" />
                <span v-if="hasIap" class="app-iap-hint">{{ priceText }}</span>
              </template>
            </div>
          </div>

          <!-- 应用信息栏 -->
          <div class="app-info-bar">
            <div class="info-item">
              <div class="info-value">
                {{ hasRating ? formatRating(displayRating) : '暂无' }}
              </div>
              <div class="info-label">
                {{ hasRating ? `${ratingCount} 评分` : '评分' }}
              </div>
            </div>
            <div v-if="displayData.age" class="info-divider" />
            <div v-if="displayData.age" class="info-item">
              <div class="info-value">
                {{ displayData.age }}
              </div>
              <div class="info-label">
                年龄
              </div>
            </div>
            <div class="info-divider" />
            <button
              type="button"
              class="info-item info-item-btn"
              :class="{ 'info-item--tappable': developerActive }"
              @click="goDeveloper"
            >
              <div class="info-value info-value-clip">
                {{ developerDisplay || '—' }}
              </div>
              <div class="info-label">
                开发者
              </div>
            </button>
          </div>
        </div>

        <!-- 新功能 -->
        <div v-if="displayData.whatsNew" class="section">
          <div class="section-header">
            <h2 class="section-title">
              新功能
            </h2>
            <button class="version-history-btn">
              版本记录
            </button>
          </div>
          <div class="section-content">
            <div class="version-info">
              <span class="version-number">版本 {{ displayData.version }}</span>
              <span v-if="displayData.updateDate" class="update-date">{{ displayData.updateDate }}</span>
            </div>
            <p class="whats-new-text">
              {{ displayData.whatsNew }}
            </p>
          </div>
        </div>

        <!-- 截图预览 -->
        <div class="section">
          <h2 class="section-title">
            预览
          </h2>
          <div class="screenshots-container">
            <!-- 真实截图优先 -->
            <template v-if="screenshots.length">
              <div
                v-for="(src, i) in screenshots"
                :key="i"
                class="screenshot-shot"
              >
                <img
                  :src="src"
                  :alt="`${displayData.name} 截图 ${i + 1}`"
                  loading="lazy"
                  class="screenshot-img"
                >
              </div>
            </template>
            <!-- 无截图时回退占位面板 -->
            <template v-else>
              <div
                v-for="panel in displayData.previewPanels"
                :key="panel.id"
                class="screenshot-item preview-panel"
                :style="{ '--preview-color': displayData.themeColor }"
              >
                <div class="preview-panel-orb">
                  <img v-if="displayData.logo" :src="displayData.logo" alt="" class="preview-panel-logo">
                  <span v-else>{{ displayData.emoji }}</span>
                </div>
                <div class="preview-panel-content">
                  <div class="preview-panel-eyebrow">
                    {{ panel.eyebrow }}
                  </div>
                  <div class="preview-panel-title">
                    {{ panel.title }}
                  </div>
                  <p class="preview-panel-body">
                    {{ panel.body }}
                  </p>
                </div>
              </div>
            </template>
          </div>
        </div>

        <!-- 应用描述 -->
        <div v-if="displayData.description" class="section">
          <div class="section-header">
            <h2 class="section-title">
              简介
            </h2>
          </div>
          <div class="section-content">
            <p class="description-text">
              {{ displayData.description }}
            </p>
          </div>
        </div>

        <AppReviewSection
          id="app-reviews"
          :app-key="reviewAppKey"
          :app-name="displayData.name"
          :app-icon="displayData.logo"
          @summary="reviewSummary = $event"
        />

        <!-- 信息 -->
        <div class="section">
          <h2 class="section-title">
            信息
          </h2>
          <div class="info-list">
            <button
              type="button"
              class="info-row info-row-btn"
              :class="{ 'info-row--tappable': developerActive }"
              @click="goDeveloper"
            >
              <span class="info-row-label">开发者</span>
              <div class="info-row-value" :class="{ 'info-row-value--link': developerActive }">
                <span class="truncate">{{ developerDisplay || '未知' }}</span>
                <IonIcon v-if="developerActive" :icon="chevronForward" class="chevron-icon" />
              </div>
            </button>
            <button
              v-if="!isEmbedded && websiteHost && displayData.websiteUrl?.startsWith('http')"
              type="button"
              class="info-row info-row-btn info-row--tappable"
              @click="openWebsite"
            >
              <span class="info-row-label">网站</span>
              <div class="info-row-value info-row-value--link">
                <span class="truncate">{{ websiteHost }}</span>
                <IonIcon :icon="globeOutline" class="chevron-icon" />
              </div>
            </button>
            <div v-if="displayData.category" class="info-row">
              <span class="info-row-label">类别</span>
              <span class="info-row-value">{{ displayData.category }}</span>
            </div>
            <div class="info-row">
              <span class="info-row-label">兼容性</span>
              <span class="info-row-value">{{ displayData.compatibility }}</span>
            </div>
            <div class="info-row">
              <span class="info-row-label">语言</span>
              <span class="info-row-value">{{ displayData.languages.join('、') }}</span>
            </div>
            <div v-if="displayData.age" class="info-row">
              <span class="info-row-label">年龄分级</span>
              <span class="info-row-value">{{ displayData.age }}</span>
            </div>
            <div class="info-row">
              <span class="info-row-label">价格</span>
              <span class="info-row-value">{{ priceText }}</span>
            </div>
            <div v-if="hasIap" class="info-row">
              <span class="info-row-label">App 内购买项目</span>
              <span class="info-row-value">{{ requiresMembership ? '会员专属' : '是' }}</span>
            </div>
            <button
              v-if="displayData.githubRepo"
              type="button"
              class="info-row info-row-btn info-row--tappable"
              @click="openGithub"
            >
              <span class="info-row-label">源代码</span>
              <div class="info-row-value info-row-value--link">
                <span>GitHub</span>
                <IonIcon :icon="chevronForward" class="chevron-icon" />
              </div>
            </button>
            <button
              v-if="displayData.privacyPolicyUrl"
              type="button"
              class="info-row info-row-btn info-row--tappable"
              @click="openPolicyUrl(displayData.privacyPolicyUrl)"
            >
              <span class="info-row-label">隐私政策</span>
              <div class="info-row-value info-row-value--link">
                <span>查看</span>
                <IonIcon :icon="chevronForward" class="chevron-icon" />
              </div>
            </button>
            <button
              v-if="displayData.supportUrl"
              type="button"
              class="info-row info-row-btn info-row--tappable"
              @click="openPolicyUrl(displayData.supportUrl)"
            >
              <span class="info-row-label">应用支持</span>
              <div class="info-row-value info-row-value--link">
                <span>联系</span>
                <IonIcon :icon="chevronForward" class="chevron-icon" />
              </div>
            </button>
          </div>
        </div>

        <!-- 来自同一开发者的其他应用 -->
        <div v-if="otherApps.length" class="section">
          <div class="section-header">
            <h2 class="section-title">
              其他 App
            </h2>
            <button type="button" class="see-all-btn" @click="goDeveloper">
              {{ developerDisplay }}
              <IonIcon :icon="chevronForward" />
            </button>
          </div>
          <div class="other-apps-row">
            <button
              v-for="a in otherApps"
              :key="a.id"
              type="button"
              class="other-app-card"
              @click="goApp(a)"
            >
              <AppIconBox
                :icon="a.logo"
                :emoji="a.emoji"
                :color="a.themeColor"
                size="md"
              />
              <span class="other-app-name">{{ a.name }}</span>
              <span class="other-app-cat">{{ a.category || '应用' }}</span>
            </button>
          </div>
        </div>

        <AppReportSheet
          :is-open="appReportOpen"
          target-type="app"
          :target-id="reviewAppKey"
          :app-key="reviewAppKey"
          @close="appReportOpen = false"
        />
      </div>

      <div v-else class="app-detail-container">
        <div class="detail-empty-state">
          <div class="detail-empty-icon">
            {{ appData?.emoji || '📱' }}
          </div>
          <h1 class="detail-empty-title">
            {{ error || '应用详情暂不可用' }}
          </h1>
          <p class="detail-empty-desc">
            当前应用数据没有成功加载，请稍后重试，或返回工坊浏览其他应用。
          </p>
          <div class="detail-empty-actions">
            <IonButton size="small" @click="refresh()">
              重新加载
            </IonButton>
            <IonButton size="small" fill="clear" @click="router.push('/tabs/apps')">
              返回工坊
            </IonButton>
          </div>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.app-detail-content {
  --background: var(--ion-background-color);
}

.app-detail-container {
  max-width: 980px;
  margin: 0 auto;
  padding-bottom: 40px;
}

.detail-empty-state {
  min-height: calc(100vh - 120px);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 40px 24px;
  text-align: center;
}

.detail-empty-icon {
  width: 76px;
  height: 76px;
  border-radius: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--ylf-fill-secondary);
  font-size: 36px;
}

.detail-empty-title {
  margin: 8px 0 0;
  font-size: 22px;
  font-weight: 700;
}

.detail-empty-desc {
  max-width: 320px;
  margin: 0;
  color: var(--ion-color-medium);
  font-size: 15px;
  line-height: 1.5;
}

.detail-empty-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
}

/* 应用头部 */
.app-header {
  background: var(--ion-item-background);
  padding: 20px;
  margin-bottom: 8px;
}

.app-header-content {
  display: flex;
  gap: 16px;
  align-items: center;
  margin-bottom: 16px;
}

/* 骨架屏占位（实际图标由 AppIconBox size="xl" 渲染，尺寸保持一致） */
.app-icon-large {
  width: 120px;
  height: 120px;
  border-radius: 27px;
  flex-shrink: 0;
}

.app-header-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.app-name-row {
  display: flex;
  align-items: center;
  gap: 5px;
  min-width: 0;
}

.app-name {
  font-size: 22px;
  font-weight: 700;
  line-height: 1.22;
  margin: 0;
  min-width: 0;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.app-subtitle {
  font-size: 14px;
  color: var(--ion-color-medium);
  margin: 0;
  line-height: 1.3;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

/* 开发者链接（App Store 蓝色可点击售卖方） */
.app-developer-link {
  appearance: none;
  -webkit-appearance: none;
  background: none;
  border: 0;
  padding: 3px 0 0;
  margin: 0;
  display: inline-flex;
  align-items: center;
  gap: 1px;
  max-width: 100%;
  color: var(--ion-color-primary);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
}

.app-developer-link .truncate {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-developer-link:active {
  opacity: 0.6;
}

.developer-link-chevron {
  font-size: 13px;
  flex-shrink: 0;
}

.app-developer-static {
  margin: 3px 0 0;
  font-size: 13px;
  color: var(--ion-color-medium);
}

/* 操作行：紧凑胶囊「打开」+ 分享图标（替代原全宽大按钮） */
/* 获取/打开 按钮列（图标右侧，列表同款 AppInstallButton） */
.app-header-action {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
}

.app-iap-hint {
  font-size: 11px;
  line-height: 1;
  color: var(--ion-color-medium);
  white-space: nowrap;
}

.app-info-bar {
  display: flex;
  align-items: center;
  justify-content: space-around;
  padding-top: 16px;
  border-top: 0.5px solid var(--ylf-separator);
}

.info-item {
  text-align: center;
  flex: 1;
  min-width: 0;
}

/* 信息栏中作为按钮的单元（开发者）需要重置原生按钮样式 */
.info-item-btn {
  appearance: none;
  -webkit-appearance: none;
  background: none;
  border: 0;
  padding: 0;
  font: inherit;
  cursor: default;
}

.info-item--tappable {
  cursor: pointer;
}

.info-item--tappable .info-value {
  color: var(--ion-color-primary);
}

.info-item--tappable:active {
  opacity: 0.6;
}

.info-value {
  font-size: 15px;
  font-weight: 600;
  color: var(--ion-color-medium);
  margin-bottom: 2px;
}

.info-value-clip {
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.info-label {
  font-size: 11px;
  color: var(--ion-color-medium);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.info-divider {
  width: 0.5px;
  height: 32px;
  flex-shrink: 0;
  background: var(--ylf-separator);
}

/* 通用区块样式 */
.section {
  background: var(--ion-item-background);
  padding: 20px;
  margin-bottom: 8px;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}

.section-title {
  font-size: 20px;
  font-weight: 700;
  margin: 0;
}

.version-history-btn,
.see-all-btn,
.more-btn {
  background: none;
  border: none;
  color: var(--ion-color-primary);
  font-size: 15px;
  font-weight: 400;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 0;
}

.section-content {
  color: var(--ion-text-color);
}

.version-info {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  color: var(--ion-color-medium);
  margin-bottom: 12px;
}

.whats-new-text {
  font-size: 15px;
  line-height: 1.5;
  white-space: pre-line;
  margin: 0;
}

/* 截图 */
.screenshots-container {
  display: flex;
  gap: 12px;
  overflow-x: auto;
  padding: 8px 0;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.screenshots-container::-webkit-scrollbar {
  display: none;
}

/* 真实截图（自适应宽高比，统一卡片高度） */
.screenshot-shot {
  height: 460px;
  flex-shrink: 0;
  border-radius: 18px;
  overflow: hidden;
  background: var(--ylf-fill-secondary);
  box-shadow:
    0 12px 28px rgba(0, 0, 0, 0.14),
    inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
}

.dark .screenshot-shot {
  box-shadow:
    0 12px 28px rgba(0, 0, 0, 0.4),
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.08);
}

.screenshot-img {
  display: block;
  height: 100%;
  width: auto;
  max-width: 82vw;
  object-fit: cover;
}

.screenshot-item {
  width: 230px;
  height: 498px;
  border-radius: 16px;
  flex-shrink: 0;
  box-shadow:
    0 18px 34px rgba(0, 0, 0, 0.16),
    inset 0 1px 0 rgba(255, 255, 255, 0.26);
  display: flex;
  color: #fff;
  position: relative;
  overflow: hidden;
  background:
    radial-gradient(circle at 28% 18%, rgba(255, 255, 255, 0.42), transparent 28%),
    linear-gradient(
      145deg,
      color-mix(in srgb, var(--preview-color) 82%, white 18%),
      color-mix(in srgb, var(--preview-color) 76%, black 24%)
    );
}

.screenshot-item::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  box-shadow:
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.28),
    inset 0 -80px 110px rgba(0, 0, 0, 0.16);
  pointer-events: none;
}

.preview-panel {
  flex-direction: column;
  justify-content: space-between;
  padding: 24px;
}

.preview-panel-orb {
  width: 82px;
  height: 82px;
  border-radius: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.18);
  border: 0.5px solid rgba(255, 255, 255, 0.28);
  box-shadow:
    0 12px 24px rgba(0, 0, 0, 0.18),
    inset 0 1px 0 rgba(255, 255, 255, 0.32);
  backdrop-filter: blur(18px) saturate(170%);
  -webkit-backdrop-filter: blur(18px) saturate(170%);
  font-size: 42px;
}

.preview-panel-logo {
  width: 100%;
  height: 100%;
  border-radius: inherit;
  object-fit: cover;
}

.preview-panel-content {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.preview-panel-eyebrow {
  font-size: 12px;
  font-weight: 700;
  line-height: 1;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  opacity: 0.76;
}

.preview-panel-title {
  font-size: 26px;
  font-weight: 800;
  line-height: 1.08;
}

.preview-panel-body {
  margin: 0;
  font-size: 14px;
  line-height: 1.45;
  opacity: 0.86;
  overflow-wrap: anywhere;
}

.description-text {
  font-size: 15px;
  line-height: 1.5;
  margin: 0 0 12px 0;
  white-space: pre-line;
}

/* 评分与评论 */
.rating-summary {
  display: flex;
  gap: 24px;
  padding: 16px 0;
  border-bottom: 0.5px solid var(--ylf-separator);
  margin-bottom: 16px;
}

.rating-score {
  text-align: center;
  min-width: 100px;
}

.score-number {
  font-size: 56px;
  font-weight: 700;
  line-height: 1;
  margin-bottom: 4px;
}

.score-label {
  font-size: 13px;
  color: var(--ion-color-medium);
  margin-bottom: 8px;
}

.rating-stars-small {
  display: flex;
  justify-content: center;
  gap: 2px;
  margin-bottom: 4px;
}

.star-icon-small {
  font-size: 10px;
  color: var(--ylf-color-yellow);
}

.rating-count-small {
  font-size: 11px;
  color: var(--ion-color-medium);
}

.rating-bars {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 6px;
  justify-content: center;
}

.rating-bar-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.bar-star {
  font-size: 10px;
  color: var(--ion-color-medium);
  flex-shrink: 0;
}

.bar-container {
  flex: 1;
  height: 6px;
  background: var(--ylf-fill-tertiary);
  border-radius: 3px;
  overflow: hidden;
}

.bar-fill {
  height: 100%;
  background: var(--ion-color-medium);
  border-radius: 3px;
}

/* 评论列表 */
.reviews-list {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.review-item {
  padding-bottom: 20px;
  border-bottom: 0.5px solid var(--ylf-separator);
}

.review-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.review-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 8px;
}

.reviewer-info {
  display: flex;
  gap: 12px;
  align-items: center;
}

.reviewer-avatar {
  width: 40px;
  height: 40px;
  border-radius: 20px;
  background: var(--ion-color-medium);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 600;
}

.reviewer-details {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.reviewer-name {
  font-size: 15px;
  font-weight: 600;
}

.review-stars {
  display: flex;
  gap: 2px;
}

.review-star {
  font-size: 10px;
  color: var(--ylf-color-yellow);
}

.review-date {
  font-size: 13px;
  color: var(--ion-color-medium);
}

.review-content {
  margin-left: 52px;
}

.review-title {
  font-size: 15px;
  font-weight: 600;
  margin: 0 0 4px 0;
}

.review-text {
  font-size: 15px;
  line-height: 1.5;
  color: var(--ion-color-medium);
  margin: 0;
}

/* 信息列表 */
.info-list {
  display: flex;
  flex-direction: column;
}

.info-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 0;
  border-bottom: 0.5px solid var(--ylf-separator);
}

.info-row:last-child {
  border-bottom: none;
}

/* 可点击信息行（开发者 / 网站 / 源代码）需要重置原生按钮样式 */
.info-row-btn {
  appearance: none;
  -webkit-appearance: none;
  width: 100%;
  background: none;
  border: 0;
  border-bottom: 0.5px solid var(--ylf-separator);
  font: inherit;
  text-align: left;
  color: inherit;
  cursor: default;
}

.info-row--tappable {
  cursor: pointer;
}

.info-row--tappable:active {
  opacity: 0.55;
}

.info-row-label {
  font-size: 15px;
  color: var(--ion-color-medium);
  flex-shrink: 0;
}

.info-row-value {
  font-size: 15px;
  text-align: right;
  display: flex;
  align-items: center;
  gap: 4px;
  min-width: 0;
  margin-left: 16px;
}

.info-row-value--link {
  color: var(--ion-color-primary);
}

.info-row-value .truncate {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.info-row-value-multi {
  text-align: right;
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 15px;
}

.info-sub {
  font-size: 13px;
  color: var(--ion-color-medium);
}

.chevron-icon {
  font-size: 14px;
  color: var(--ylf-label-tertiary);
}

/* ==================== 开发者的其他 App ==================== */
.other-apps-row {
  display: flex;
  gap: 18px;
  overflow-x: auto;
  padding: 4px 0 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.other-apps-row::-webkit-scrollbar {
  display: none;
}

.other-app-card {
  appearance: none;
  -webkit-appearance: none;
  flex-shrink: 0;
  width: 64px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 0;
  border: 0;
  background: none;
  cursor: pointer;
}

.other-app-card:active {
  opacity: 0.6;
}

.other-app-name {
  max-width: 64px;
  font-size: 12px;
  font-weight: 500;
  line-height: 1.25;
  color: var(--ion-text-color);
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.other-app-cat {
  max-width: 64px;
  font-size: 11px;
  line-height: 1.2;
  color: var(--ion-color-medium);
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* ==================== 骨架屏 ==================== */
.skeleton-pulse {
  background: var(--ylf-fill-tertiary);
  border-radius: 8px;
  animation: pulse 1.5s ease-in-out infinite;
}

.skeleton-line {
  border-radius: 4px;
  margin-bottom: 8px;
}

.skeleton-button {
  flex-shrink: 0;
  width: 72px;
  height: 28px;
  border-radius: 100px;
}

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.4;
  }
}
</style>
