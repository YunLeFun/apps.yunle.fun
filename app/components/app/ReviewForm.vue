<script setup lang="ts">
import type { ReviewRecord } from '~/types/review'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonModal,
  IonTextarea,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { star, starOutline } from 'ionicons/icons'

const props = defineProps<{
  isOpen: boolean
  review?: ReviewRecord | null
  submitting?: boolean
}>()

const emit = defineEmits<{
  close: []
  submit: [input: { rating: number, title?: string, content: string }]
}>()

const rating = ref(5)
const title = ref('')
const content = ref('')

watch(() => props.isOpen, (open) => {
  if (!open)
    return
  rating.value = props.review?.rating || 5
  title.value = props.review?.title || ''
  content.value = props.review?.content || ''
})

const canSubmit = computed(() => rating.value >= 1 && rating.value <= 5 && content.value.trim().length > 0 && content.value.length <= 1000)

function submit() {
  if (!canSubmit.value)
    return
  emit('submit', {
    rating: rating.value,
    title: title.value.trim() || undefined,
    content: content.value.trim(),
  })
}

function renderStar(index: number) {
  return index <= rating.value ? star : starOutline
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
          <IonButton :disabled="!canSubmit || submitting" @click="submit">
            发布
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>
    <IonContent class="ion-padding">
      <div class="review-form">
        <div class="rating-picker" aria-label="评分">
          <button
            v-for="i in 5"
            :key="i"
            type="button"
            class="rating-star-button"
            :aria-label="`${i} 星`"
            @click="rating = i"
          >
            <IonIcon :icon="renderStar(i)" />
          </button>
        </div>

        <IonInput
          v-model="title"
          label="标题"
          label-placement="stacked"
          :maxlength="100"
          placeholder="一句话总结体验"
          :disabled="submitting"
        />
        <IonTextarea
          v-model="content"
          label="评论"
          label-placement="stacked"
          auto-grow
          :counter="true"
          :maxlength="1000"
          placeholder="说说你的使用体验"
          :disabled="submitting"
        />
      </div>
    </IonContent>
  </IonModal>
</template>

<style scoped>
.review-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.rating-picker {
  display: flex;
  justify-content: center;
  gap: 6px;
  padding: 8px 0;
}

.rating-star-button {
  width: 38px;
  height: 38px;
  border: 0;
  padding: 0;
  border-radius: 19px;
  background: transparent;
  color: var(--ylf-color-yellow);
  font-size: 28px;
}
</style>
