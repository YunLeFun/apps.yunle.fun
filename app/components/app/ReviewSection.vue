<script setup lang="ts">
import type { ReviewPublic, ReviewRecord, ReviewSummary } from '~/types/review'
import { Haptics, NotificationType } from '@capacitor/haptics'
import { IonButton, IonIcon, IonSpinner } from '@ionic/vue'
import { chatbubbleEllipsesOutline, star, starOutline } from 'ionicons/icons'

const props = defineProps<{
  appKey: string
  appName?: string
  appIcon?: string
}>()

const emit = defineEmits<{
  summary: [summary: ReviewSummary]
}>()

const {
  summary,
  reviews,
  myReview,
  loading,
  submitting,
  error,
  load,
  submitReview,
  deleteMyReview,
} = useAppReviews(() => props.appKey)

const formOpen = ref(false)
const reportOpen = ref(false)
const reportTarget = ref<ReviewPublic | ReviewRecord | null>(null)
const router = useRouter()
const toast = useToast()
const userStore = useUserStore()

// 评分一律以真实评论为准：无评论时为 0，展示「新」而非运营预设分
const displayAverage = computed(() => summary.value.count > 0 ? summary.value.average : 0)
const hasReviews = computed(() => reviews.value.length > 0)

watch(summary, value => emit('summary', value), { deep: true, immediate: true })

async function handleSubmit(input: { rating: number, title?: string, content: string }) {
  const result = await submitReview(input)
  if (result) {
    Haptics.notification({
      type: result.status === 'rejected' ? NotificationType.Error : NotificationType.Success,
    }).catch(() => {})
    formOpen.value = false
  }
}

async function openReviewForm() {
  if (!userStore.isLoggedIn) {
    toast.showError('请先登录后评论')
    await router.push('/login')
    return
  }
  formOpen.value = true
}

function openReport(review: ReviewPublic | ReviewRecord) {
  reportTarget.value = review
  reportOpen.value = true
}

function renderStars(rating: number) {
  const fullStars = Math.floor(rating)
  return Array.from({ length: 5 }, (_, index) => index < fullStars ? star : starOutline)
}

function barWidth(starValue: 1 | 2 | 3 | 4 | 5) {
  if (!summary.value.count)
    return '0%'
  return `${Math.round((summary.value.distribution[starValue] / summary.value.count) * 100)}%`
}
</script>

<template>
  <div class="section">
    <div class="section-header">
      <h2 class="section-title">
        评分与评论
      </h2>
      <IonButton size="small" fill="clear" :disabled="submitting" @click="openReviewForm">
        {{ userStore.isLoggedIn ? '写评论' : '登录后评论' }}
      </IonButton>
    </div>

    <div class="rating-summary">
      <div class="rating-score">
        <div class="score-number">
          {{ displayAverage ? displayAverage.toFixed(1) : '新' }}
        </div>
        <div class="score-label">
          满分 5 分
        </div>
        <div class="rating-stars-small">
          <IonIcon
            v-for="(starIcon, idx) in renderStars(displayAverage)"
            :key="idx"
            :icon="starIcon"
            class="star-icon-small"
          />
        </div>
        <div class="rating-count-small">
          {{ summary.count }} 条评论
        </div>
      </div>

      <div class="rating-bars">
        <div v-for="i in [5, 4, 3, 2, 1]" :key="i" class="rating-bar-row">
          <IonIcon :icon="star" class="bar-star" />
          <div class="bar-container">
            <div class="bar-fill" :style="{ width: barWidth(i as 1 | 2 | 3 | 4 | 5) }" />
          </div>
        </div>
      </div>
    </div>

    <div v-if="loading" class="reviews-loading">
      <IonSpinner name="crescent" />
    </div>
    <div v-else-if="error" class="reviews-empty">
      <p>{{ error }}</p>
      <IonButton size="small" fill="clear" @click="load">
        重试
      </IonButton>
    </div>
    <div v-else class="reviews-list">
      <AppReviewItem
        v-if="myReview && myReview.status !== 'published'"
        :review="myReview"
        mine
        @edit="formOpen = true"
        @delete="deleteMyReview"
      />
      <template v-if="hasReviews">
        <AppReviewItem
          v-for="review in reviews"
          :key="review._id"
          :review="review"
          :mine="myReview?.status === 'published' && myReview._id === review._id"
          @edit="formOpen = true"
          @delete="deleteMyReview"
          @report="openReport"
        />
      </template>
      <div v-else class="reviews-empty">
        <IonIcon :icon="chatbubbleEllipsesOutline" />
        <p>成为第一个评论的人</p>
      </div>
    </div>

    <AppReviewForm
      :is-open="formOpen"
      :review="myReview"
      :submitting="submitting"
      :app-name="appName"
      :app-icon="appIcon"
      @close="formOpen = false"
      @submit="handleSubmit"
    />
    <AppReportSheet
      :is-open="reportOpen"
      target-type="review"
      :target-id="reportTarget?._id || ''"
      :app-key="appKey"
      @close="reportOpen = false"
    />
  </div>
</template>

<style scoped>
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

.score-label,
.rating-count-small {
  font-size: 13px;
  color: var(--ion-color-medium);
}

.rating-stars-small {
  display: flex;
  justify-content: center;
  gap: 2px;
  margin: 8px 0 4px;
}

.star-icon-small {
  font-size: 10px;
  color: var(--ylf-color-yellow);
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

.reviews-list {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.reviews-loading,
.reviews-empty {
  min-height: 112px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--ion-color-medium);
  text-align: center;
}

.reviews-empty ion-icon {
  font-size: 28px;
}

.reviews-empty p {
  margin: 0;
}
</style>
