import type { H3Event } from 'h3'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const fixture = vi.hoisted(() => ({
  resolve: vi.fn(),
  featured: [] as unknown[],
  weekly: [] as unknown[],
  failure: null as Error | null,
}))
vi.mock('../../server/domain/catalog/cloudbase', () => ({
  createCloudbaseCatalogResolver: () => ({ resolveCatalog: fixture.resolve }),
}))
vi.mock('../../server/utils/cloudbase-admin', () => ({
  useCloudbaseAdmin: () => ({
    db: {
      collection: (name: string) => {
        interface Query {
          where: (condition: unknown) => Query
          orderBy: (field: string, direction: string) => Query
          limit: (value: number) => Query
          get: () => Promise<{ data: unknown[] }>
        }
        const query: Query = {
          where: () => query,
          orderBy: () => query,
          limit: () => query,
          get: async () => {
            if (fixture.failure)
              throw fixture.failure
            return { data: name === 'featured_apps' ? fixture.featured : fixture.weekly }
          },
        }
        return query
      },
    },
  }),
}))
vi.stubGlobal('defineEventHandler', (handler: (event: H3Event) => unknown) => handler)

const now = Date.parse('2026-10-28T03:00:00Z')
const weekStart = Date.parse('2026-10-25T16:00:00Z')

function eventFor() {
  const headers = new Map<string, unknown>()
  const event = { node: { res: { setHeader: (key: string, value: unknown) => headers.set(key, value) } } } as unknown as H3Event
  return { event, headers }
}

describe('public workshop discovery', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.useFakeTimers()
    vi.setSystemTime(now)
    fixture.featured = []
    fixture.weekly = []
    fixture.failure = null
    fixture.resolve.mockResolvedValue({ apps: [{ _id: 'approved', slug: 'public-slug', marketShortName: 'public-key' }] })
  })
  afterEach(() => vi.useRealTimers())

  it('returns only current approved references and never copies editorial application metadata', async () => {
    fixture.featured = [
      { appId: 'private', type: 'daily', isActive: true, startDate: now - 1, endDate: now + 1 },
      { appId: 'public-slug', type: 'editor', isActive: true, startDate: now - 1, endDate: now + 1, title: ' 编辑标题 ', websiteUrl: 'https://private.invalid', _openid: 'owner-secret' },
      { appId: 'public-key', type: 'daily', isActive: true, startDate: now - 1, endDate: now + 1 },
      { appId: 'approved', type: 'daily', isActive: true, startDate: 0, endDate: now - 1 },
    ]
    const { default: handler } = await import('../../server/api/catalog/discovery.get')
    const { event, headers } = eventFor()
    await expect(handler(event)).resolves.toEqual({ schemaVersion: 1, generatedAt: now, weeklyChart: null, featured: [{ appId: 'approved', title: '编辑标题', subtitle: undefined, startsAt: now - 1, expiresAt: now + 1 }] })
    expect(headers.get('Cache-Control')).toBe('no-store')
    expect(fixture.resolve).toHaveBeenCalledExactlyOnceWith({ surface: 'public_market' }, null)
  })

  it('keeps real current-week ranks without renumbering after inaccessible entries are removed', async () => {
    fixture.weekly = [
      { appId: 'private', weekStart, rank: 1 },
      { appId: 'public-key', weekStart, rank: 3 },
      { appId: 'approved', weekStart, rank: 4 },
      { appId: 'approved', weekStart: weekStart - 7 * 86_400_000, rank: 2 },
    ]
    const { default: handler } = await import('../../server/api/catalog/discovery.get')
    await expect(handler(eventFor().event)).resolves.toMatchObject({
      featured: [],
      weeklyChart: { weekStart, items: [{ appId: 'approved', rank: 3 }] },
    })
  })

  it('does not turn empty editorial collections into a fabricated popularity chart', async () => {
    const { default: handler } = await import('../../server/api/catalog/discovery.get')
    await expect(handler(eventFor().event)).resolves.toEqual({ schemaVersion: 1, generatedAt: now, featured: [], weeklyChart: null })
  })

  it('does not expose ambiguous aliases or treat an upstream failure as an empty success', async () => {
    fixture.resolve.mockResolvedValue({ apps: [{ _id: 'one', slug: 'same' }, { _id: 'two', slug: 'same' }] })
    fixture.featured = [{ appId: 'same', type: 'daily', isActive: true, startDate: 0, endDate: now + 1 }]
    const { default: handler } = await import('../../server/api/catalog/discovery.get')
    await expect(handler(eventFor().event)).resolves.toMatchObject({ featured: [], weeklyChart: null })
    fixture.failure = new Error('editorial unavailable')
    await expect(handler(eventFor().event)).rejects.toThrow('editorial unavailable')
  })
})
