/** www 钱包 / 会员页（携带 from=apps，支付成功后 www 显示「返回云乐坊」） */
export const WWW_WALLET_URL = 'https://www.yunle.fun/wallet?from=apps'
export const WWW_PRICING_URL = 'https://www.yunle.fun/pricing?from=apps'

/**
 * Open online checkout and reconcile once when its tab becomes visible again.
 * Native iOS commerce is owned by apps/ios, independently of these Web pages.
 */
export function usePaymentChannel(options: {
  /** 用户从外部支付页回到 App 后的回调（仅在本组合式触发过跳转后才会调用） */
  onReturn?: () => void | Promise<void>
} = {}) {
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
    pendingReturn.value = true
    openInAppBrowser(WWW_WALLET_URL)
  }

  /** 去开通 / 续费会员 */
  function goMembershipPurchase() {
    pendingReturn.value = true
    openInAppBrowser(WWW_PRICING_URL)
  }

  function onVisibilityChange() {
    if (document.visibilityState === 'visible')
      handleReturn()
  }

  onMounted(() => document.addEventListener('visibilitychange', onVisibilityChange))

  onUnmounted(() => {
    document.removeEventListener('visibilitychange', onVisibilityChange)
  })

  return {
    goRecharge,
    goMembershipPurchase,
  }
}
