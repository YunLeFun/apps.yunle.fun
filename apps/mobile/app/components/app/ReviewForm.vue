<script setup lang="ts">
import type { ReviewRecord } from '~/types/review'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonItem,
  IonList,
  IonModal,
  IonSpinner,
  IonTextarea,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { star, starOutline } from 'ionicons/icons'

const props = defineProps<{
  isOpen: boolean
  review?: ReviewRecord | null
  submitting?: boolean
  appName?: string
  appIcon?: string
}>()

const emit = defineEmits<{
  close: []
  submit: [input: { rating: number, title?: string, content: string }]
}>()

const RATING_WORDS: Record<number, string> = {
  1: '很差',
  2: '一般',
  3: '还行',
  4: '不错',
  5: '超赞',
}

const rating = ref(5)
const hoverRating = ref(0)
const title = ref('')
const content = ref('')

const displayRating = computed(() => hoverRating.value || rating.value)
const ratingWord = computed(() => RATING_WORDS[displayRating.value] ?? '点击星星评分')

watch(() => props.isOpen, (open) => {
  if (!open)
    return
  rating.value = props.review?.rating || 5
  hoverRating.value = 0
  title.value = props.review?.title || ''
  content.value = props.review?.content || ''
})

const canSubmit = computed(() => rating.value >= 1 && rating.value <= 5 && content.value.trim().length > 0 && content.value.length <= 1000)

function setRating(value: number) {
  rating.value = value
  Haptics.impact({ style: ImpactStyle.Light }).catch(() => {})
}

function submit() {
  if (!canSubmit.value)
    return
  emit('submit', {
    rating: rating.value,
    title: title.value.trim() || undefined,
    content: content.value.trim(),
  })
}
</script>

<template>
  <IonModal :is-open="isOpen" @did-dismiss="emit('close')">
    <IonHeader>
      <IonToolbar>
        <IonButtons slot="start">
          <IonButton @click="emit('close')">
            取消
          </IonButton>
        </IonButtons>
        <IonTitle>{{ review ? '编辑评论' : '写评论' }}</IonTitle>
        <IonButtons slot="end">
          <IonButton :strong="true" :disabled="!canSubmit || submitting" @click="submit">
            <IonSpinner v-if="submitting" name="crescent" />
            <template v-else>
              发布
            </template>
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>
    <IonContent class="ion-padding">
      <div class="review-form">
        <!-- 评价对象 -->
        <div class="review-context">
          <div v-if="appIcon" class="context-icon">
            <img :src="appIcon" alt="">
          </div>
          <div class="context-label">
            {{ review ? '编辑你的评价' : '评价' }}
          </div>
          <div v-if="appName" class="context-name">
            {{ appName }}
          </div>
        </div>

        <!-- 评分 -->
        <div class="rating-card">
          <div class="rating-stars" role="radiogroup" aria-label="评分">
            <button
              v-for="i in 5"
              :key="i"
              type="button"
              class="star-btn"
              :class="{ 'star-btn--on': i <= displayRating }"
              role="radio"
              :aria-checked="rating === i"
              :aria-label="`${i} 星`"
              @click="setRating(i)"
              @pointerenter="hoverRating = i"
              @pointerleave="hoverRating = 0"
            >
              <IonIcon :icon="i <= displayRating ? star : starOutline" />
            </button>
          </div>
          <Transition name="rating-word" mode="out-in">
            <div :key="displayRating" class="rating-word">
              {{ ratingWord }}
            </div>
          </Transition>
        </div>

        <!-- 内容 -->
        <IonList class="review-fields" inset>
          <IonItem>
            <IonInput
              v-model="title"
              label="标题"
              label-placement="stacked"
              :maxlength="100"
              placeholder="一句话总结体验（选填）"
              :disabled="submitting"
            />
          </IonItem>
          <IonItem>
            <IonTextarea
              v-model="content"
              label="评论"
              label-placement="stacked"
              :rows="5"
              auto-grow
              :counter="true"
              :maxlength="1000"
              placeholder="说说你的使用体验，给其他人一些参考～"
              :disabled="submitting"
            />
          </IonItem>
        </IonList>
        <p class="form-hint">
          真实的体验对其他用户很有帮助
        </p>
      </div>
    </IonContent>
  </IonModal>
</template>

<style scoped>
.review-form {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* 评价对象 */
.review-context {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding-top: 12px;
}

.context-icon {
  width: 56px;
  height: 56px;
  border-radius: 14px;
  overflow: hidden;
  background: var(--ylf-fill-tertiary);
  margin-bottom: 2px;
}

.context-icon img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.context-label {
  font-size: 13px;
  color: var(--ylf-label-secondary);
}

.context-name {
  font-size: 17px;
  font-weight: 600;
  color: var(--ylf-label);
  text-align: center;
  overflow-wrap: anywhere;
}

/* 评分卡片 */
.rating-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 20px 16px 18px;
  background: var(--ion-item-background);
  border-radius: 14px;
}

.rating-stars {
  display: flex;
  gap: 6px;
}

.star-btn {
  width: 48px;
  height: 48px;
  padding: 0;
  border: 0;
  background: transparent;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.star-btn ion-icon {
  font-size: 40px;
  color: var(--ylf-label-quaternary);
  transition:
    transform 0.18s cubic-bezier(0.34, 1.56, 0.64, 1),
    color 0.18s ease;
}

.star-btn--on ion-icon {
  color: var(--ylf-color-yellow);
}

.star-btn:active ion-icon {
  transform: scale(0.84);
}

.star-btn:focus-visible {
  outline: 2px solid var(--ion-color-primary);
  outline-offset: 2px;
  border-radius: 12px;
}

.rating-word {
  font-size: 15px;
  font-weight: 600;
  color: var(--ylf-label);
  min-height: 20px;
  line-height: 20px;
}

.rating-word-enter-active,
.rating-word-leave-active {
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
}

.rating-word-enter-from {
  opacity: 0;
  transform: translateY(4px);
}

.rating-word-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}

/* 字段：与评分卡片对齐，去掉 inset 默认外边距 */
.review-fields {
  margin: 0;
  border-radius: 14px;
}

.form-hint {
  margin: 12px 0 0;
  font-size: 13px;
  line-height: 1.4;
  color: var(--ylf-label-secondary);
}

@media (prefers-reduced-motion: reduce) {
  .star-btn ion-icon {
    transition: color 0.18s ease;
  }

  .star-btn:active ion-icon {
    transform: none;
  }

  .rating-word-enter-active,
  .rating-word-leave-active {
    transition: none;
  }
}
</style>
