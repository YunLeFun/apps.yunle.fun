<script setup lang="ts">
import type { CoinPackId, CoinTransaction } from '@yunlefun/types'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonInfiniteScroll,
  IonInfiniteScrollContent,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { COIN_PACKS, COIN_RATE_FEN, COIN_TX_TYPE_NAMES, formatCoin, formatPrice, IAP_COIN_PRODUCTS, PLAN_NAMES } from '@yunlefun/types'
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

const userStore = useUserStore()
const router = useRouter()
const { account, balance, membership, isMember, loading, refresh, reconcileOrders, listTransactions } = useCoin()

const { channel, canPurchase, goRecharge } = usePaymentChannel({
  // 从 www 支付页回到 App：兜底对账 + 刷新余额与流水
  onReturn: () => reconcileAndRefresh(),
})
const iap = useIap()

/** iOS 充值包（App Store 本地化价；商品未就绪时整体隐藏，见审核 3.1.1） */
const iapCoinPacks = computed(() =>
  (Object.keys(COIN_PACKS) as CoinPackId[])
    .map((packId) => {
      const product = iap.findProduct(IAP_COIN_PRODUCTS[packId])
      return product
        ? { packId, coin: COIN_PACKS[packId].coin, priceText: product.displayPrice }
        : null
    })
    .filter(pack => pack !== null),
)

async function handleIapRecharge(packId: CoinPackId) {
  const ok = await iap.purchase(IAP_COIN_PRODUCTS[packId])
  if (ok) {
    showIonicToast('充值已到账')
    iap.reset()
    await loadTransactions(true)
  }
  else if (iap.phase.value === 'fail') {
    showIonicToast(iap.errorMessage.value || '购买失败，请稍后重试', 'danger')
    iap.reset()
  }
}

/** 余额等价人民币（1 云币 = 10 分） */
const balanceEquivText = computed(() =>
  `≈ ${formatPrice(balance.value * COIN_RATE_FEN)} · 100 云币 = 10 元`,
)

// 流水分页（按时间倒序，nextSkip 为 null 表示没有更多）
const transactions = ref<CoinTransaction[]>([])
const txLoading = ref(false)
const nextSkip = ref<number | null>(0)
const hasMore = computed(() => nextSkip.value !== null)

async function loadTransactions(reset = false) {
  if (txLoading.value)
    return
  if (reset) {
    transactions.value = []
    nextSkip.value = 0
  }
  if (nextSkip.value === null || !userStore.isLoggedIn)
    return
  txLoading.value = true
  try {
    const { items, nextSkip: ns } = await listTransactions({ skip: nextSkip.value, limit: 20 })
    transactions.value.push(...items)
    nextSkip.value = ns
  }
  finally {
    txLoading.value = false
  }
}

async function loadMore(event: CustomEvent) {
  await loadTransactions()
  ;(event.target as HTMLIonInfiniteScrollElement).complete()
}

/** 兜底对账（补发漏到账的订单）+ 全量刷新 */
async function reconcileAndRefresh() {
  const { paid } = await reconcileOrders()
  await Promise.all([refresh(), loadTransactions(true)])
  if (paid > 0)
    showIonicToast(`已为你补发到账：${paid} 笔支付已确认入账`)
}

onMounted(async () => {
  if (!userStore.isLoggedIn) {
    router.replace('/login')
    return
  }
  if (channel === 'ios-iap') {
    await iap.loadProducts()
    const settled = await iap.processUnfinished()
    if (settled > 0)
      showIonicToast('购买已到账')
  }
  await reconcileAndRefresh()
})

async function handleRefresh(event: CustomEvent) {
  await Promise.all([refresh(), loadTransactions(true)])
  ;(event.target as HTMLIonRefresherElement).complete()
}

function goMembership() {
  router.push('/membership')
}

/** 会员到期日期展示 */
const memberExpireText = computed(() => formatExpireDate(membership.value?.expireAt))
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
        <div class="balance-equiv">
          {{ balanceEquivText }}
        </div>
        <!-- Web：跳 www 微信支付；iOS：站内 IAP（见下方充值包） -->
        <k-button v-if="canPurchase" rounded class="recharge-btn" @click="goRecharge">
          充值云币
        </k-button>
      </k-block>

      <!-- iOS 充值包（App Store 内购；商品未就绪时整体隐藏，审核 3.1.1 不可降级为外部支付） -->
      <template v-if="channel === 'ios-iap' && iapCoinPacks.length > 0">
        <k-block-title>充值云币</k-block-title>
        <k-block strong inset>
          <div class="iap-pack-grid">
            <button
              v-for="pack in iapCoinPacks"
              :key="pack.packId"
              type="button"
              class="iap-pack-card"
              :disabled="iap.purchasing.value"
              @click="handleIapRecharge(pack.packId)"
            >
              <div class="iap-pack-coin">
                {{ pack.coin }}
              </div>
              <div class="iap-pack-unit">
                云币
              </div>
              <div class="iap-pack-price">
                {{ pack.priceText }}
              </div>
            </button>
          </div>
        </k-block>
      </template>

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

      <IonInfiniteScroll :disabled="!hasMore" threshold="100px" @ion-infinite="loadMore">
        <IonInfiniteScrollContent loading-spinner="crescent" loading-text="加载中…" />
      </IonInfiniteScroll>
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
  margin: 8px 0 4px;
  color: var(--ion-text-color);
}

.balance-equiv {
  font-size: 12px;
  color: var(--ion-color-medium);
  margin-bottom: 16px;
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

/* iOS IAP 充值包 */
.iap-pack-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
}

.iap-pack-card {
  border: 1.5px solid var(--ion-color-step-200, #e5e5ea);
  border-radius: 14px;
  padding: 14px 8px 10px;
  text-align: center;
  background: transparent;
}

.iap-pack-card:disabled {
  opacity: 0.5;
}

.iap-pack-coin {
  font-size: 20px;
  font-weight: 700;
}

.iap-pack-unit {
  font-size: 12px;
  color: var(--ion-color-medium);
}

.iap-pack-price {
  font-size: 14px;
  font-weight: 600;
  color: var(--ion-color-primary, #007aff);
  margin-top: 6px;
}
</style>
