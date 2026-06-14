import type { CoinTransaction } from '@yunlefun/types'
import { COIN_TX_TYPE_NAMES } from '@yunlefun/types'

/** IAP 订单 outTradeNo（即流水 refId）前缀，与微信支付订单区分 */
const IAP_REF_PREFIX = 'iap_'

/**
 * 流水标题：充值/退款追回按渠道细分（App Store / 微信支付），其余类型用通用名。
 * 负数 refund 是渠道退款后的云币追回；正数 refund 是消费退还，沿用「退款」。
 */
export function formatTxTitle(tx: Pick<CoinTransaction, 'type' | 'amount' | 'refId'>): string {
  const isIap = (tx.refId || '').startsWith(IAP_REF_PREFIX)
  if (tx.type === 'recharge')
    return isIap ? 'App Store 充值' : '微信支付充值'
  if (tx.type === 'refund' && tx.amount <= 0)
    return isIap ? 'App Store 退款追回' : '退款追回'
  return COIN_TX_TYPE_NAMES[tx.type]
}

/** 会员到期日期展示，如 `2026/6/10 到期`（无到期时间返回空串） */
export function formatExpireDate(expireAt: number | null | undefined): string {
  if (!expireAt)
    return ''
  const d = new Date(expireAt)
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} 到期`
}

/** 流水时间展示，如 `6/10 09:30` */
export function formatTxTime(ts: number): string {
  const d = new Date(ts)
  const pad = (n: number) => n.toString().padStart(2, '0')
  return `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
