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
  onIonViewWillEnter,
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
const toast = useToast()

const { channel, goMembershipPurchase } = usePaymentChannel({
  // 从 www 支付页回到 App：兜底对账 + 刷新会员状态
  onReturn: async () => {
    const { paid } = await reconcileOrders()
    await refresh()
    if (paid > 0)
      toast.showSuccess('已为你补发到账')
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
const restoring = ref(false)

/** 当前通道下购买入口是否可用（iOS 须商品加载成功，否则整体隐藏，见审核 3.1.1） */
const purchasable = computed(() => channel === 'web-redirect' || iap.ready.value)

const memberExpireText = computed(() => formatExpireDate(membership.value?.expireAt))

// Ionic 会缓存路由页面；每次重新进入都以服务端快照覆盖本地旧状态。
onIonViewWillEnter(() => {
  if (userStore.isLoggedIn)
    refresh()
})

onMounted(async () => {
  if (channel === 'ios-iap') {
    await iap.loadProducts()
    // 杀进程 / 入账失败的交易补单
    const settled = await iap.processUnfinished()
    if (settled > 0)
      toast.showSuccess('购买已到账')
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
    toast.showSuccess('会员已开通')
    iap.reset()
  }
  else if (iap.phase.value === 'fail') {
    toast.showError(iap.errorMessage.value || '购买失败，请稍后重试', '')
    iap.reset()
  }
}

/** 恢复购买（App Store 审核要求的显式入口） */
async function handleRestore() {
  if (restoring.value)
    return
  restoring.value = true
  try {
    const settled = await iap.restore()
    if (settled > 0)
      toast.showSuccess(`已恢复 ${settled} 笔购买`)
    else
      toast.showInfo('未发现需要恢复的购买')
  }
  catch {
    toast.showError('恢复购买失败，请稍后重试', '')
  }
  finally {
    restoring.value = false
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
            <IonIcon :icon="checkmarkCircle" class="feature-check" aria-hidden="true" />
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
              :aria-pressed="selectedCycle === opt.cycle"
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
          <div v-else class="restore-purchase">
            <button
              type="button"
              class="purchase-hint restore-link"
              :disabled="restoring"
              :aria-busy="restoring"
              aria-describedby="restore-purchase-tip"
              @click="handleRestore"
            >
              {{ restoring ? '正在恢复…' : '恢复 App Store 购买' }}
            </button>
            <p id="restore-purchase-tip" class="restore-tip">
              更换设备或重装后，可恢复当前 Apple 账户购买的会员，不会重复扣款
            </p>
          </div>
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
  color: var(--ylf-color-success-on-surface);
}

.plan-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.plan-card {
  position: relative;
  border: 1px solid color-mix(in srgb, currentColor 12%, transparent);
  border-radius: 14px;
  padding: 16px 12px 10px;
  color: inherit;
  text-align: center;
  background: color-mix(in srgb, var(--ion-item-background, var(--ion-background-color)) 94%, currentColor 6%);
  transition:
    background-color 160ms ease,
    border-color 160ms ease,
    transform 160ms ease;
}

.plan-card-selected {
  border-color: color-mix(
    in srgb,
    var(--ion-color-primary) 72%,
    var(--ion-item-background, var(--ion-background-color))
  );
  background: color-mix(in srgb, var(--ion-color-primary) 12%, var(--ion-item-background, var(--ion-background-color)));
  box-shadow: inset 0 0 0 0.5px color-mix(in srgb, var(--ion-color-primary) 38%, transparent);
}

.plan-card:active {
  transform: scale(0.985);
}

.plan-card:focus-visible,
.purchase-btn:focus-visible,
.restore-link:focus-visible {
  outline: 2px solid var(--ion-color-primary);
  outline-offset: 2px;
}

.plan-badge {
  position: absolute;
  top: -10px;
  left: 50%;
  transform: translateX(-50%);
  font-size: 11px;
  font-weight: 700;
  line-height: 1.1;
  color: var(--ylf-color-warning-on);
  background: var(--ion-color-warning, #ff9f0a);
  border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
  border-radius: 999px;
  padding: 3px 9px;
  box-shadow: 0 1px 3px color-mix(in srgb, currentColor 14%, transparent);
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
  font-weight: 600;
  color: var(--ylf-color-warning-text);
  margin-top: 2px;
  min-height: 16px;
}

.purchase-btn {
  max-width: 240px;
  min-height: 44px;
  height: 44px;
  margin: 16px auto 0;
  background-color: var(--ylf-color-primary-action);
}

.purchase-btn:active {
  background-color: var(--ylf-color-primary-action-pressed);
}

.purchase-hint {
  font-size: 12px;
  line-height: 1.45;
  color: var(--ion-color-medium);
  text-align: center;
  margin-top: 10px;
}

.restore-link {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 44px;
  padding: 0 12px;
  border: 0;
  background: transparent;
  color: var(--ion-color-primary, #007aff);
  cursor: pointer;
  margin-right: auto;
  margin-left: auto;
}

.restore-link:disabled {
  opacity: 0.55;
  cursor: default;
}

.restore-tip {
  max-width: 320px;
  margin: -2px auto 0;
  color: var(--ion-color-medium);
  font-size: 12px;
  line-height: 1.45;
  text-align: center;
}

@media (prefers-reduced-motion: reduce) {
  .plan-card {
    transition: none;
  }

  .plan-card:active {
    transform: none;
  }
}
</style>
