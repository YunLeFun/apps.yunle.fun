import type { AppRecord } from '../../app/types/app'
import type { ApplicationAcquisitionDependencies } from '../../server/utils/application-acquisition'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { hasApplicationPurchase, readApplicationAcquisitionInput, resolveApplicationAcquisition } from '../../server/utils/application-acquisition'

const app = { _id: 'record-one', name: '示例应用', coinCost: 10, accessMode: 'public', isPublic: true } as AppRecord
const input = { action: 'check', appId: app._id } as const
function rig(overrides: Partial<AppRecord> = {}) {
  let owned = false
  const account = { coin: 100, membership: { isActive: false, expireAt: null as number | null } }
  const deps = {
    application: vi.fn(async () => ({ ...app, ...overrides })),
    account: vi.fn(async () => account),
    purchased: vi.fn(async () => owned),
    deduct: vi.fn(async () => {
      owned = true
      return { balance: 90, deduped: false }
    }),
    now: () => 1000,
  } satisfies ApplicationAcquisitionDependencies
  return { deps, account, own: () => {
    owned = true
  } }
}
describe('native application acquisition', () => {
  it('only checks rights until an explicit purchase is confirmed', async () => {
    const { deps } = rig()
    expect(await resolveApplicationAcquisition('alice', input, deps)).toMatchObject({ state: 'purchase_required', coinCost: 10, balance: 100 })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('preserves a historic canonical purchase even when balance is now zero', async () => {
    const { deps, account, own } = rig()
    own()
    account.coin = 0
    expect(await resolveApplicationAcquisition('alice', input, deps)).toMatchObject({ state: 'allowed', reason: 'purchased' })
    expect(deps.purchased).toHaveBeenCalledWith('alice', 'record-one')
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('uses the published price and the existing permanent purchase key', async () => {
    const { deps } = rig()
    const result = await resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)
    expect(result).toMatchObject({ state: 'allowed', reason: 'purchased', balance: 90 })
    expect(deps.deduct).toHaveBeenCalledExactlyOnceWith('record-one', 10, 'purchase:record-one')
    expect(deps.purchased).toHaveBeenCalledTimes(2)
  })
  it('rejects a changed price before spending anything', async () => {
    const { deps } = rig({ coinCost: 20 })
    await expect(resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)).rejects.toMatchObject({ statusCode: 409 })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('does not charge after another device has already acquired the same app', async () => {
    const { deps, own } = rig()
    own()
    expect(await resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)).toMatchObject({ reason: 'purchased' })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('does not charge a current member', async () => {
    const { deps, account } = rig()
    account.membership = { isActive: true, expireAt: 2000 }
    expect(await resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)).toMatchObject({ reason: 'member' })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('does not replace a membership requirement with an old purchase', async () => {
    const { deps, own } = rig({ requiresMembership: true })
    own()
    expect(await resolveApplicationAcquisition('alice', input, deps)).toMatchObject({ state: 'membership_required' })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('does not replace an invitation with membership or payment', async () => {
    const { deps, account, own } = rig({ accessMode: 'invite_only' })
    own()
    account.membership = { isActive: true, expireAt: 2000 }
    expect(await resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)).toMatchObject({ state: 'invitation_required' })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('keeps insufficient funds distinct from an unavailable account service', async () => {
    const { deps, account } = rig()
    account.coin = 1
    await expect(resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)).rejects.toMatchObject({ statusCode: 409 })
    expect(deps.deduct).not.toHaveBeenCalled()
    deps.account.mockRejectedValueOnce(new Error('outage'))
    await expect(resolveApplicationAcquisition('alice', input, deps)).rejects.toThrow('outage')
  })
  it('does not claim success without an authoritative consume record', async () => {
    const { deps } = rig()
    deps.deduct.mockResolvedValueOnce({ balance: 90, deduped: false })
    await expect(resolveApplicationAcquisition('alice', { ...input, action: 'purchase', expectedCoinCost: 10 }, deps)).rejects.toMatchObject({ statusCode: 503 })
  })
  it.each([-1, 1.5, Number.NaN, Number.MAX_SAFE_INTEGER + 1])('rejects invalid server price %s', async (coinCost) => {
    const { deps } = rig({ coinCost })
    await expect(resolveApplicationAcquisition('alice', input, deps)).rejects.toMatchObject({ statusCode: 503 })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('rejects expired-but-active membership snapshots instead of waiving payment', async () => {
    const { deps, account } = rig()
    account.membership = { isActive: true, expireAt: 999 }
    await expect(resolveApplicationAcquisition('alice', input, deps)).rejects.toMatchObject({ statusCode: 503 })
    expect(deps.deduct).not.toHaveBeenCalled()
  })
  it('does not acquire an unpublished record or an ambiguous alias', async () => {
    const { deps } = rig({ _id: 'different-record' })
    await expect(resolveApplicationAcquisition('alice', input, deps)).rejects.toMatchObject({ statusCode: 404 })
    expect(deps.account).not.toHaveBeenCalled()
  })
  it.each([
    { ...input, uid: 'victim' },
    { ...input, amount: 1 },
    { ...input, bizId: 'purchase:other' },
    { ...input, action: 'purchase' },
    { ...input, action: 'purchase', expectedCoinCost: true },
    { ...input, appId: '../private' },
    { ...input, action: { toString: 'check' } },
  ])('rejects caller-selected authority fields %s', (value) => {
    expect(() => readApplicationAcquisitionInput(value)).toThrow()
  })
})

describe('historic purchase ownership lookup', () => {
  const get = vi.fn()
  const limit = vi.fn(() => ({ get }))
  const where = vi.fn(() => ({ limit }))
  const collection = vi.fn(() => ({ where }))
  const db = { collection } as unknown as Parameters<typeof hasApplicationPurchase>[2]
  beforeEach(() => {
    vi.clearAllMocks()
  })
  it('reads only the verified account and canonical legacy ref key', async () => {
    get.mockResolvedValue({ data: [] })
    expect(await hasApplicationPurchase('alice', 'record-one', db)).toBe(false)
    expect(collection).toHaveBeenCalledWith('coin_transactions')
    expect(where).toHaveBeenCalledWith({ userId: 'alice', refId: 'purchase:record-one', type: 'consume' })
    expect(limit).toHaveBeenCalledWith(2)
  })
  it('rejects an owner mismatch or malformed balance entry', async () => {
    for (const row of [
      { userId: 'bob', appId: 'record-one', refId: 'purchase:record-one', type: 'consume', amount: -10 },
      { userId: 'alice', appId: 'record-one', refId: 'purchase:record-one', type: 'consume', amount: 0 },
    ]) {
      get.mockResolvedValue({ data: [row] })
      await expect(hasApplicationPurchase('alice', 'record-one', db)).rejects.toMatchObject({ statusCode: 503 })
    }
  })
  it('rejects a failed query instead of assuming not purchased', async () => {
    get.mockResolvedValue({ code: 'DB_UNAVAILABLE', data: [] })
    await expect(hasApplicationPurchase('alice', 'record-one', db)).rejects.toMatchObject({ statusCode: 503 })
  })
})
