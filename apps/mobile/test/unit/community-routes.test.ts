import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const fixtures = vi.hoisted(() => ({ queries: [] as Record<string, unknown>[], admin: vi.fn() }))
vi.mock('../../server/utils/cloudbase-admin', () => ({ useCloudbaseAdmin: fixtures.admin }))
vi.mock('../../server/utils/public-apps', () => ({
  getPublicAppByKey: vi.fn(async () => ({ _id: 'app-ai-sfc', marketShortName: 'ai-sfc' })),
  getPublicAppsByKeys: vi.fn(async (keys: string[]) => new Map(keys.map(key => [key, { name: 'AI 春联' }]))),
}))

describe('review and report HTTP identity boundaries', () => {
  const nativeFetch = globalThis.fetch
  let server: ReturnType<typeof createServer>
  let origin: string
  const review = {
    _id: 'review-one',
    appKey: 'ai-sfc',
    uid: 'verified-user',
    authorName: '用户',
    rating: 5,
    content: '使用体验',
    status: 'published',
    createdAt: 1800000000000,
    updatedAt: 1800000000000,
  }
  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'test-env' } }))
    const getReviews = (await import('../../server/api/reviews/index.get')).default
    const postReview = (await import('../../server/api/reviews/index.post')).default
    const deleteReview = (await import('../../server/api/reviews/[id].delete')).default
    const getReports = (await import('../../server/api/reports/index.get')).default
    const postReport = (await import('../../server/api/reports/index.post')).default
    const app = createApp()
    app.use('/api/reviews', defineEventHandler(event => event.method === 'POST'
      ? postReview(event)
      : event.method === 'DELETE' ? deleteReview(event) : getReviews(event)))
    app.use('/api/reports', defineEventHandler(event => event.method === 'POST' ? postReport(event) : getReports(event)))
    server = createServer(toNodeListener(app))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  beforeEach(async () => {
    vi.clearAllMocks()
    fixtures.queries = []
    const { clearCloudbaseAuthCache } = await import('../../server/utils/cloudbase-auth')
    clearCloudbaseAuthCache()
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const token = new Headers(init?.headers).get('authorization')
      return token === 'Bearer valid-test'
        ? new Response(JSON.stringify({ sub: 'verified-user', status: 'ACTIVE' }))
        : new Response('{}', { status: 401 })
    }))
    fixtures.admin.mockReturnValue({ db: {
      command: { aggregate: { sum: () => 'sum' } },
      collection: (name: string) => ({
        where: (query: Record<string, unknown>) => {
          fixtures.queries.push(query)
          const chain = {
            orderBy: () => chain,
            limit: () => chain,
            get: async () => ({ data: name === 'app_reviews'
              ? [review]
              : [{ _id: 'report-one', targetType: 'app', targetId: 'ai-sfc', appKey: 'ai-sfc', reason: 'spam', status: 'open', createdAt: 1800000000000, uid: 'verified-user', moderation: 'PRIVATE', handledBy: 'PRIVATE' }] }),
          }
          return chain
        },
        aggregate: () => {
          const chain = { match: () => chain, group: () => chain, end: async () => ({ data: [{ _id: 5, count: 1 }] }) }
          return chain
        },
      }),
    } })
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })
  it('lets a visitor read public reviews without querying a private user', async () => {
    const response = await nativeFetch(`${origin}/api/reviews?appKey=ai-sfc`)
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    const body = await response.json()
    expect(body.data.myReview).toBeNull()
    expect(body.data.reviews[0]).not.toHaveProperty('uid')
    expect(fetch).not.toHaveBeenCalled()
  })
  it('does not downgrade invalid credentials to a successful visitor response', async () => {
    const response = await nativeFetch(`${origin}/api/reviews?appKey=ai-sfc`, { headers: { Authorization: 'Bearer invalid-test' } })
    expect(response.status).toBe(401)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.admin).not.toHaveBeenCalled()
  })
  it('requires login before reading any report history', async () => {
    const response = await nativeFetch(`${origin}/api/reports`)
    expect(response.status).toBe(401)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(fixtures.admin).not.toHaveBeenCalled()
    expect(fetch).not.toHaveBeenCalled()
  })
  it('queries the verified account and ignores a caller-selected UID', async () => {
    const response = await nativeFetch(`${origin}/api/reviews?appKey=ai-sfc&uid=victim`, { headers: { Authorization: 'Bearer valid-test' } })
    expect(response.status).toBe(200)
    expect((await response.json()).data.myReview.uid).toBe('verified-user')
    expect(fixtures.queries).toContainEqual({ appKey: 'ai-sfc', uid: 'verified-user' })
    expect(fixtures.queries.some(query => query.uid === 'victim')).toBe(false)
  })
  it('returns only safe fields from the current users report history', async () => {
    const response = await nativeFetch(`${origin}/api/reports?uid=victim`, { headers: { Authorization: 'Bearer valid-test' } })
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    const body = await response.json()
    expect(body.data.reports).toHaveLength(1)
    expect(body.data.reports[0].appName).toBe('AI 春联')
    expect(body.data.reports[0]).not.toHaveProperty('moderation')
    expect(body.data.reports[0]).not.toHaveProperty('handledBy')
    expect(body.data.reports[0]).not.toHaveProperty('uid')
    expect(fixtures.queries).toContainEqual({ uid: 'verified-user' })
  })
  it('denies all writes before database or moderation work and marks errors no-store', async () => {
    for (const [path, method] of [['reviews', 'POST'], ['reviews/review-one', 'DELETE'], ['reports', 'POST']] as const) {
      const response = await nativeFetch(`${origin}/api/${path}`, { method, body: method === 'POST' ? '{}' : undefined })
      expect(response.status).toBe(401)
      expect(response.headers.get('cache-control')).toBe('private, no-store')
    }
    expect(fixtures.admin).not.toHaveBeenCalled()
  })
})
