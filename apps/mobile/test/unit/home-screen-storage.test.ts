import type { CloudbaseAdminDb } from '../../server/utils/cloudbase-admin'
import { describe, expect, it, vi } from 'vitest'
import { homeDocumentId, remoteHome } from '../../server/domain/home-screen'
import { getHomeScreen, putHomeScreen } from '../../server/utils/home-screen'

const owner = 'test-owner'
const config = { installedApps: [{ appId: 'original' }], dockApps: [], recentApps: [] }
const legacy = { _id: 'legacy', _openid: owner, ...config, updatedAt: 100, createdAt: 1 }
const mutationId = '00000000-0000-4000-8000-000000000001'

function storage(initial: Record<string, unknown>[] = []) {
  const records = new Map(initial.map(record => [String(record._id), structuredClone(record)]))
  let beforeTransaction: (() => void) | undefined
  const queries: unknown[] = []
  const writes = vi.fn(async (id: string, payload: Record<string, unknown>): Promise<{ updated?: number, code?: string }> => {
    records.set(id, { ...structuredClone(payload), _id: id })
    return { updated: 1 }
  })
  const transaction = {
    collection: () => ({
      doc: (id: string) => ({
        get: async () => ({ data: records.has(id) ? [structuredClone(records.get(id))] : [] }),
        set: (payload: Record<string, unknown>) => writes(id, payload),
      }),
    }),
  }
  let queue: Promise<unknown> = Promise.resolve()
  const db = {
    collection: () => ({
      where: (query: { _openid: string }) => {
        queries.push(query)
        return { limit: () => ({ get: async () => ({ data: [...records.values()].filter(record => record._openid === query._openid) }) }) }
      },
    }),
    runTransaction: vi.fn((callback: (transaction: unknown) => Promise<unknown>) => {
      const task = queue.then(async () => {
        beforeTransaction?.()
        beforeTransaction = undefined
        return callback(transaction)
      })
      queue = task.then(() => undefined, () => undefined)
      return task
    }),
  }
  return {
    db: db as unknown as CloudbaseAdminDb,
    records,
    writes,
    queries,
    beforeTransaction: (action: () => void) => { beforeTransaction = action },
  }
}

describe('home screen CloudBase storage adapter', () => {
  it('derives the query owner from the verified identity and projects only configuration', async () => {
    const store = storage([legacy, { ...legacy, _id: 'foreign', _openid: 'other-owner' }])
    const remote = await getHomeScreen(owner, store.db)
    expect(store.queries).toEqual([{ _openid: owner }])
    expect(remote.configuration.installedApps).toEqual(config.installedApps)
    expect(JSON.stringify(remote)).not.toContain('other-owner')
    expect(remote).not.toHaveProperty('_openid')
  })

  it('re-reads known documents inside the transaction before accepting a revision', async () => {
    const store = storage([legacy])
    const base = await getHomeScreen(owner, store.db)
    store.beforeTransaction(() => store.records.set('legacy', { ...legacy, updatedAt: 101, installedApps: [] }))
    await expect(putHomeScreen(owner, { baseRevision: base.revision, mutationId, configuration: config }, store.db))
      .rejects
      .toMatchObject({ statusCode: 409, data: { code: 'HOME_CONFLICT' } })
    expect(store.writes).not.toHaveBeenCalled()
  })

  it('preserves legacy documents while using a deterministic destination for new writers', async () => {
    const store = storage([legacy])
    const before = structuredClone(legacy)
    const base = await getHomeScreen(owner, store.db)
    const saved = await putHomeScreen(owner, {
      baseRevision: base.revision,
      mutationId,
      configuration: { ...config, installedApps: [] },
      _openid: 'victim',
    }, store.db)
    expect(store.records.get('legacy')).toEqual(before)
    expect(store.records.get(homeDocumentId(owner))).toMatchObject({ _openid: owner, installedApps: [] })
    expect(saved.configuration.installedApps).toEqual([])
    expect(store.records.has(homeDocumentId('victim'))).toBe(false)
  })

  it('serializes simultaneous empty-base writes without creating two native records', async () => {
    const store = storage()
    const write = { baseRevision: null, mutationId, configuration: config }
    const results = await Promise.allSettled([
      putHomeScreen(owner, write, store.db),
      putHomeScreen(owner, { ...write, mutationId: '00000000-0000-4000-8000-000000000002' }, store.db),
    ])
    expect(results.map(result => result.status)).toEqual(['fulfilled', 'rejected'])
    expect(store.records.size).toBe(1)
    const saved = store.records.get(homeDocumentId(owner))!
    expect(remoteHome({ ...legacy, ...saved })).toMatchObject({ configuration: { installedApps: config.installedApps } })
  })

  it('does not overwrite malformed history or foreign deterministic documents', async () => {
    const broken = storage([{ ...legacy, installedApps: 'broken' }])
    await expect(putHomeScreen(owner, { baseRevision: null, mutationId, configuration: config }, broken.db)).rejects.toMatchObject({ statusCode: 409 })
    expect(broken.writes).not.toHaveBeenCalled()
    const foreign = storage([{ ...legacy, _id: homeDocumentId(owner), _openid: 'foreign-owner' }])
    await expect(putHomeScreen(owner, { baseRevision: null, mutationId, configuration: config }, foreign.db)).rejects.toMatchObject({ statusCode: 409 })
    expect(foreign.writes).not.toHaveBeenCalled()
  })

  it('keeps folders through a whole-document write from a client without folder support', async () => {
    const withFolders = { ...legacy, installedApps: [{ appId: 'original' }, { appId: 'second' }], folders: [{ id: 'f', name: '收藏', appIds: ['original', 'second'] }] }
    const store = storage([withFolders])
    const base = await getHomeScreen(owner, store.db)
    expect(base.configuration).not.toHaveProperty('folders')
    await putHomeScreen(owner, {
      baseRevision: base.revision,
      mutationId,
      configuration: { ...config, installedApps: [{ appId: 'second' }] },
    }, store.db)
    expect(store.records.get(homeDocumentId(owner))).toMatchObject({ folders: [{ id: 'f', name: '收藏', appIds: ['second'] }] })
    const upgraded = await getHomeScreen(owner, store.db, 2)
    expect(upgraded).toMatchObject({ schemaVersion: 2, configuration: { folders: [{ id: 'f', appIds: ['second'] }] } })
  })

  it('does not acknowledge a non-throwing SDK write error as success', async () => {
    const store = storage()
    store.writes.mockResolvedValueOnce({ code: 'SERVICE_ERROR' })
    await expect(putHomeScreen(owner, { baseRevision: null, mutationId, configuration: config }, store.db))
      .rejects
      .toMatchObject({ statusCode: 503 })
    expect(store.records.size).toBe(0)
  })
})
