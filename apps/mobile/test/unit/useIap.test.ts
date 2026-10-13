import { beforeEach, describe, expect, it, vi } from 'vitest'
import { readonly, ref } from 'vue'

import { useIap } from '../../app/composables/useIap'

const storekit = vi.hoisted(() => ({
  getProducts: vi.fn(),
  purchase: vi.fn(),
  finishTransaction: vi.fn(),
  getUnfinishedTransactions: vi.fn(),
  restorePurchases: vi.fn(),
}))
const callFunction = vi.hoisted(() => vi.fn())
const refresh = vi.hoisted(() => vi.fn())
const nuxtState = new Map<string, ReturnType<typeof ref>>()

vi.mock('@yunlefun/capacitor-storekit', () => ({
  Storekit: storekit,
}))

vi.stubGlobal('useCloudbase', () => ({
  app: { callFunction },
}))

vi.stubGlobal('useCoin', () => ({
  refresh,
}))

vi.stubGlobal('readonly', readonly)
vi.stubGlobal('useState', <T>(key: string, init: () => T) => {
  if (!nuxtState.has(key))
    nuxtState.set(key, ref(init()))
  return nuxtState.get(key)
})

describe('useIap 购买链路', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    nuxtState.clear()
  })

  it('xcode 本地交易提示改用 Sandbox，且只在本地结束交易', async () => {
    const transaction = {
      transactionId: '1',
      originalTransactionId: '0',
      productId: 'fun.yunle.apps.member_month',
      jws: 'eyJhbGciOiJFUzI1NiIsImtpZCI6IkFwcGxlX1hjb2RlX0tleSJ9.payload.signature',
    }
    storekit.purchase.mockResolvedValue(transaction)
    callFunction.mockResolvedValue({ result: { granted: true } })

    const iap = useIap()
    const purchased = await iap.purchase('fun.yunle.apps.member_month')

    expect(purchased).toBe(false)
    expect(iap.phase.value).toBe('fail')
    expect(iap.errorMessage.value).toContain('Sandbox')
    expect(callFunction).not.toHaveBeenCalled()
    expect(storekit.finishTransaction).toHaveBeenCalledWith({
      transactionId: transaction.transactionId,
    })
    expect(refresh).not.toHaveBeenCalled()
  })

  it('启动补单会清理 xcode 本地交易且不会发送到线上恢复接口', async () => {
    const transaction = {
      transactionId: '2',
      originalTransactionId: '2',
      productId: 'fun.yunle.apps.member_year',
      jws: 'eyJhbGciOiJFUzI1NiIsImtpZCI6IkFwcGxlX1hjb2RlX0tleSJ9.payload.signature',
    }
    storekit.getUnfinishedTransactions.mockResolvedValue({
      transactions: [transaction],
    })

    const iap = useIap()
    const settled = await iap.processUnfinished()

    expect(settled).toBe(0)
    expect(callFunction).not.toHaveBeenCalled()
    expect(storekit.finishTransaction).toHaveBeenCalledWith({
      transactionId: transaction.transactionId,
    })
    expect(refresh).not.toHaveBeenCalled()
  })

  it('sandbox 交易验单成功后才结束交易并刷新会员', async () => {
    const trace: string[] = []
    const transaction = {
      transactionId: '2000000123456789',
      originalTransactionId: '2000000123456789',
      productId: 'fun.yunle.apps.member_month',
      jws: 'sandbox-jws',
    }
    storekit.purchase.mockImplementation(async () => {
      trace.push('purchase')
      return transaction
    })
    callFunction.mockImplementation(async (options) => {
      trace.push('verify')
      expect(options).toEqual({
        name: 'iap-order',
        data: {
          action: 'verifyPurchase',
          transactionId: transaction.transactionId,
        },
      })
      return { result: { granted: true } }
    })
    storekit.finishTransaction.mockImplementation(async () => {
      trace.push('finish')
    })
    refresh.mockImplementation(async () => {
      trace.push('refresh')
    })

    const iap = useIap()
    const purchased = await iap.purchase(transaction.productId)

    expect(purchased).toBe(true)
    expect(iap.phase.value).toBe('success')
    expect(trace).toEqual(['purchase', 'verify', 'finish', 'refresh'])
  })

  it('sandbox 验单失败时保留未结束交易供补单', async () => {
    storekit.purchase.mockResolvedValue({
      transactionId: '2000000987654321',
      originalTransactionId: '2000000987654321',
      productId: 'fun.yunle.apps.member_year',
      jws: 'sandbox-jws',
    })
    callFunction.mockRejectedValue(new Error('交易不存在'))

    const iap = useIap()
    const purchased = await iap.purchase('fun.yunle.apps.member_year')

    expect(purchased).toBe(false)
    expect(iap.phase.value).toBe('fail')
    expect(iap.errorMessage.value).toBe('交易不存在')
    expect(storekit.finishTransaction).not.toHaveBeenCalled()
    expect(refresh).not.toHaveBeenCalled()
  })
})
