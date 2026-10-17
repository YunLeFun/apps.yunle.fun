import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const services = vi.hoisted(() => ({
  get: vi.fn(),
  put: vi.fn(),
}))
vi.mock('../../server/utils/home-screen', () => ({
  getHomeScreen: services.get,
  putHomeScreen: services.put,
}))

describe('home screen authenticated HTTP routes', () => {
  const nativeFetch = globalThis.fetch
  let server: ReturnType<typeof createServer>
  let origin: string
  let status = 'ACTIVE'

  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'test-env' } }))
    const get = (await import('../../server/api/home-screen/index.get')).default
    const put = (await import('../../server/api/home-screen/index.put')).default
    const app = createApp()
    app.use('/api/home-screen', defineEventHandler(event => event.method === 'PUT' ? put(event) : get(event)))
    server = createServer(toNodeListener(app))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  beforeEach(async () => {
    vi.clearAllMocks()
    status = 'ACTIVE'
    const { clearCloudbaseAuthCache } = await import('../../server/utils/cloudbase-auth')
    clearCloudbaseAuthCache()
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ sub: 'verified-user', status }), {
      headers: { 'Content-Type': 'application/json' },
    })))
    services.get.mockResolvedValue({ schemaVersion: 1, revision: null, configuration: { installedApps: [], dockApps: [], recentApps: [], updatedAt: 0 } })
    services.put.mockResolvedValue({ saved: true })
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })

  it('returns no-store 401 without a token and does not query private data', async () => {
    const response = await nativeFetch(`${origin}/api/home-screen`)
    expect(response.status).toBe(401)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(services.get).not.toHaveBeenCalled()
    expect(fetch).not.toHaveBeenCalled()
  })
  it('uses the verified identity rather than a query UID', async () => {
    const response = await nativeFetch(`${origin}/api/home-screen?uid=victim`, { headers: { Authorization: 'Bearer test-only' } })
    expect(response.status).toBe(200)
    expect(services.get).toHaveBeenCalledWith('verified-user', undefined, 1)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
  })
  it('serves schema 2 (folders) only to clients that ask for it', async () => {
    await nativeFetch(`${origin}/api/home-screen?schema=2`, { headers: { Authorization: 'Bearer test-only' } })
    expect(services.get).toHaveBeenCalledWith('verified-user', undefined, 2)
    await nativeFetch(`${origin}/api/home-screen?schema=9`, { headers: { Authorization: 'Bearer test-only' } })
    expect(services.get).toHaveBeenLastCalledWith('verified-user', undefined, 1)
  })
  it('binds a write to the verified account even when the body supplies a different UID', async () => {
    const body = { uid: 'victim', baseRevision: null, mutationId: 'test-only', configuration: {} }
    const response = await nativeFetch(`${origin}/api/home-screen`, {
      method: 'PUT',
      headers: { 'Authorization': 'Bearer test-only', 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    expect(response.status).toBe(200)
    expect(services.put).toHaveBeenCalledWith('verified-user', body)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
  })
  it('denies a BLOCKED account before either private service runs', async () => {
    status = 'BLOCKED'
    const response = await nativeFetch(`${origin}/api/home-screen`, { headers: { Authorization: 'Bearer test-only' } })
    expect(response.status).toBe(403)
    expect(services.get).not.toHaveBeenCalled()
    expect(services.put).not.toHaveBeenCalled()
  })
})
