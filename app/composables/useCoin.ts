import type { AccountSnapshot, CoinTransaction } from '@yunlefun/types'
import consola from 'consola'

/**
 * 平台账户 composable（云币余额 + 会员状态 + 流水）。
 *
 * - 对接 www.yunle.fun 已部署的 `account-api` 云函数（共用同一 CloudBase 环境）
 * - 全局共享：通过 useState 在多个组件间复用同一份账户快照
 * - 与登录态联动：用户变化时自动刷新 / 清空
 *
 * 充值 / 开通会员的下单流程仍在 www 完成，App 端只读账户 + 按次扣费。
 */
export function useCoin() {
  const { app } = useCloudbase()
  const userStore = useUserStore()

  const account = useState<AccountSnapshot | null>('coin_account', () => null)
  const loading = ref(false)
  const error = ref<string | null>(null)

  const balance = computed(() => account.value?.coin ?? 0)
  const membership = computed(() => account.value?.membership ?? null)
  const isMember = computed(() => !!account.value?.membership.isActive)

  /** 拉取账户全貌（余额 + 会员） */
  async function refresh(): Promise<AccountSnapshot | null> {
    if (!userStore.isLoggedIn || !app) {
      account.value = null
      return null
    }
    loading.value = true
    error.value = null
    try {
      const res = await app.callFunction({
        name: 'account-api',
        data: { action: 'getAccount' },
      })
      account.value = res.result as AccountSnapshot
      return account.value
    }
    catch (err) {
      error.value = err instanceof Error ? err.message : '获取账户失败'
      consola.warn('[useCoin] refresh failed:', err)
      return account.value
    }
    finally {
      loading.value = false
    }
  }

  /**
   * 扣减云币（供各子应用按次消费调用）。
   *
   * params：appId 业务应用标识、amount 扣减云币数（正整数）、
   * bizId 业务幂等键（同一 bizId 只扣一次）、meta 业务自定义信息。
   */
  async function deduct(params: {
    appId: string
    amount: number
    bizId?: string
    meta?: Record<string, unknown>
  }): Promise<{ balance: number, deduped: boolean }> {
    if (!app)
      throw new Error('账户服务暂不可用')
    const res = await app.callFunction({
      name: 'account-api',
      data: { action: 'deductCoin', ...params },
    })
    const result = res.result as { balance: number, deduped: boolean }
    // 同步本地余额
    if (account.value)
      account.value = { ...account.value, coin: result.balance }
    return result
  }

  /** 云币流水分页（按时间倒序） */
  async function listTransactions(params: { skip?: number, limit?: number } = {}): Promise<{
    items: CoinTransaction[]
    nextSkip: number | null
  }> {
    if (!app)
      return { items: [], nextSkip: null }
    const res = await app.callFunction({
      name: 'account-api',
      data: { action: 'listTransactions', skip: params.skip ?? 0, limit: params.limit ?? 20 },
    })
    return res.result as { items: CoinTransaction[], nextSkip: number | null }
  }

  // 用户变化时自动刷新
  watch(
    () => userStore.userInfo?.id,
    (newId, oldId) => {
      if (newId !== oldId) {
        if (newId)
          refresh()
        else
          account.value = null
      }
    },
    { immediate: false },
  )

  return {
    account: readonly(account),
    balance,
    membership,
    isMember,
    loading: readonly(loading),
    error: readonly(error),
    refresh,
    deduct,
    listTransactions,
  }
}
