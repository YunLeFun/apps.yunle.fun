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
import { formatPrice, PLAN_FEATURES, PLAN_NAMES, PLAN_PRICES } from '@yunlefun/types'
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
const { membership, isMember, refresh, reconcileOrders } = useCoin()
const toast = useToast()

const { goMembershipPurchase } = usePaymentChannel({
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

/** Online checkout displays the centrally defined RMB prices. */
const cycleOptions = computed(() => {
  return (['month', 'year'] as BillingCycle[]).map((cycle) => {
    return {
      cycle,
      label: cycle === 'month' ? '月度' : '年度',
      priceText: formatPrice(PLAN_PRICES[LEVEL][cycle]),
      popular: cycle === 'year',
      note: cycle === 'year' ? '约 8.4 折' : '',
    }
  })
})

const selectedCycle = ref<BillingCycle>('year')

const memberExpireText = computed(() => formatExpireDate(membership.value?.expireAt))

// Ionic 会缓存路由页面；每次重新进入都以服务端快照覆盖本地旧状态。
onIonViewWillEnter(() => {
  if (userStore.isLoggedIn)
    refresh()
})

async function handleRefresh(event: CustomEvent) {
  await refresh()
  ;(event.target as HTMLIonRefresherElement).complete()
}

function handlePurchase() {
  goMembershipPurchase()
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

        <k-button rounded class="purchase-btn" @click="handlePurchase">
          {{ isMember ? '续费会员' : '立即开通' }}
        </k-button>
        <p class="purchase-hint">
          将跳转 www.yunle.fun 完成支付，支付完成后返回本页自动到账
        </p>
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

@media (prefers-reduced-motion: reduce) {
  .plan-card {
    transition: none;
  }

  .plan-card:active {
    transform: none;
  }
}
</style>
