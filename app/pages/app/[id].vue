<script setup lang="ts">
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonToolbar,
} from '@ionic/vue'
import { chevronForward, share, star, starOutline } from 'ionicons/icons'
import { getAppById } from '~/constants/apps'

const route = useRoute()
const router = useRouter()
const appId = computed(() => (route.params as any).id as string)

// 获取应用数据
const appInfo = computed(() => getAppById(appId.value))

// 监听应用信息，如果不存在则跳转
watch(appInfo, (info) => {
  if (!info) {
    router.push('/tabs/apps')
  }
}, { immediate: true })

// 扩展应用数据（添加详情页需要的额外字段）
const appData = computed(() => {
  if (!appInfo.value) {
    return null
  }

  return {
    ...appInfo.value,
    ratingCount: '1.2万',
    developer: 'YunYouJun',
    price: '免费',
    inAppPurchases: false,
    whatsNew: '• 优化用户体验\n• 修复已知问题\n• 提升应用性能',
    features: [
      '简洁美观的界面',
      '流畅的交互体验',
      '强大的功能',
    ],
    screenshots: [
      { id: 1, color: appInfo.value.color, title: '主界面' },
      { id: 2, color: appInfo.value.color, title: '功能展示' },
      { id: 3, color: appInfo.value.color, title: '详细信息' },
    ],
    version: '1.0.0',
    updateDate: '1周前',
    languages: ['简体中文', '英语'],
    compatibility: 'iPhone、iPad、iPod touch',
    minOS: '需要 iOS 14.0 或更高版本',
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
  if (appData.value?.url) {
    window.open(appData.value.url, '_blank')
  }
}

// 分享应用
function shareApp() {
  // TODO: 实现分享功能
  // console.log('分享应用:', appData.value?.name)
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
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="app-detail-content">
      <div v-if="appData" class="app-detail-container">
        <!-- 应用头部信息 -->
        <div class="app-header">
          <div class="app-header-content">
            <div
              class="app-icon-large"
              :style="{ backgroundColor: appData.color }"
            >
              {{ appData.emoji || appData.icon }}
            </div>

            <div class="app-header-info">
              <h1 class="app-name">
                {{ appData.name }}
              </h1>
              <p class="app-category">
                {{ appData.category }}
              </p>

              <!-- 评分信息 -->
              <div v-if="appData.rating" class="app-rating-row">
                <div class="rating-stars">
                  <span class="rating-number">{{ appData.rating }}</span>
                  <IonIcon
                    v-for="(starIcon, idx) in renderStars(appData.rating)"
                    :key="idx"
                    :icon="starIcon"
                    class="star-icon"
                  />
                </div>
                <span class="rating-count">{{ appData.ratingCount }} 个评分</span>
              </div>
            </div>
          </div>

          <!-- 获取按钮 -->
          <IonButton expand="block" class="get-button-large" @click="openApp">
            打开应用
          </IonButton>

          <!-- 应用信息栏 -->
          <div class="app-info-bar">
            <div class="info-item">
              <div class="info-value">
                {{ appData.ratingCount }}
              </div>
              <div class="info-label">
                评分
              </div>
            </div>
            <div class="info-divider" />
            <div class="info-item">
              <div class="info-value">
                {{ appData.age }}
              </div>
              <div class="info-label">
                年龄
              </div>
            </div>
            <div class="info-divider" />
            <div class="info-item">
              <div class="info-value">
                {{ appData.downloads }}
              </div>
              <div class="info-label">
                下载量
              </div>
            </div>
            <div class="info-divider" />
            <div class="info-item">
              <div class="info-value">
                {{ appData.developer }}
              </div>
              <div class="info-label">
                开发者
              </div>
            </div>
          </div>
        </div>

        <!-- 新功能 -->
        <div class="section">
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
              <span class="version-number">版本 {{ appData.version }}</span>
              <span class="update-date">{{ appData.updateDate }}</span>
            </div>
            <p class="whats-new-text">
              {{ appData.whatsNew }}
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
              v-for="screenshot in appData.screenshots"
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
        <div class="section">
          <div class="section-header">
            <h2 class="section-title">
              简介
            </h2>
          </div>
          <div class="section-content">
            <p class="description-text">
              {{ appData.description }}
            </p>
            <button class="more-btn">
              更多
              <IonIcon :icon="chevronForward" />
            </button>
          </div>
        </div>

        <!-- 评分与评论 -->
        <div class="section">
          <div class="section-header">
            <h2 class="section-title">
              评分与评论
            </h2>
            <button class="see-all-btn">
              查看全部
              <IonIcon :icon="chevronForward" />
            </button>
          </div>

          <div v-if="appData.rating" class="rating-summary">
            <div class="rating-score">
              <div class="score-number">
                {{ appData.rating }}
              </div>
              <div class="score-label">
                满分 5 分
              </div>
              <div class="rating-stars-small">
                <IonIcon
                  v-for="(starIcon, idx) in renderStars(appData.rating)"
                  :key="idx"
                  :icon="starIcon"
                  class="star-icon-small"
                />
              </div>
              <div class="rating-count-small">
                {{ appData.ratingCount }}
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
            <div v-for="review in appData.reviews" :key="review.id" class="review-item">
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
                <span>{{ appData.developer }}</span>
                <IonIcon :icon="chevronForward" class="chevron-icon" />
              </div>
            </div>
            <div class="info-row">
              <span class="info-row-label">大小</span>
              <span class="info-row-value">{{ appData.size }}</span>
            </div>
            <div class="info-row">
              <span class="info-row-label">类别</span>
              <span class="info-row-value">{{ appData.category }}</span>
            </div>
            <div class="info-row">
              <span class="info-row-label">兼容性</span>
              <div class="info-row-value-multi">
                <span>{{ appData.compatibility }}</span>
                <span class="info-sub">{{ appData.minOS }}</span>
              </div>
            </div>
            <div class="info-row">
              <span class="info-row-label">语言</span>
              <div class="info-row-value-multi">
                <span>{{ appData.languages.join('、') }}</span>
              </div>
            </div>
            <div class="info-row">
              <span class="info-row-label">年龄分级</span>
              <span class="info-row-value">{{ appData.age }}</span>
            </div>
            <div class="info-row">
              <span class="info-row-label">价格</span>
              <span class="info-row-value">{{ appData.price }}</span>
            </div>
          </div>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.app-detail-content {
  --background: #f2f2f7;
}

.dark .app-detail-content {
  --background: #000000;
}

.app-detail-container {
  max-width: 980px;
  margin: 0 auto;
  padding-bottom: 40px;
}

/* 应用头部 */
.app-header {
  background: white;
  padding: 20px;
  margin-bottom: 8px;
}

.dark .app-header {
  background: #1c1c1e;
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
  color: #8e8e93;
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
  color: #8e8e93;
}

.star-icon {
  font-size: 12px;
  color: #ffcc00;
}

.rating-count {
  font-size: 13px;
  color: #8e8e93;
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
  border-top: 0.5px solid rgba(60, 60, 67, 0.18);
}

.dark .app-info-bar {
  border-top-color: rgba(84, 84, 88, 0.48);
}

.info-item {
  text-align: center;
  flex: 1;
}

.info-value {
  font-size: 15px;
  font-weight: 600;
  color: #8e8e93;
  margin-bottom: 2px;
}

.info-label {
  font-size: 11px;
  color: #8e8e93;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.info-divider {
  width: 0.5px;
  height: 32px;
  background: rgba(60, 60, 67, 0.18);
}

.dark .info-divider {
  background: rgba(84, 84, 88, 0.48);
}

/* 通用区块样式 */
.section {
  background: white;
  padding: 20px;
  margin-bottom: 8px;
}

.dark .section {
  background: #1c1c1e;
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
  color: #007aff;
  font-size: 15px;
  font-weight: 400;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 0;
}

.section-content {
  color: #000;
}

.dark .section-content {
  color: #fff;
}

.version-info {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  color: #8e8e93;
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
  color: white;
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
  border-bottom: 0.5px solid rgba(60, 60, 67, 0.18);
  margin-bottom: 16px;
}

.dark .rating-summary {
  border-bottom-color: rgba(84, 84, 88, 0.48);
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
  color: #8e8e93;
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
  color: #ffcc00;
}

.rating-count-small {
  font-size: 11px;
  color: #8e8e93;
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
  color: #8e8e93;
  flex-shrink: 0;
}

.bar-container {
  flex: 1;
  height: 6px;
  background: rgba(60, 60, 67, 0.12);
  border-radius: 3px;
  overflow: hidden;
}

.dark .bar-container {
  background: rgba(84, 84, 88, 0.24);
}

.bar-fill {
  height: 100%;
  background: #8e8e93;
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
  border-bottom: 0.5px solid rgba(60, 60, 67, 0.18);
}

.review-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.dark .review-item {
  border-bottom-color: rgba(84, 84, 88, 0.48);
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
  background: #8e8e93;
  color: white;
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
  color: #ffcc00;
}

.review-date {
  font-size: 13px;
  color: #8e8e93;
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
  color: #8e8e93;
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
  border-bottom: 0.5px solid rgba(60, 60, 67, 0.18);
}

.info-row:last-child {
  border-bottom: none;
}

.dark .info-row {
  border-bottom-color: rgba(84, 84, 88, 0.48);
}

.info-row-label {
  font-size: 15px;
  color: #8e8e93;
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
  color: #8e8e93;
}

.chevron-icon {
  font-size: 14px;
  color: #c7c7cc;
}
</style>
