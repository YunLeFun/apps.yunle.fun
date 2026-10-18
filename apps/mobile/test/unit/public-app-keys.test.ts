import { beforeEach, describe, expect, it, vi } from 'vitest'

const fixture = vi.hoisted(() => ({
  resolve: vi.fn(),
  apps: [
    { _id: 'record-one', marketShortName: 'public-one', slug: 'shared-local-slug', name: '公开应用一' },
    { _id: 'record-two', marketShortName: 'public-two', slug: 'shared-local-slug', name: '公开应用二' },
  ],
}))
vi.mock('../../server/utils/cloudbase-admin', () => ({ useCloudbaseAdmin: () => ({ db: {} }) }))
vi.mock('../../server/domain/catalog/cloudbase', () => ({
  createCloudbaseCatalogResolver: () => ({ resolveCatalog: fixture.resolve }),
  catalogAppViewToRecord: (app: unknown) => app,
}))

describe('public application key resolution', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    fixture.resolve.mockResolvedValue({ apps: fixture.apps })
  })
  it('resolves an entire report list from one public snapshot without choosing workshop slugs', async () => {
    const { getPublicAppsByKeys } = await import('../../server/utils/public-apps')
    const records = await getPublicAppsByKeys(['record-one', 'PUBLIC-TWO', 'shared-local-slug', 'removed', 'record-one'])
    expect([...records.keys()]).toEqual(['record-one', 'PUBLIC-TWO'])
    expect(records.get('PUBLIC-TWO')?.name).toBe('公开应用二')
    expect(fixture.resolve).toHaveBeenCalledExactlyOnceWith({ surface: 'public_market' }, null)
  })
  it('keeps the single-key endpoint on the same public identity rules', async () => {
    const { getPublicAppByKey } = await import('../../server/utils/public-apps')
    expect(await getPublicAppByKey('shared-local-slug')).toBeNull()
    expect((await getPublicAppByKey('public-one'))?._id).toBe('record-one')
  })
})
