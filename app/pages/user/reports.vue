<script setup lang="ts">
import type { MyReportItem } from '~/types/review'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { flagOutline } from 'ionicons/icons'
import {
  kBlock,
  kList,
  kListItem,
} from 'konsta/vue'
import { REPORT_REASON_LABELS, REPORT_STATUS_LABELS } from '~/types/review'

const router = useRouter()
const userStore = useUserStore()
const { reports, loading, loaded, load } = useMyReports()

onMounted(() => {
  if (!userStore.isLoggedIn) {
    router.replace('/login')
    return
  }
  load()
})

function reportTitle(report: MyReportItem) {
  return report.appName || report.appKey || report.targetId
}

function reportSubtitle(report: MyReportItem) {
  const type = report.targetType === 'review' ? '评论举报' : '应用举报'
  return `${type} · ${REPORT_REASON_LABELS[report.reason]}`
}

function formatReportTime(ts: number) {
  const diff = Date.now() - ts
  if (diff < 60000)
    return '刚刚'
  if (diff < 3600000)
    return `${Math.floor(diff / 60000)} 分钟前`
  if (diff < 86400000)
    return `${Math.floor(diff / 3600000)} 小时前`
  const date = new Date(ts)
  const m = `${date.getMonth() + 1}`.padStart(2, '0')
  const d = `${date.getDate()}`.padStart(2, '0')
  return `${date.getFullYear()}-${m}-${d}`
}

async function handleRefresh(event: CustomEvent) {
  await load()
  ;(event.target as HTMLIonRefresherElement).complete()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>我的举报</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonRefresher slot="fixed" @ion-refresh="handleRefresh">
        <IonRefresherContent />
      </IonRefresher>

      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            我的举报
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <AppPageLoading
        v-if="loading && reports.length === 0"
        label="正在加载我的举报"
      />

      <k-list v-else-if="reports.length > 0" strong inset>
        <k-list-item
          v-for="report in reports"
          :key="report._id"
          :title="reportTitle(report)"
          :subtitle="reportSubtitle(report)"
          :text="report.detail || undefined"
          :footer="formatReportTime(report.createdAt)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-red">
              <IonIcon :icon="flagOutline" />
            </span>
          </template>
          <template #after>
            <span class="report-status" :class="`report-status--${report.status}`">
              {{ REPORT_STATUS_LABELS[report.status] }}
            </span>
          </template>
        </k-list-item>
      </k-list>

      <k-block v-else-if="loaded" strong inset class="report-empty">
        还没有提交过举报
      </k-block>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.report-empty {
  text-align: center;
  opacity: 0.5;
}

.report-status {
  font-size: 13px;
  font-weight: 600;
}

.report-status--open {
  color: var(--ion-color-warning, #ff9f0a);
}

.report-status--resolved {
  color: var(--ion-color-success, #2dd36f);
}

.report-status--dismissed {
  color: var(--ion-color-medium, #8e8e93);
}
</style>
