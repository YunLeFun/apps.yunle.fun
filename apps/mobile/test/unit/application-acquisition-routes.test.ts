import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const state = vi.hoisted(() => ({
  application: vi.fn(),
  owned: false,
  ledgerGet: vi.fn(),
}))
vi.mock('../../server/utils/public-apps', () => ({ getPublicAppByKey: state.application }))
vi.mock('../../server/utils/cloudbase-admin', () => ({
  useCloudbaseAdmin: () => ({
    db: { collection: () => ({ where: () => ({ limit: () => ({ get: state.ledgerGet }) }) }) },
  }),
}))

describe('application acquisition authenticated route', () => {
  const nativeFetch = globalThis.fetch
  let server: ReturnType<typeof createServer>
  let origin: string
  let status = 'ACTIVE'
  const calls: { url: string, body: Record<string, unknown>, headers: Record<string, string>, redirect: string }[] = []
  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'fixture-env' } }))
    const route = (await import('../../server/api/apps/acquisition.post')).default
    const app = createApp()
    app.use('/api/apps/acquisition', route)
    server = createServer(toNodeListener(app))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  beforeEach(async () => {
    vi.clearAllMocks()
    calls.length = 0
    status = 'ACTIVE'
    state.owned = false
    const { clearCloudbaseAuthCache } = await import('../../server/utils/cloudbase-auth')
    clearCloudbaseAuthCache()
    state.application.mockResolvedValue({ _id: 'paid-app', name: '示例应用', coinCost: 10, requiresMembership: null, accessMode: 'public' })
    state.ledgerGet.mockImplementation(async () => ({ data: state.owned
      ? [{
          userId: 'verified-user',
          appId: 'paid-app',
          refId: 'purchase:paid-app',
          type: 'consume',
          amount: -10,
        }]
      : [] }))
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => {
      if (String(url).endsWith('/auth/v1/user/me'))
        return Response.json({ sub: 'verified-user', status })
      const body = JSON.parse(String(init.body))
      calls.push({ url: String(url), body, headers: init.headers as Record<string, string>, redirect: String(init.redirect) })
      if (body.action === 'getAccount')
        return Response.json({ coin: 100, membership: { isActive: false, expireAt: null } })
      state.owned = true
      return Response.json({ balance: 90, deduped: false })
    }))
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })
  const post = (body: unknown, token = 'fixture-only') => nativeFetch(`${origin}/api/apps/acquisition`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  })
  it('returns private no-store 401 before reading any private data', async () => {
    const response = await post({ action: 'check', appId: 'paid-app' }, '')
    expect(response.status).toBe(401)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fetch).not.toHaveBeenCalled()
    expect(state.application).not.toHaveBeenCalled()
  })
  it('checks rights without calling deductCoin', async () => {
    const response = await post({ action: 'check', appId: 'paid-app' })
    expect(response.status).toBe(200)
    expect(await response.json()).toMatchObject({ userId: 'verified-user', state: 'purchase_required', coinCost: 10 })
    expect(calls.map(v => v.body.action)).toEqual(['getAccount'])
    expect(response.headers.get('cache-control')).toBe('private, no-store')
  })
  it('delegates the verified bearer only to the fixed gateway and canonical purchase key', async () => {
    const response = await post({ action: 'purchase', appId: 'paid-app', expectedCoinCost: 10 })
    expect(response.status).toBe(200)
    expect(await response.json()).toMatchObject({ state: 'allowed', reason: 'purchased', balance: 90 })
    expect(calls[1]).toMatchObject({
      url: 'https://fixture-env.api.tcloudbasegateway.com/v1/functions/account-api',
      redirect: 'error',
      headers: { Authorization: 'Bearer fixture-only' },
      body: { action: 'deductCoin', appId: 'paid-app', amount: 10, bizId: 'purchase:paid-app' },
    })
    expect(calls[1].body).not.toHaveProperty('userId')
    expect(calls[1].body).not.toHaveProperty('serviceToken')
  })
  it('rejects a suspended account before invoking the ledger', async () => {
    status = 'BLOCKED'
    const response = await post({ action: 'purchase', appId: 'paid-app', expectedCoinCost: 10 })
    expect(response.status).toBe(403)
    expect(calls).toEqual([])
    expect(state.ledgerGet).not.toHaveBeenCalled()
  })
  it('rejects caller UID or price authority rather than forwarding it', async () => {
    const response = await post({ action: 'purchase', appId: 'paid-app', expectedCoinCost: 10, userId: 'victim', amount: 1 })
    expect(response.status).toBe(400)
    expect(calls).toEqual([])
  })
})
