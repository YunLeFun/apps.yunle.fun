import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, createRouter, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const fixtures = vi.hoisted(() => ({ resolve: vi.fn() }))
vi.mock('../../server/domain/catalog/cloudbase', () => ({
  createCloudbaseCatalogResolver: () => ({ resolveCatalog: fixtures.resolve }),
  catalogAppViewToRecord: (app: unknown) => app,
}))

describe('workshop native identity boundary', () => {
  const nativeFetch = globalThis.fetch
  let server: ReturnType<typeof createServer>
  let origin: string
  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'test-env' } }))
    const route = (await import('../../server/api/workshops/[id].get')).default
    const middleware = (await import('../../server/middleware/workshop-no-store')).default
    const app = createApp()
    app.use(middleware)
    app.use(createRouter().get('/api/workshops/:id', route))
    server = createServer(toNodeListener(app))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  beforeEach(async () => {
    vi.clearAllMocks()
    const { clearCloudbaseAuthCache } = await import('../../server/utils/cloudbase-auth')
    clearCloudbaseAuthCache()
    fixtures.resolve.mockResolvedValue({ surface: 'workshop', access: 'anonymous', workshop: { _id: 'ABC234' }, apps: [] })
    vi.stubGlobal('fetch', vi.fn(async (_url: unknown, init?: RequestInit) => {
      const token = new Headers(init?.headers).get('authorization')
      if (token === 'Bearer valid-test')
        return new Response(JSON.stringify({ sub: 'verified-user', status: 'ACTIVE' }))
      if (token === 'Bearer anonymous-test')
        return new Response(JSON.stringify({ sub: 'anonymous-user', status: 'ACTIVE', is_anonymous: true }))
      if (token === 'Bearer suspended-test')
        return new Response(JSON.stringify({ sub: 'suspended-user', status: 'SUSPENDED' }))
      if (token === 'Bearer offline-test')
        return new Response('{}', { status: 503 })
      return new Response('{}', { status: 401 })
    }))
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })
  it('keeps anonymous lookup public and no-store', async () => {
    const result = await nativeFetch(`${origin}/api/workshops/abc234`)
    expect(result.status).toBe(200)
    expect(result.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.resolve).toHaveBeenCalledWith({ surface: 'workshop', workshopId: 'ABC234' }, null)
    expect(fetch).not.toHaveBeenCalled()
  })
  it('does not silently downgrade expired credentials into a visitor membership', async () => {
    const result = await nativeFetch(`${origin}/api/workshops/ABC234`, { headers: { Authorization: 'Bearer invalid-test' } })
    expect(result.status).toBe(401)
    expect(result.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.resolve).not.toHaveBeenCalled()
  })
  it('passes only the verified registered UID to the catalog resolver', async () => {
    const result = await nativeFetch(`${origin}/api/workshops/ABC234?uid=client-forgery`, { headers: { Authorization: 'Bearer valid-test' } })
    expect(result.status).toBe(200)
    expect(fixtures.resolve).toHaveBeenCalledWith({ surface: 'workshop', workshopId: 'ABC234' }, { uid: 'verified-user' })
  })
  it.each(['anonymous-test', 'suspended-test'])('denies an ineligible authenticated identity: %s', async (token) => {
    const result = await nativeFetch(`${origin}/api/workshops/ABC234`, { headers: { Authorization: `Bearer ${token}` } })
    expect(result.status).toBe(403)
    expect(result.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.resolve).not.toHaveBeenCalled()
  })
  it('keeps identity upstream outages distinct from expired sessions', async () => {
    const result = await nativeFetch(`${origin}/api/workshops/ABC234`, { headers: { Authorization: 'Bearer offline-test' } })
    expect(result.status).toBe(503)
    expect(result.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.resolve).not.toHaveBeenCalled()
  })
  it('does not resolve invalid workshop IDs and still disables caching', async () => {
    const result = await nativeFetch(`${origin}/api/workshops/AB0123`)
    expect(result.status).toBe(404)
    expect(result.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.resolve).not.toHaveBeenCalled()
  })
})
