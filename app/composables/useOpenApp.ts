import type { YlfAppInfo } from '@yunlefun/types'
import { alertController } from '@ionic/vue'
import { useStorage } from '@vueuse/core'
import consola from 'consola'

/**
 * useOpenApp - 统一的应用打开入口（含会员 / 云币门控）
 *
 * 收口了原本散落在 home.vue 和 AppItem.vue 的打开逻辑，并在打开前做门控：
 * - `requiresMembership`：会员专属应用，非会员引导去开通
 * - `coinCost > 0`：付费应用，**一次购买永久使用**，会员免购。
 *   服务端以 `bizId = purchase:{appKey}` 幂等去重，同一用户重复购买不会重复扣费；
 *   本地已购缓存仅用于跳过确认弹窗，丢失后重走购买流程也只会命中 dedupe。
 *
 * 未登录用户访问付费 / 会员应用时引导去登录。
 */
export function useOpenApp() {
  const router = useRouter()
  const userStore = useUserStore()
  const { account, balance, isMember, refresh, deduct } = useCoin()
  const { showError, showSuccess } = useToast()

  /** 已购应用本地缓存（仅用于免确认直接打开，真实凭证以服务端 bizId 幂等记录为准） */
  const purchasedApps = useStorage<string[]>('ylf:purchased-apps', [])

  /** 通用确认弹窗，返回用户是否点了确认 */
  async function confirm(header: string, message: string, okText = '确定'): Promise<boolean> {
    const alert = await alertController.create({
      header,
      message,
      buttons: [
        { text: '取消', role: 'cancel' },
        { text: okText, role: 'confirm' },
      ],
    })
    await alert.present()
    const { role } = await alert.onDidDismiss()
    return role === 'confirm'
  }

  /** 真正执行打开（callback / 外链 / 站内路由） */
  function doOpen(app: YlfAppInfo) {
    if (app.callback) {
      app.callback()
    }
    else if (app.websiteUrl) {
      if (app.websiteUrl.startsWith('http')) {
        openCatalogAppInBrowser(app)
      }
      else {
        router.push(app.websiteUrl)
      }
    }
  }

  /** 是否需要账户门控（付费或会员专属） */
  function needsGate(app: YlfAppInfo): boolean {
    return app.requiresMembership === true || (app.coinCost ?? 0) > 0
  }

  /**
   * 打开应用。返回是否真正打开（被门控拦截时返回 false）。
   */
  async function openApp(app: YlfAppInfo): Promise<boolean> {
    // 免费且非会员专属：直接打开
    if (!needsGate(app)) {
      doOpen(app)
      return true
    }

    // 需要门控但未登录 → 引导登录
    if (!userStore.isLoggedIn) {
      const ok = await confirm('需要登录', `打开「${app.name}」需要先登录云乐坊账户。`, '去登录')
      if (ok)
        router.push('/login')
      return false
    }

    // 确保账户快照已加载（用于会员状态 / 余额判断）
    if (!account.value)
      await refresh()

    // 会员专属
    if (app.requiresMembership && !isMember.value) {
      const ok = await confirm('会员专属', `「${app.name}」为会员专属应用，开通云乐坊会员后即可使用。`, '去开通')
      if (ok)
        router.push('/wallet')
      return false
    }

    // 付费应用：一次购买永久使用（会员免购）
    const cost = app.coinCost ?? 0
    const appKey = app.id || app.slug
    if (cost > 0 && !isMember.value && !purchasedApps.value.includes(appKey)) {
      if (balance.value < cost) {
        const ok = await confirm('云币不足', `购买「${app.name}」需 ${cost} 云币，当前余额 ${balance.value} 云币。`, '去充值')
        if (ok)
          router.push('/wallet')
        return false
      }

      const ok = await confirm(
        '购买应用',
        `「${app.name}」为付费应用，购买需 ${cost} 云币（一次购买，永久使用）。当前余额 ${balance.value} 云币。`,
        '确认购买',
      )
      if (!ok)
        return false

      try {
        const result = await deduct({
          appId: appKey,
          amount: cost,
          // 固定 bizId：同一用户对同一应用只会成功扣费一次（服务端幂等）
          bizId: `purchase:${appKey}`,
          meta: { scene: 'purchase-app', name: app.name },
        })
        showSuccess(result.deduped ? '你已拥有该应用，未重复扣费' : `已购买「${app.name}」`)
        purchasedApps.value = [...purchasedApps.value, appKey]
      }
      catch (e) {
        consola.error('[useOpenApp] purchase failed:', e)
        showError('购买失败，请稍后再试')
        return false
      }
    }

    doOpen(app)
    return true
  }

  return {
    openApp,
    needsGate,
  }
}
