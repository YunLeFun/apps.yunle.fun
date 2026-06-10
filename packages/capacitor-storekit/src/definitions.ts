import type { PluginListenerHandle } from '@capacitor/core'

/** App Store 商品（含按用户地区本地化的价格） */
export interface IapProduct {
  productId: string
  displayName: string
  description: string
  /** 本地化展示价（如 "¥12.00"），iOS 端必须用它而非 Web 人民币价 */
  displayPrice: string
  price: number
  /** 'Consumable' | 'Non-Renewing Subscription' 等 */
  type: string
}

/** StoreKit 2 交易（jws 仅作客户端参考，服务端以 Server API 回查为准） */
export interface IapTransaction {
  transactionId: string
  originalTransactionId: string
  productId: string
  jws: string
}

export interface StorekitPlugin {
  /** 拉取商品信息（本地化价格展示用） */
  getProducts: (options: { productIds: string[] }) => Promise<{ products: IapProduct[] }>

  /**
   * 发起购买。成功返回交易信息；**不会** finish 交易，
   * 调用方必须在服务端入账成功后调 finishTransaction。
   * 拒绝码：USER_CANCELLED（用户取消）、PENDING（待批准）、VERIFICATION_FAILED。
   */
  purchase: (options: { productId: string }) => Promise<IapTransaction>

  /** 服务端入账成功后结束交易（找不到视为已结束，幂等） */
  finishTransaction: (options: { transactionId: string }) => Promise<void>

  /** 未结束的交易（杀进程 / 入账失败后的补单来源） */
  getUnfinishedTransactions: () => Promise<{ transactions: IapTransaction[] }>

  /** 恢复购买：与 App Store 同步后返回未结束交易 */
  restorePurchases: () => Promise<{ transactions: IapTransaction[] }>

  /** 交易更新事件（待批准完成 / 客服补单等） */
  addListener: (
    eventName: 'transactionUpdated',
    listenerFunc: (transaction: IapTransaction) => void,
  ) => Promise<PluginListenerHandle>

  removeAllListeners: () => Promise<void>
}
