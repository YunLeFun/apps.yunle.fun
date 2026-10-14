import type { PluginListenerHandle } from '@capacitor/core'
import { Browser } from '@capacitor/browser'
import { Capacitor } from '@capacitor/core'

/**
 * 支付通道：
 * - `web-redirect`：跳转 www.yunle.fun 完成微信支付（Web / 非 iOS 原生环境）
 * - `ios-iap`：iOS 原生壳内走 App Store 内购（App Store 审核指南 3.1.1
 *   禁止 iOS 包内出现微信支付等外部购买入口）
 */
export type PaymentChannel = 'web-redirect' | 'ios-iap'

/** www 钱包 / 会员页（携带 from=apps，支付成功后 www 显示「返回云乐坊」） */
export const WWW_WALLET_URL = 'https://www.yunle.fun/wallet?from=apps'
export const WWW_PRICING_URL = 'https://www.yunle.fun/pricing?from=apps'

/** 判定当前环境的支付通道（iOS 原生壳一律 IAP，其余跳 www） */
export function getPaymentChannel(): PaymentChannel {
  if (Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'ios')
    return 'ios-iap'
  return 'web-redirect'
}

/**
 * 支付通道唯一裁决点：充值 / 开通会员入口统一从这里走。
 *
 * web-redirect：跳 www 支付，并在用户回到 App 时自动触发 `onReturn`
 * （原生 in-app browser 关闭 / Web 标签页重新可见），由调用方在回调里
 * 做 reconcile + refresh，闭环「跳出去支付 → 回来余额对上」。
 *
 * ios-iap：IAP 上线前 `canPurchase` 为 false，页面应整体隐藏购买入口
 * （不能降级为跳 Safari 微信支付，审核红线）。
 */
export function usePaymentChannel(options: {
  /** 用户从外部支付页回到 App 后的回调（仅在本组合式触发过跳转后才会调用） */
  onReturn?: () => void | Promise<void>
} = {}) {
  const channel = getPaymentChannel()

  /** 当前通道下购买入口是否可用 */
  const canPurchase = computed(() => channel === 'web-redirect')

  /** 是否跳出去支付过（避免普通切后台也触发对账刷新） */
  const pendingReturn = ref(false)

  async function handleReturn() {
    if (!pendingReturn.value)
      return
    pendingReturn.value = false
    await options.onReturn?.()
  }

  /** 去充值云币 */
  function goRecharge() {
    if (channel !== 'web-redirect')
      return
    pendingReturn.value = true
    openInAppBrowser(WWW_WALLET_URL)
  }

  /** 去开通 / 续费会员 */
  function goMembershipPurchase() {
    if (channel !== 'web-redirect')
      return
    pendingReturn.value = true
    openInAppBrowser(WWW_PRICING_URL)
  }

  // 回到 App 的两条路径：
  // - 原生壳：in-app browser 关闭（browserFinished）
  // - 纯 Web：window.open 新标签页支付后切回来（visibilitychange）
  let browserHandle: PluginListenerHandle | null = null

  function onVisibilityChange() {
    if (document.visibilityState === 'visible')
      handleReturn()
  }

  onMounted(async () => {
    if (Capacitor.isNativePlatform())
      browserHandle = await Browser.addListener('browserFinished', handleReturn)
    else
      document.addEventListener('visibilitychange', onVisibilityChange)
  })

  onUnmounted(() => {
    browserHandle?.remove()
    document.removeEventListener('visibilitychange', onVisibilityChange)
  })

  return {
    channel,
    canPurchase,
    goRecharge,
    goMembershipPurchase,
  }
}
