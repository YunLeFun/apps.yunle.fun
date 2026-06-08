<script setup lang="ts">
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
import { chevronForward, ellipsisHorizontal, share, star, starOutline } from 'ionicons/icons'
import { YLF_CONTACT } from '~/constants/links'

const route = useRoute()
const router = useRouter()
const appId = computed(() => (route.params as any).id as string)

// 使用 useAppDetail composable 获取应用数据
const { appData, loading, error } = useAppDetail(appId)

// 加载完成后，如果应用不存在则跳转
watch([loading, error], ([isLoading, err]) => {
  if (!isLoading && err && !appData.value) {
    router.push('/tabs/apps')
  }
})

// 扩展展示数据
const displayData = computed(() => {
  if (!appData.value)
    return null

  return {
    ...appData.value,
    screenshots: [
      { id: 1, color: appData.value.themeColor, title: '主界面' },
      { id: 2, color: appData.value.themeColor, title: '功能展示' },
      { id: 3, color: appData.value.themeColor, title: '详细信息' },
    ],
    reviews: [
      {
        id: 1,
        user: '云游君',
        rating: 5,
        title: '非常好用的应用',
        content: '界面简洁美观，功能强大。强烈推荐！',
        date: '2天前',
      },
    ],
  }
})

function renderStars(rating: number = 0) {
  const stars = []
  const fullStars = Math.floor(rating)
  for (let i = 0; i < 5; i++) {
    stars.push(i < fullStars ? star : starOutline)
  }
  return stars
}

// 打开应用
function openApp() {
  if (!displayData.value?.websiteUrl)
    return
  if (displayData.value.websiteUrl.startsWith('http')) {
    openInAppBrowser(displayData.value.websiteUrl)
  }
  else {
    router.push(displayData.value.websiteUrl)
  }
}

// 分享应用
const { shareApp: shareAppAction } = useAppActions()
async function shareApp() {
  if (!appData.value)
    return
  await shareAppAction(appData.value)
}

/**
 * 应用详情更多操作菜单（举报 / 复制链接）
 *
 * App Store 审核指南 1.2 要求 UGC 内容必须提供举报入口
 * 当前简化为 mailto 链接，后续 M2 阶段可接 CloudBase reports 集合
 */
