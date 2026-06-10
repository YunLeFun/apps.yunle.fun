<script setup lang="ts">
import type { ReviewPublic, ReviewRecord } from '~/types/review'
import { IonBadge, IonButton, IonIcon } from '@ionic/vue'
import { flagOutline, star, starOutline, trashOutline } from 'ionicons/icons'

const props = defineProps<{
  review: ReviewPublic | ReviewRecord
  mine?: boolean
}>()

const emit = defineEmits<{
  edit: []
  delete: []
  report: [review: ReviewPublic | ReviewRecord]
}>()

const status = computed(() => 'status' in props.review ? props.review.status : 'published')
const statusLabel = computed(() => {
  if (status.value === 'pending')
    return '审核中'
  if (status.value === 'rejected')
    return '未发布'
  return ''
})

function renderStars(rating: number) {
  return Array.from({ length: 5 }, (_, index) => index < rating ? star : starOutline)
}

function avatarText(name: string) {
  return name.trim().charAt(0) || '云'
}

function formatDate(timestamp?: number) {
  if (!timestamp)
    return ''
  const diff = Date.now() - timestamp
  const minute = 60 * 1000
  const hour = 60 * minute
  const day = 24 * hour
  if (diff < hour)
    return `${Math.max(1, Math.floor(diff / minute))} 分钟前`
  if (diff < day)
    return `${Math.floor(diff / hour)} 小时前`
  if (diff < 7 * day)
    return `${Math.floor(diff / day)} 天前`
  return new Date(timestamp).toLocaleDateString('zh-CN')
}
</script>

<template>
  <div class="review-item" :class="{ 'review-item--mine': mine }">
    <div class="review-header">
      <div class="reviewer-info">
        <img v-if="review.authorAvatar" :src="review.authorAvatar" alt="" class="reviewer-avatar-img">
        <div v-else class="reviewer-avatar">
          {{ avatarText(review.authorName) }}
        </div>
        <div class="reviewer-details">
          <div class="reviewer-name-row">
            <span class="reviewer-name">{{ review.authorName }}</span>
            <IonBadge v-if="statusLabel" :color="status === 'rejected' ? 'danger' : 'warning'">
              {{ statusLabel }}
            </IonBadge>
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
        {{ formatDate(review.publishedAt || review.updatedAt || review.createdAt) }}
      </div>
    </div>

    <div class="review-content">
      <h4 v-if="review.title" class="review-title">
        {{ review.title }}
      </h4>
      <p class="review-text">
        {{ review.content }}
      </p>
      <p v-if="'rejectedReason' in review && review.rejectedReason" class="review-rejected">
        {{ review.rejectedReason }}
      </p>
      <div class="review-actions">
        <IonButton v-if="mine" size="small" fill="clear" @click="emit('edit')">
          编辑
        </IonButton>
        <IonButton v-if="mine" size="small" fill="clear" color="danger" @click="emit('delete')">
          <IonIcon slot="start" :icon="trashOutline" />
          删除
        </IonButton>
        <IonButton v-else size="small" fill="clear" color="medium" @click="emit('report', review)">
          <IonIcon slot="start" :icon="flagOutline" />
          举报
        </IonButton>
      </div>
    </div>
  </div>
</template>

<style scoped>
.review-item {
  padding-bottom: 20px;
  border-bottom: 0.5px solid var(--ylf-separator);
}

.review-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.review-item--mine {
  padding: 14px;
  border: 0.5px solid var(--ylf-separator);
  border-radius: 8px;
  background: var(--ylf-fill-quaternary);
}

.review-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  margin-bottom: 8px;
}

.reviewer-info {
  display: flex;
  gap: 12px;
  align-items: center;
  min-width: 0;
}

.reviewer-avatar,
.reviewer-avatar-img {
  width: 40px;
  height: 40px;
  border-radius: 20px;
  flex-shrink: 0;
}

.reviewer-avatar {
  background: var(--ion-color-medium);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 600;
}

.reviewer-avatar-img {
  object-fit: cover;
}

.reviewer-details {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}

.reviewer-name-row {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
}

.reviewer-name {
  font-size: 15px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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
  flex-shrink: 0;
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
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.review-rejected {
  margin: 8px 0 0;
  font-size: 13px;
  color: var(--ion-color-danger);
}

.review-actions {
  display: flex;
  justify-content: flex-end;
  gap: 4px;
  margin-top: 8px;
}

@media (max-width: 520px) {
  .review-content {
    margin-left: 0;
  }
}
</style>
