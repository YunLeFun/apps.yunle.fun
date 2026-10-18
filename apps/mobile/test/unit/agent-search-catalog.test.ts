import { beforeEach, describe, expect, it, vi } from 'vitest'

const source = vi.hoisted(() => ({ resolve: vi.fn(), db: {} }))
vi.mock('../../server/domain/catalog/cloudbase', () => ({
  createCloudbaseCatalogResolver: (db: unknown) => {
    expect(db).toBe(source.db)
    return { resolveCatalog: source.resolve }
  },
  catalogAppViewToRecord: (view: unknown) => view,
}))
describe('agent search uses approved public revisions', () => {
  beforeEach(() => {
    source.resolve.mockResolvedValue({ apps: [{
      _id: 'canonical-id',
      slug: 'local-slug',
      marketShortName: 'published-key',
      name: '已发布工具',
      isPublic: true,
      status: 'approved',
      publicationStatus: 'published',
    }] })
  })
  it('searches the public market snapshot rather than mutable owner metadata', async () => {
    const { searchApps } = await import('../../server/utils/agent-search-apps')
    const results = await searchApps({ query: '工具' }, { db: source.db as never })
    expect(source.resolve).toHaveBeenCalledWith({ surface: 'public_market' }, null)
    expect(results).toMatchObject([{ id: 'canonical-id', slug: 'published-key', name: '已发布工具' }])
  })
  it('does not treat unpublished current content as a second source', async () => {
    source.resolve.mockResolvedValue({ apps: [] })
    const { searchApps } = await import('../../server/utils/agent-search-apps')
    expect(await searchApps({ query: '待审草稿' }, { db: source.db as never })).toEqual([])
  })
})
