<script setup lang="ts">
import type { CoinTransaction } from '@yunlefun/types'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { COIN_TX_TYPE_NAMES, formatCoin, PLAN_NAMES } from '@yunlefun/types'
import {
  diamondOutline,
  ribbonOutline,
  walletOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kButton,
  kList,
  kListItem,
} from 'konsta/vue'

/** www 充值 / 开通会员页（App 端跳转过去完成支付） */
const WWW_WALLET_URL = 'https://www.yunle.fun/wallet'
const WWW_PRICING_URL = 'https://www.yunle.fun/pricing'

const userStore = useUserStore()
const router = useRouter()
const { account, balance, membership, isMember, loading, refresh, listTransactions } = useCoin()

const transactions = ref<CoinTransaction[]>([])
const txLoading = ref(false)

async function loadTransactions() {
  if (!userStore.isLoggedIn)
    return
  txLoading.value = true
  try {
    const { items } = await listTransactions({ limit: 20 })
    transactions.value = items
  }
  finally {
    txLoading.value = false
  }
}

onMounted(async () => {
  if (!userStore.isLoggedIn) {
    router.replace('/login')
    return
  }
  await refresh()
  await loadTransactions()
})

async function handleRefresh(event: CustomEvent) {
  await Promise.all([refresh(), loadTransactions()])
  ;(event.target as HTMLIonRefresherElement).complete()
}

function goRecharge() {
  openInAppBrowser(WWW_WALLET_URL)
}

function goMembership() {
  openInAppBrowser(WWW_PRICING_URL)
}

/** 会员到期日期展示 */
const memberExpireText = computed(() => {
  const expireAt = membership.value?.expireAt
  if (!expireAt)
    return ''
  const d = new Date(expireAt)
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} 到期`
})

function formatTxTime(ts: number): string {
  const d = new Date(ts)
  const pad = (n: number) => n.toString().padStart(2, '0')
  return `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>钱包</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonRefresher slot="fixed" @ion-refresh="handleRefresh">
        <IonRefresherContent />
      </IonRefresher>

      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            钱包
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 云币余额卡片 -->
      <k-block strong inset class="balance-card">
        <div class="balance-label">
          <IonIcon :icon="diamondOutline" />
          <span>云币余额</span>
        </div>
        <div class="balance-value">
          <IonSpinner v-if="loading && !account" name="crescent" />
          <template v-else>
            {{ balance }}
          </template>
        </div>
        <k-button rounded class="recharge-btn" @click="goRecharge">
          充值云币
        </k-button>
      </k-block>

      <!-- 会员状态 -->
      <k-block-title>会员</k-block-title>
      <k-list strong inset>
        <k-list-item
          :title="isMember ? (membership?.level ? PLAN_NAMES[membership.level] : '云乐坊会员') : '开通会员'"
          :footer="isMember ? memberExpireText : '解锁更多权益'"
          link
          @click="goMembership"
        >
          <template #media>
            <span class="ios-icon-box" :class="isMember ? 'ios-icon-orange' : 'ios-icon-gray'">
              <IonIcon :icon="ribbonOutline" />
            </span>
          </template>
          <template #after>
            <span v-if="isMember" class="member-badge">有效</span>
            <span v-else class="text-sm opacity-50">去开通</span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 云币流水 -->
      <k-block-title>云币流水</k-block-title>
      <div v-if="txLoading && transactions.length === 0" class="tx-loading">
        <IonSpinner name="crescent" />
      </div>
      <k-list v-else-if="transactions.length > 0" strong inset>
        <k-list-item
          v-for="tx in transactions"
          :key="tx._id"
          :title="COIN_TX_TYPE_NAMES[tx.type]"
          :footer="formatTxTime(tx.createdAt)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="walletOutline" />
            </span>
          </template>
          <template #after>
            <span :class="tx.amount >= 0 ? 'tx-in' : 'tx-out'">
              {{ tx.amount >= 0 ? '+' : '' }}{{ formatCoin(tx.amount) }}
            </span>
          </template>
        </k-list-item>
      </k-list>
      <k-block v-else strong inset class="text-center opacity-50">
        暂无流水记录
      </k-block>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.balance-card {
  text-align: center;
  padding-top: 24px !important;
  padding-bottom: 24px !important;
}

.balance-label {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  font-size: 14px;
  color: var(--ion-color-medium);
}

.balance-value {
  font-size: 44px;
  font-weight: 700;
  line-height: 1.2;
  margin: 8px 0 16px;
  color: var(--ion-text-color);
}

.recharge-btn {
  max-width: 200px;
  margin: 0 auto;
}

.member-badge {
  font-size: 13px;
  font-weight: 600;
  color: var(--ion-color-success, #2dd36f);
}

.tx-in {
  color: var(--ion-color-success, #2dd36f);
  font-weight: 600;
}

.tx-out {
  color: var(--ion-color-medium);
  font-weight: 600;
}

.tx-loading {
  display: flex;
  justify-content: center;
  padding: 24px;
}
</style>
