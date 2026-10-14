import { describe, expect, it } from 'vitest'
import { formatTxTitle } from '../../app/utils/format'

describe('formatTxTitle', () => {
  it('充值按渠道细分：IAP 订单 refId 以 iap_ 开头', () => {
    expect(formatTxTitle({ type: 'recharge', amount: 100, refId: 'iap_20001' })).toBe('App Store 充值')
    expect(formatTxTitle({ type: 'recharge', amount: 100, refId: 'O17500001' })).toBe('微信支付充值')
  })

  it('负数 refund 是渠道退款追回，按渠道细分', () => {
    expect(formatTxTitle({ type: 'refund', amount: -100, refId: 'iap_20001' })).toBe('App Store 退款追回')
    expect(formatTxTitle({ type: 'refund', amount: -100, refId: 'O17500001' })).toBe('退款追回')
    // 余额为零时的占位追回流水（amount 0）同样显示为追回
    expect(formatTxTitle({ type: 'refund', amount: 0, refId: 'iap_20001' })).toBe('App Store 退款追回')
  })

  it('正数 refund 是消费退还，沿用通用「退款」', () => {
    expect(formatTxTitle({ type: 'refund', amount: 50, refId: 'C1' })).toBe('退款')
  })

  it('其余类型用通用名', () => {
    expect(formatTxTitle({ type: 'consume', amount: -10, refId: 'C1' })).toBe('消费')
    expect(formatTxTitle({ type: 'gift', amount: 10, refId: '' })).toBe('赠送')
  })

  it('refId 缺失时按非 IAP 处理', () => {
    expect(formatTxTitle({ type: 'recharge', amount: 100, refId: '' })).toBe('微信支付充值')
  })
})
