import type { IapProduct, IapTransaction } from '@yunlefun/capacitor-storekit'
import type { PaymentPhase } from '@yunlefun/types'
import { Storekit } from '@yunlefun/capacitor-storekit'
import { IAP_ALL_PRODUCT_IDS } from '@yunlefun/types'
import consola from 'consola'

const XCODE_STOREKIT_ERROR
  = '本地 StoreKit 仅用于界面预览，请使用 App Scheme 和 Sandbox 测试完整购买链路'

function isXcodeStoreKitTransaction(tx: IapTransaction): boolean {
  if (tx.originalTransactionId === '0')
    return true

  try {
    const encodedHeader = tx.jws.split('.')[0]
    if (!encodedHeader)
      return false
    const base64 = encodedHeader
      .replaceAll('-', '+')
      .replaceAll('_', '/')
      .padEnd(Math.ceil(encodedHeader.length / 4) * 4, '=')
    const header = JSON.parse(atob(base64)) as { kid?: string }
    return header.kid === 'Apple_Xcode_Key'
  }
  catch {
    return false
  }
}

/**
 * iOS App Store 内购流程（仅 'ios-iap' 通道下使用，调用方必须先判定通道）。
 *
 * 购买链路：Storekit.purchase →（服务端）iap-order verifyPurchase 经
 * App Store Server API 校验入账 → Storekit.finishTransaction → 刷新账户。
 * 服务端入账成功前绝不 finish，杀进程 / 网络失败的交易留在 unfinished，
 * 由 processUnfinished / restore 补单。
 */
export function useIap() {
  const { app } = useCloudbase()
  const { refresh } = useCoin()

  /** 商品列表（含本地化价格，iOS 端展示必须用 displayPrice） */
  const products = useState<IapProduct[]>('iap_products', () => [])
  /** 商品是否加载成功（失败时页面应隐藏购买入口） */
  const ready = computed(() => products.value.length > 0)

  const phase = ref<PaymentPhase>('confirm')
  const errorMessage = ref('')
  const purchasing = ref(false)

  /** 拉取商品（幂等，已加载则跳过） */
  async function loadProducts() {
    if (ready.value)
      return
    try {
      const { products: list } = await Storekit.getProducts({ productIds: IAP_ALL_PRODUCT_IDS })
      products.value = list
    }
    catch (err) {
      consola.warn('[useIap] 拉取商品失败:', err)
    }
  }

  function findProduct(productId: string): IapProduct | undefined {
    return products.value.find(p => p.productId === productId)
  }

  /** 服务端校验入账；成功后才允许 finish */
  async function verifyOnServer(tx: IapTransaction) {
    if (!app)
      throw new Error('账户服务暂不可用')
    const res = await app.callFunction({
      name: 'iap-order',
      data: { action: 'verifyPurchase', transactionId: tx.transactionId },
    })
    return res.result as { granted: boolean, alreadyProcessed?: boolean }
  }

  /**
   * 购买商品（用户取消静默返回 false；其他失败置 phase=fail）。
   */
  async function purchase(productId: string): Promise<boolean> {
    if (purchasing.value)
      return false
    purchasing.value = true
    phase.value = 'paying'
    errorMessage.value = ''
    try {
      const tx = await Storekit.purchase({ productId })
      if (isXcodeStoreKitTransaction(tx)) {
        // Xcode 本地交易无法被 App Store Server API 验签；及时结束，避免它在
        // 后续启动时反复出现在 unfinished 队列并被误送到线上补单。
        await Storekit.finishTransaction({ transactionId: tx.transactionId })
        throw new Error(XCODE_STOREKIT_ERROR)
      }
      await verifyOnServer(tx)
      await Storekit.finishTransaction({ transactionId: tx.transactionId })
      await refresh()
      phase.value = 'success'
      return true
    }
    catch (err) {
      const code = (err as { code?: string }).code
      if (code === 'USER_CANCELLED') {
        phase.value = 'confirm'
        return false
      }
      // PENDING（待批准）：交易完成后走 transactionUpdated 补单
      if (code === 'PENDING') {
        phase.value = 'confirm'
        errorMessage.value = '交易等待批准，完成后将自动到账'
        return false
      }
      consola.warn('[useIap] 购买失败:', err)
      phase.value = 'fail'
      errorMessage.value = err instanceof Error ? err.message : '购买失败，请稍后重试'
      return false
    }
    finally {
      purchasing.value = false
    }
  }

  /** 补单一批交易：服务端入账成功的逐一 finish */
  async function settleTransactions(transactions: IapTransaction[]): Promise<number> {
    if (transactions.length === 0)
      return 0

    const appStoreTransactions: IapTransaction[] = []
    for (const tx of transactions) {
      if (isXcodeStoreKitTransaction(tx)) {
        // 旧的 Xcode 测试交易只做本地清理，绝不进入线上验单。
        await Storekit.finishTransaction({ transactionId: tx.transactionId })
      }
      else {
        appStoreTransactions.push(tx)
      }
    }

    if (appStoreTransactions.length === 0 || !app)
      return 0

    const res = await app.callFunction({
      name: 'iap-order',
      data: {
        action: 'restore',
        transactionIds: appStoreTransactions.map(tx => tx.transactionId),
      },
    })
    const { results } = res.result as { results: { transactionId: string, ok: boolean }[] }
    let settled = 0
    for (const item of results) {
      if (!item.ok)
        continue
      await Storekit.finishTransaction({ transactionId: item.transactionId })
      settled++
    }
    if (settled > 0)
      await refresh()
    return settled
  }

  /** 启动补单：处理 unfinished 交易（页面 onMounted 调用） */
  async function processUnfinished(): Promise<number> {
    try {
      const { transactions } = await Storekit.getUnfinishedTransactions()
      return await settleTransactions(transactions)
    }
    catch (err) {
      consola.warn('[useIap] 补单失败:', err)
      return 0
    }
  }

  /** 恢复购买（审核要求的显式入口）：与 App Store 同步后补单 */
  async function restore(): Promise<number> {
    const { transactions } = await Storekit.restorePurchases()
    return settleTransactions(transactions)
  }

  function reset() {
    phase.value = 'confirm'
    errorMessage.value = ''
  }

  return {
    products: readonly(products),
    ready,
    phase: readonly(phase),
    errorMessage: readonly(errorMessage),
    purchasing: readonly(purchasing),
    loadProducts,
    findProduct,
    purchase,
    processUnfinished,
    restore,
    reset,
  }
}
