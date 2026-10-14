<script setup lang="ts">
import type { ReportReason } from '~/types/review'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonModal,
  IonTextarea,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { REPORT_REASON_LABELS } from '~/types/review'

const props = defineProps<{
  isOpen: boolean
  targetType: 'app' | 'review'
  targetId: string
  appKey?: string
}>()

const emit = defineEmits<{
  close: []
  submitted: []
}>()

const reasons = Object.entries(REPORT_REASON_LABELS) as Array<[ReportReason, string]>
const reason = ref<ReportReason>('illegal')
const detail = ref('')
const { submitReport, submitting } = useAppReviews(() => props.appKey, { autoLoad: false })

watch(() => props.isOpen, (open) => {
  if (open) {
    reason.value = 'illegal'
    detail.value = ''
  }
})

async function submit() {
  const ok = await submitReport({
    targetType: props.targetType,
    targetId: props.targetId,
    appKey: props.appKey,
    reason: reason.value,
    detail: detail.value.trim() || undefined,
  })
  if (ok) {
    emit('submitted')
    emit('close')
  }
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
        <IonTitle>举报</IonTitle>
        <IonButtons slot="end">
          <IonButton :disabled="submitting || !targetId" @click="submit">
            提交
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>
    <IonContent class="ion-padding">
      <div class="report-reasons">
        <button
          v-for="[value, label] in reasons"
          :key="value"
          type="button"
          class="report-reason"
          :class="{ active: reason === value }"
          @click="reason = value"
        >
          {{ label }}
        </button>
      </div>
      <IonTextarea
        v-model="detail"
        label="补充说明"
        label-placement="stacked"
        auto-grow
        :counter="true"
        :maxlength="500"
        placeholder="可选，帮助我们更快处理"
        :disabled="submitting"
      />
    </IonContent>
  </IonModal>
</template>

<style scoped>
.report-reasons {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  margin-bottom: 18px;
}

.report-reason {
  min-height: 40px;
  border: 0.5px solid var(--ylf-separator);
  border-radius: 8px;
  background: var(--ion-item-background);
  color: var(--ion-text-color);
  font-size: 15px;
}

.report-reason.active {
  border-color: var(--ion-color-primary);
  color: var(--ion-color-primary);
  background: color-mix(in srgb, var(--ion-color-primary) 10%, transparent);
}
</style>
