import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, createRouter, defineEventHandler, setResponseHeader, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const fixtures = vi.hoisted(() => ({ admin: vi.fn(), queries: [] as Record<string, unknown>[], rows: [] as Record<string, unknown>[], listings: [] as Record<string, unknown>[], revisions: [] as Record<string, unknown>[], mutations: vi.fn() }))
vi.mock('../../server/utils/cloudbase-admin', () => ({ useCloudbaseAdmin: fixtures.admin }))

describe('native application management identity and cache boundaries', () => {
  const nativeFetch = globalThis.fetch
  let server: ReturnType<typeof createServer>
  let origin: string
  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'test-env' } }))
    const mine = (await import('../../server/api/apps/mine.get')).default
    const owned = (await import('../../server/api/apps/mine/[slug].get')).default
    const access = (await import('../../server/api/apps/access.get')).default
    const delist = (await import('../../server/api/apps/[id].delete')).default
    const submit = (await import('../../server/api/apps/submissions.post')).default
    const middleware = (await import('../../server/middleware/app-management-no-store')).default
    const router = createRouter()
      .get('/api/apps/mine', mine)
      .get('/api/apps/mine/:slug', owned)
      .get('/api/apps/access', access)
      .delete('/api/apps/:id', delist)
      .post('/api/apps/submissions', submit)
      .get('/api/apps/public', defineEventHandler((event) => {
        setResponseHeader(event, 'Cache-Control', 'public, max-age=30')
        return { items: [] }
      }))
    const app = createApp()
    app.use(middleware)
    app.use(router)
    server = createServer(toNodeListener(app))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  beforeEach(async () => {
    vi.clearAllMocks()
    fixtures.queries = []
    fixtures.rows = []
    fixtures.listings = []
    fixtures.revisions = []
    const { clearCloudbaseAuthCache } = await import('../../server/utils/cloudbase-auth')
    clearCloudbaseAuthCache()
    vi.stubGlobal('fetch', vi.fn(async (_url: unknown, init?: RequestInit) => {
      const token = new Headers(init?.headers).get('authorization')
      if (token === 'Bearer valid-test')
        return new Response(JSON.stringify({ sub: 'owner', status: 'ACTIVE', phone_number_verified: true }))
      if (token === 'Bearer unverified-test')
        return new Response(JSON.stringify({ sub: 'owner', status: 'ACTIVE', phone_number_verified: false }))
      if (token === 'Bearer anonymous-test')
        return new Response(JSON.stringify({ sub: 'owner', status: 'ACTIVE', is_anonymous: true }))
      if (token === 'Bearer suspended-test')
        return new Response(JSON.stringify({ sub: 'owner', status: 'SUSPENDED' }))
      if (token === 'Bearer offline-test')
        return new Response('{}', { status: 503 })
      return new Response('{}', { status: 401 })
    }))
    fixtures.admin.mockReturnValue({ db: {
      command: { in: (values: string[]) => ({ in: values }) },
      runTransaction: fixtures.mutations,
      collection: (name: string) => ({
        where: (query: Record<string, unknown>) => {
          fixtures.queries.push(query)
          const chain = { limit: () => chain, get: async () => ({ data: name === 'apps' ? fixtures.rows : name === 'public_market_listings' ? fixtures.listings : name === 'app_submissions' ? fixtures.revisions : [] }) }
          return chain
        },
        doc: () => ({ get: async () => ({ data: fixtures.rows[0] }) }),
      }),
    } })
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })
  it.each(['/api/apps/mine', '/api/apps/access', '/api/apps/mine/my-app'])('requires an identity and disables caching before failure: %s', async (path) => {
    const response = await nativeFetch(origin + path)
    expect(response.status).toBe(401)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.admin).not.toHaveBeenCalled()
  })
  it.each(['anonymous-test', 'suspended-test'])('does not expose private records to an ineligible identity: %s', async (token) => {
    const response = await nativeFetch(`${origin}/api/apps/mine`, { headers: { Authorization: `Bearer ${token}` } })
    expect(response.status).toBe(403)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.admin).not.toHaveBeenCalled()
  })
  it('scopes both canonical and legacy reads to the verified UID and hides conflicting legacy ownership', async () => {
    fixtures.rows = [
      { _id: 'canonical', name: 'Canonical', slug: 'canonical', ownerUid: 'owner', updatedAt: 30 },
      { _id: 'legacy', name: 'Legacy', slug: 'legacy', _openid: 'owner', updatedAt: 20 },
      { _id: 'transferred', name: 'Private to another owner', slug: 'other', ownerUid: 'other', _openid: 'owner', updatedAt: 40 },
    ]
    const response = await nativeFetch(`${origin}/api/apps/mine?ownerUid=client-forgery`, { headers: { Authorization: 'Bearer valid-test' } })
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.items.map((item: { _id: string }) => item._id)).toEqual(['canonical', 'legacy'])
    expect(fixtures.queries).toContainEqual({ ownerUid: 'owner' })
    expect(fixtures.queries).toContainEqual({ _openid: 'owner' })
    expect(response.headers.get('cache-control')).toBe('private, no-store')
  })
  it('keeps a newly saved projection when a different older revision is still under review', async () => {
    fixtures.rows = [{ _id: 'app-one', ownerUid: 'owner', name: 'New current name', slug: 'my-app', websiteUrl: 'https://new.yunle.fun/', currentRevisionId: 'new-revision', publishedSubmissionId: 'new-revision', activeSubmissionId: '', audience: 'public', publicationStatus: 'published', status: 'approved', updatedAt: 30 }]
    fixtures.listings = [{ _id: 'app-one', appId: 'app-one', status: 'unlisted', approvedRevisionId: '', activeSubmissionId: 'old-revision' }]
    fixtures.revisions = [{ _id: 'old-revision', appId: 'app-one', reviewStatus: 'pending', snapshot: { name: 'Old submitted name', websiteUrl: 'https://old.yunle.fun/' } }]
    const response = await nativeFetch(`${origin}/api/apps/mine`, { headers: { Authorization: 'Bearer valid-test' } })
    expect(response.status).toBe(200)
    const item = (await response.json()).items[0]
    expect(item.name).toBe('New current name')
    expect(item.websiteUrl).toBe('https://new.yunle.fun/')
    expect(item.currentRevisionId).toBe('new-revision')
    expect(item.ownerMetadataRevisionId).toBe('new-revision')
    expect(item.status).toBe('approved')
    expect(item.latestSubmission._id).toBe('old-revision')
    expect(item.latestSubmission.reviewStatus).toBe('pending')
  })
  it('does not let a former legacy owner delist an application with a different canonical owner', async () => {
    fixtures.rows = [{ _id: 'transferred', ownerUid: 'other', _openid: 'owner' }]
    const response = await nativeFetch(`${origin}/api/apps/transferred`, { method: 'DELETE', headers: { Authorization: 'Bearer valid-test' } })
    expect(response.status).toBe(403)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.mutations).not.toHaveBeenCalled()
  })
  it('lets unverified registered accounts read eligibility but not create or delist', async () => {
    const headers = { 'Authorization': 'Bearer unverified-test', 'Content-Type': 'application/json' }
    const access = await nativeFetch(`${origin}/api/apps/access`, { headers })
    expect(access.status).toBe(200)
    expect((await access.json()).canSubmitFirstParty).toBe(false)
    const create = await nativeFetch(`${origin}/api/apps/submissions`, { method: 'POST', headers, body: '{}' })
    const delist = await nativeFetch(`${origin}/api/apps/app-one`, { method: 'DELETE', headers })
    expect(create.status).toBe(403)
    expect(delist.status).toBe(403)
    expect(create.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.admin).not.toHaveBeenCalled()
  })
  it('keeps a CloudBase identity outage distinct from expired credentials', async () => {
    const response = await nativeFetch(`${origin}/api/apps/mine`, { headers: { Authorization: 'Bearer offline-test' } })
    expect(response.status).toBe(503)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.admin).not.toHaveBeenCalled()
  })
  it('does not apply private management policy to the public catalog', async () => {
    const response = await nativeFetch(`${origin}/api/apps/public`)
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('public, max-age=30')
    expect(fetch).not.toHaveBeenCalled()
  })
})