async function openMoreMenu() {
  const app = appData.value
  if (!app)
    return
  const subject = encodeURIComponent(`举报应用：${app.name}（${app.slug || app.id}）`)
  const body = encodeURIComponent(
    `应用名称：${app.name}\n应用 ID：${app.id}\n应用 slug：${app.slug || ''}\n网址：${app.websiteUrl || ''}\n\n举报原因（请说明）：\n`,
  )
  const reportMailto = `mailto:${YLF_CONTACT.support.email}?subject=${subject}&body=${body}`

  const sheet = await actionSheetController.create({
    header: app.name,
    buttons: [
      {
        text: '举报此应用',
        role: 'destructive',
        handler: () => {
          window.location.href = reportMailto
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
              <div class="skeleton-line skeleton-pulse" style="width: 60%; height: 22px;" />
              <div class="skeleton-line skeleton-pulse" style="width: 40%; height: 15px;" />
              <div class="skeleton-line skeleton-pulse" style="width: 50%; height: 14px;" />
            </div>
          </div>
          <div class="skeleton-button skeleton-pulse" />
        </div>
      </div>

      <!-- 应用详情 -->
      <div v-else-if="displayData" class="app-detail-container">
        <!-- 应用头部信息 -->
        <div class="app-header">
          <div class="app-header-content">
            <div
              class="app-icon-large"
              :style="{ backgroundColor: displayData.themeColor }"
            >
              {{ displayData.emoji || displayData.logo }}
            </div>

            <div class="app-header-info">
              <h1 class="app-name">
                {{ displayData.name }}
              </h1>
              <p class="app-category">
                {{ displayData.category || '应用' }}
              </p>

              <!-- 评分信息 -->
              <div v-if="displayData.rating" class="app-rating-row">
                <div class="rating-stars">
                  <span class="rating-number">{{ displayData.rating }}</span>
                  <IonIcon
                    v-for="(starIcon, idx) in renderStars(displayData.rating)"
                    :key="idx"
                    :icon="starIcon"
                    class="star-icon"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- 获取/打开按钮 -->
          <IonButton expand="block" class="get-button-large" @click="openApp">
            打开应用
          </IonButton>

          <!-- 应用信息栏 -->
          <div class="app-info-bar">
            <div v-if="displayData.rating" class="info-item">
              <div class="info-value">
                {{ displayData.rating }}
              </div>
              <div class="info-label">
                评分
              </div>
            </div>
            <div v-if="displayData.rating && (displayData.age || displayData.downloads)" class="info-divider" />
            <div v-if="displayData.age" class="info-item">
              <div class="info-value">
                {{ displayData.age }}
              </div>
              <div class="info-label">
                年龄
              </div>
            </div>
            <div v-if="displayData.age && displayData.downloads" class="info-divider" />
            <div v-if="displayData.downloads" class="info-item">
              <div class="info-value">
                {{ displayData.downloads }}
              </div>
              <div class="info-label">
                下载量
              </div>
            </div>
            <div v-if="displayData.downloads || displayData.age || displayData.rating" class="info-divider" />
            <div class="info-item">
              <div class="info-value">
                {{ displayData.developer }}
              </div>
              <div class="info-label">
                开发者
              </div>
            </div>
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
            <div
              v-for="screenshot in displayData.screenshots"
              :key="screenshot.id"
              class="screenshot-item"
              :style="{ backgroundColor: screenshot.color }"
            >
              <div class="screenshot-placeholder">
                {{ screenshot.title }}
              </div>
            </div>
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

        <!-- 评分与评论 -->
        <div v-if="displayData.rating" class="section">
          <div class="section-header">
            <h2 class="section-title">
              评分与评论
            </h2>
            <button class="see-all-btn">
              查看全部
              <IonIcon :icon="chevronForward" />
            </button>
          </div>

          <div class="rating-summary">
            <div class="rating-score">
              <div class="score-number">
                {{ displayData.rating }}
              </div>
              <div class="score-label">
                满分 5 分
              </div>
              <div class="rating-stars-small">
                <IonIcon
                  v-for="(starIcon, idx) in renderStars(displayData.rating)"
                  :key="idx"
                  :icon="starIcon"
                  class="star-icon-small"
                />
              </div>
            </div>

            <div class="rating-bars">
              <div v-for="i in 5" :key="i" class="rating-bar-row">
                <IonIcon :icon="star" class="bar-star" />
                <div class="bar-container">
                  <div class="bar-fill" :style="{ width: `${(6 - i) * 18}%` }" />
                </div>
              </div>
            </div>
          </div>

          <!-- 评论列表 -->
          <div class="reviews-list">
            <div v-for="review in displayData.reviews" :key="review.id" class="review-item">
              <div class="review-header">
                <div class="reviewer-info">
                  <div class="reviewer-avatar">
                    {{ review.user.charAt(0) }}
                  </div>
                  <div class="reviewer-details">
                    <div class="reviewer-name">
                      {{ review.user }}
                    </div>
                    <div class="review-stars">
                      <IonIcon
                        v-for="(starIcon, idx) in renderStars(review.rating)"
                        :key="idx"
                        :icon="starIcon"
                        class="review-star"
                      />
                    </div>
                  </div>
                </div>
                <div class="review-date">
                  {{ review.date }}
                </div>
              </div>
              <div class="review-content">
                <h4 class="review-title">
                  {{ review.title }}
                </h4>
                <p class="review-text">
                  {{ review.content }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- 信息 -->
        <div class="section">
          <h2 class="section-title">
            信息
          </h2>
          <div class="info-list">
            <div class="info-row">
              <span class="info-row-label">开发者</span>
              <div class="info-row-value">
                <span>{{ displayData.developer }}</span>
                <IonIcon :icon="chevronForward" class="chevron-icon" />
              </div>
            </div>
            <div v-if="displayData.size" class="info-row">
              <span class="info-row-label">大小</span>
              <span class="info-row-value">{{ displayData.size }}</span>
            </div>
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
              <span class="info-row-value">免费</span>
            </div>
            <div v-if="displayData.githubRepo" class="info-row">
              <span class="info-row-label">源代码</span>
              <div class="info-row-value">
                <span>GitHub</span>
                <IonIcon :icon="chevronForward" class="chevron-icon" />
              </div>
            </div>
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

/* 应用头部 */
.app-header {
  background: var(--ion-item-background);
  padding: 20px;
  margin-bottom: 8px;
}

.app-header-content {
  display: flex;
  gap: 16px;
  margin-bottom: 16px;
}

.app-icon-large {
  width: 120px;
  height: 120px;
  border-radius: 27px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 64px;
  flex-shrink: 0;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  position: relative;
}

.app-icon-large::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 27px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.1);
}

.app-header-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.app-name {
  font-size: 22px;
  font-weight: 700;
  line-height: 1.2;
  margin: 0;
}

.app-category {
  font-size: 15px;
  color: var(--ion-color-medium);
  margin: 0;
}

.app-rating-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
}

.rating-stars {
  display: flex;
  align-items: center;
  gap: 4px;
}

.rating-number {
  font-size: 15px;
  font-weight: 600;
  color: var(--ion-color-medium);
}

.star-icon {
  font-size: 12px;
  color: var(--ylf-color-yellow);
}

.rating-count {
  font-size: 13px;
  color: var(--ion-color-medium);
}

.get-button-large {
  --border-radius: 14px;
  --padding-top: 10px;
  --padding-bottom: 10px;
  font-size: 17px;
  font-weight: 600;
  margin-bottom: 16px;
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
}

.info-value {
  font-size: 15px;
  font-weight: 600;
  color: var(--ion-color-medium);
  margin-bottom: 2px;
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

.screenshot-item {
  width: 230px;
  height: 498px;
  border-radius: 16px;
  flex-shrink: 0;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 18px;
  font-weight: 600;
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

.info-row-label {
  font-size: 15px;
  color: var(--ion-color-medium);
}

.info-row-value {
  font-size: 15px;
  text-align: right;
  display: flex;
  align-items: center;
  gap: 4px;
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
  height: 44px;
  border-radius: 14px;
  margin-bottom: 16px;
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
