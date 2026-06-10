<script setup lang="ts">
import type { BillingCycle } from '@yunlefun/types'
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
import { formatPrice, IAP_MEMBER_PRODUCTS, PLAN_FEATURES, PLAN_NAMES, PLAN_PRICES } from '@yunlefun/types'
import {
  checkmarkCircle,
  ribbon,
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
const { membership, isMember, refresh, reconcileOrders } = useCoin()
const iap = useIap()

const { channel, goMembershipPurchase } = usePaymentChannel({
  // 从 www 支付页回到 App：兜底对账 + 刷新会员状态
  onReturn: async () => {
    const { paid } = await reconcileOrders()
    await refresh()
    if (paid > 0)
      showIonicToast('已为你补发到账')
  },
})

/** 会员等级（当前仅 basic） */
const LEVEL = 'basic'

/** 套餐选项：iOS 用 App Store 本地化价（displayPrice），Web 用人民币价 */
const cycleOptions = computed(() => {
  return (['month', 'year'] as BillingCycle[]).map((cycle) => {
    const iapProduct = channel === 'ios-iap'
      ? iap.findProduct(IAP_MEMBER_PRODUCTS[LEVEL][cycle])
      : undefined
    return {
      cycle,
      label: cycle === 'month' ? '月度' : '年度',
      priceText: iapProduct?.displayPrice ?? formatPrice(PLAN_PRICES[LEVEL][cycle]),
      popular: cycle === 'year',
      note: channel === 'web-redirect' && cycle === 'year' ? '约 8.4 折' : '',
    }
  })
})

const selectedCycle = ref<BillingCycle>('year')

/** 当前通道下购买入口是否可用（iOS 须商品加载成功，否则整体隐藏，见审核 3.1.1） */
const purchasable = computed(() => channel === 'web-redirect' || iap.ready.value)

const memberExpireText = computed(() => formatExpireDate(membership.value?.expireAt))

onMounted(async () => {
  if (userStore.isLoggedIn)
    refresh()
  if (channel === 'ios-iap') {
    await iap.loadProducts()
    // 杀进程 / 入账失败的交易补单
    const settled = await iap.processUnfinished()
    if (settled > 0)
      showIonicToast('购买已到账')
  }
})

async function handleRefresh(event: CustomEvent) {
  await refresh()
  ;(event.target as HTMLIonRefresherElement).complete()
}

async function handlePurchase() {
  if (channel === 'web-redirect') {
    goMembershipPurchase()
    return
  }
  if (!userStore.isLoggedIn) {
    router.push('/login')
    return
  }
  const ok = await iap.purchase(IAP_MEMBER_PRODUCTS[LEVEL][selectedCycle.value])
  if (ok) {
    showIonicToast('会员已开通')
    iap.reset()
  }
  else if (iap.phase.value === 'fail') {
    showIonicToast(iap.errorMessage.value || '购买失败，请稍后重试', 'danger')
    iap.reset()
  }
}

/** 恢复购买（App Store 审核要求的显式入口） */
async function handleRestore() {
  try {
    const settled = await iap.restore()
    showIonicToast(settled > 0 ? `已恢复 ${settled} 笔购买` : '没有可恢复的购买')
  }
  catch {
    showIonicToast('恢复购买失败，请稍后重试', 'danger')
  }
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>{{ PLAN_NAMES[LEVEL] }}</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonRefresher slot="fixed" @ion-refresh="handleRefresh">
        <IonRefresherContent />
      </IonRefresher>

      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            {{ PLAN_NAMES[LEVEL] }}
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 会员状态卡 -->
      <k-block strong inset class="member-card" :class="isMember ? 'member-card-active' : ''">
        <div class="member-card-icon">
          <IonIcon :icon="ribbon" />
        </div>
        <div class="member-card-status">
          {{ isMember ? '会员有效中' : '尚未开通会员' }}
        </div>
        <div class="member-card-sub">
          {{ isMember ? memberExpireText : '开通后解锁全部权益' }}
        </div>
      </k-block>

      <!-- 权益介绍 -->
      <k-block-title>会员权益</k-block-title>
      <k-list strong inset>
        <k-list-item
          v-for="feature in PLAN_FEATURES[LEVEL]"
          :key="feature"
          :title="feature"
        >
          <template #media>
            <IonIcon :icon="checkmarkCircle" class="feature-check" />
          </template>
        </k-list-item>
      </k-list>

      <!-- 套餐选择 + 购买（iOS 商品未就绪时整体隐藏，不可降级为外部支付，见审核 3.1.1） -->
      <template v-if="purchasable">
        <k-block-title>选择套餐</k-block-title>
        <k-block strong inset class="plan-grid-block">
          <div class="plan-grid">
            <button
              v-for="opt in cycleOptions"
              :key="opt.cycle"
              type="button"
              class="plan-card"
              :class="{ 'plan-card-selected': selectedCycle === opt.cycle }"
              @click="selectedCycle = opt.cycle"
            >
              <span v-if="opt.popular" class="plan-badge">推荐</span>
              <div class="plan-label">
                {{ opt.label }}
              </div>
              <div class="plan-price">
                {{ opt.priceText }}
              </div>
              <div class="plan-note">
                {{ opt.note || '&nbsp;' }}
              </div>
            </button>
          </div>

          <k-button rounded class="purchase-btn" :disabled="iap.purchasing.value" @click="handlePurchase">
            {{ isMember ? '续费会员' : '立即开通' }}
          </k-button>
          <p v-if="channel === 'web-redirect'" class="purchase-hint">
            将跳转 www.yunle.fun 完成支付，支付完成后返回本页自动到账
          </p>
          <p v-else class="purchase-hint restore-link" @click="handleRestore">
            恢复购买
          </p>
        </k-block>
      </template>
      <k-block v-else strong inset class="text-center opacity-50">
        会员购买即将上线
      </k-block>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.member-card {
  text-align: center;
  padding-top: 24px !important;
  padding-bottom: 24px !important;
}

.member-card-icon {
  font-size: 40px;
  color: var(--ion-color-medium);
}

.member-card-active .member-card-icon {
  color: var(--ion-color-warning, #ff9f0a);
}

.member-card-status {
  font-size: 20px;
  font-weight: 700;
  margin-top: 8px;
}

.member-card-sub {
  font-size: 14px;
  color: var(--ion-color-medium);
  margin-top: 4px;
}

.feature-check {
  font-size: 22px;
  color: var(--ion-color-success, #2dd36f);
}

.plan-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.plan-card {
  position: relative;
  border: 1.5px solid var(--ion-color-step-200, #e5e5ea);
  border-radius: 14px;
  padding: 16px 12px 10px;
  text-align: center;
  background: transparent;
}

.plan-card-selected {
  border-color: var(--ion-color-primary, #007aff);
  background: rgba(0, 122, 255, 0.06);
}

.plan-badge {
  position: absolute;
  top: -9px;
  left: 50%;
  transform: translateX(-50%);
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  color: #fff;
  background: var(--ion-color-warning, #ff9f0a);
  border-radius: 8px;
  padding: 3px 8px;
}

.plan-label {
  font-size: 14px;
  color: var(--ion-color-medium);
}

.plan-price {
  font-size: 22px;
  font-weight: 700;
  margin-top: 4px;
}

.plan-note {
  font-size: 12px;
  color: var(--ion-color-warning, #ff9f0a);
  margin-top: 2px;
  min-height: 16px;
}

.purchase-btn {
  max-width: 240px;
  margin: 16px auto 0;
}

.purchase-hint {
  font-size: 12px;
  color: var(--ion-color-medium);
  text-align: center;
  margin-top: 10px;
}

.restore-link {
  color: var(--ion-color-primary, #007aff);
  cursor: pointer;
}
</style>
