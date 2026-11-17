import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  mounted: [] as Array<() => void | Promise<void>>,
  unmounted: [] as Array<() => void>,
  open: vi.fn(),
  returned: vi.fn(),
}))

vi.stubGlobal('openInAppBrowser', h.open)
vi.stubGlobal('onMounted', (callback: () => void | Promise<void>) => h.mounted.push(callback))
vi.stubGlobal('onUnmounted', (callback: () => void) => h.unmounted.push(callback))

const { usePaymentChannel, WWW_PRICING_URL, WWW_WALLET_URL } = await import('../../app/composables/usePaymentChannel')
let documentFixture: EventTarget & { visibilityState: string }

beforeEach(() => {
  vi.clearAllMocks()
  h.mounted.length = 0
  h.unmounted.length = 0
  documentFixture = Object.assign(new EventTarget(), { visibilityState: 'hidden' })
  vi.stubGlobal('document', documentFixture)
})

describe('online payment return', () => {
  it('keeps recharge and membership links attributed to Apps', () => {
    const payment = usePaymentChannel()
    payment.goRecharge()
    expect(h.open).toHaveBeenLastCalledWith(WWW_WALLET_URL)
    expect(WWW_WALLET_URL).toContain('from=apps')
    payment.goMembershipPurchase()
    expect(h.open).toHaveBeenLastCalledWith(WWW_PRICING_URL)
    expect(WWW_PRICING_URL).toContain('from=apps')
  })

  it('waits for the Web tab to become visible and removes its return listener on unmount', async () => {
    const payment = usePaymentChannel({ onReturn: h.returned })
    await h.mounted[0]!()
    payment.goMembershipPurchase()
    documentFixture.dispatchEvent(new Event('visibilitychange'))
    expect(h.returned).not.toHaveBeenCalled()
    documentFixture.visibilityState = 'visible'
    documentFixture.dispatchEvent(new Event('visibilitychange'))
    documentFixture.dispatchEvent(new Event('visibilitychange'))
    await Promise.resolve()
    expect(h.returned).toHaveBeenCalledOnce()
    h.unmounted[0]!()
    payment.goRecharge()
    documentFixture.dispatchEvent(new Event('visibilitychange'))
    expect(h.returned).toHaveBeenCalledOnce()
  })
})
