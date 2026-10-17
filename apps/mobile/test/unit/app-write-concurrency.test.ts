import type { AddressInfo } from 'node:net'
import type { AppRecord, AppSubmission, CreateAppForm } from '../../app/types/app'
import type { ServerAuthUser } from '../../server/utils/cloudbase-auth'
import { createServer } from 'node:http'
import { appendResponseHeader, createApp, createRouter, defineEventHandler, getRequestHeader, sendNoContent, setResponseHeader, setResponseHeaders, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { createAppSubmission, delistOwnedApp, listOwnedApps, submitOwnedAppToPublicMarket, updateAppSubmission } from '../../server/utils/app-submissions'
import { readOwnedApplicationState } from '../../server/utils/app-write-version'

const fixtures = vi.hoisted(() => ({ admin: vi.fn(), user: vi.fn() }))
vi.mock('../../server/utils/cloudbase-admin', () => ({ useCloudbaseAdmin: fixtures.admin }))
vi.mock('../../server/utils/cloudbase-auth', () => ({ requireVerifiedCloudbaseUser: fixtures.user }))

type Document = Record<string, unknown>
const user: ServerAuthUser = { uid: 'owner', anonymous: false, phoneVerified: true, accountStatus: 'active' }
const form: CreateAppForm = { name: 'My app', slug: 'my-app', websiteUrl: 'https://test.yunle.fun/', privacyPolicyUrl: 'https://test.yunle.fun/privacy', supportUrl: 'https://test.yunle.fun/support', isPublic: true, audience: 'public' }
const app: AppRecord = { _id: 'app-one', ownerUid: 'owner', ownerLogin: 'owner', ...form, status: 'approved', publicationStatus: 'published', currentRevisionId: 'revision-one', publishedSubmissionId: 'revision-one', activeSubmissionId: '', createdAt: 1, updatedAt: 1 }
const submission: AppSubmission = { _id: 'revision-one', appId: app._id, submitterUid: 'owner', revision: 1, kind: 'first_party', reviewStatus: 'draft', snapshot: form, ownership: { status: 'pending', checks: [] }, submittedAt: 1, createdAt: 1, updatedAt: 1 }

/** Optimistic document transactions: stage writes, reject conflicting commits, retry with a fresh snapshot. */
function database() {
  let records = new Map<string, Document>([['apps/app-one', { ...app }], ['app_submissions/revision-one', { ...submission }]])
  let epoch = 0
  let beforeTransaction: (() => void) | undefined
  let failCollection: string | undefined
  let commits = 0
  let attempts = 0
  const clone = (value: Document) => structuredClone(value)
  function collection(store: Map<string, Document>, name: string) {
    return {
      doc(id: string) {
        const key = `${name}/${id}`
        return {
          get: async () => ({ data: store.has(key) ? clone(store.get(key)!) : null }),
          set: async (value: Document) => {
            if (failCollection === name)
              throw new Error('fixture write failed')
            store.set(key, { ...clone(value), _id: id })
          },
          update: async (value: Document) => {
            if (failCollection === name)
              throw new Error('fixture write failed')
            if (!store.has(key))
              throw new Error('missing document')
            store.set(key, { ...store.get(key), ...clone(value) })
          },
        }
      },
      where(query: Document) {
        let sortKey: string | undefined
        let count = Infinity
        const rows = () => [...store.entries()].filter(([key, value]) => key.startsWith(`${name}/`) && Object.entries(query).every(([field, filter]) => {
          if (filter && typeof filter === 'object') {
            const op = filter as { in?: unknown[], gte?: number }
            return op.in ? op.in.includes(value[field]) : Number(value[field]) >= op.gte!
          }
          return value[field] === filter
        })).map(([, value]) => clone(value)).sort((a, b) => sortKey ? Number(b[sortKey]) - Number(a[sortKey]) : 0).slice(0, count)
        const chain = {
          limit: (n: number) => {
            count = n
            return chain
          },
          orderBy: (key: string) => {
            sortKey = key
            return chain
          },
          get: async () => ({ data: rows() }),
          count: async () => ({ total: rows().length }),
        }
        return chain
      },
    }
  }
  const db = {
    command: { in: (values: string[]) => ({ in: values }), gte: (value: number) => ({ gte: value }) },
    collection: (name: string) => collection(records, name),
    async runTransaction(callback: (transaction: { collection: typeof db.collection }) => Promise<unknown>) {
      beforeTransaction?.()
      beforeTransaction = undefined
      for (let retry = 0; retry < 4; retry++) {
        attempts++
        const version = epoch
        const snapshot = new Map([...records].map(([key, value]) => [key, clone(value)]))
        await callback({ collection: name => collection(snapshot, name) })
        if (version !== epoch)
          continue
        records = snapshot
        epoch++
        commits++
        return
      }
      throw new Error('DATABASE_TRANSACTION_CONFLICT')
    },
  }
  return {
    db,
    patch(key: string, value: Document) {
      records.set(key, { ...records.get(key), ...clone(value) })
      epoch++
    },
    read: (key: string) => records.get(key),
    dump: () => structuredClone([...records]),
    before(action: () => void) { beforeTransaction = action },
    failOn(name: string) { failCollection = name },
    get commits() { return commits },
    get attempts() { return attempts },
  }
}

describe('atomic owner publishing preconditions', () => {
  let memory: ReturnType<typeof database>
  let server: ReturnType<typeof createServer>
  let origin: string
  const token = async () => `"${(await readOwnedApplicationState(memory.db, app._id, user.uid)).writeVersion}"`
  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    for (const [name, fn] of Object.entries({ getRequestHeader, setResponseHeader, setResponseHeaders, appendResponseHeader, sendNoContent }))
      vi.stubGlobal(name, fn)
    const cors = (await import('../../server/middleware/cors')).default
    const update = (await import('../../server/api/apps/[id]/submissions.post')).default
    const market = (await import('../../server/api/apps/[id]/public-market.post')).default
    const delist = (await import('../../server/api/apps/[id].delete')).default
    const router = createRouter().post('/api/apps/:id/submissions', update).post('/api/apps/:id/public-market', market).delete('/api/apps/:id', delist)
    server = createServer(toNodeListener(createApp().use(cors).use(router)))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  beforeEach(() => {
    memory = database()
    fixtures.admin.mockReturnValue({ db: memory.db })
    fixtures.user.mockResolvedValue(user)
    vi.stubGlobal('useRuntimeConfig', () => ({}))
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>(resolve => server.close(() => resolve()))
  })
  it('permits conditional writes in the native shell CORS preflight', async () => {
    const response = await fetch(`${origin}/api/apps/app-one/submissions`, {
      method: 'OPTIONS',
      headers: { 'Origin': 'capacitor://localhost', 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization,content-type,if-match' },
    })
    expect(response.status).toBe(204)
    expect(response.headers.get('access-control-allow-origin')).toBe('capacitor://localhost')
    expect(response.headers.get('access-control-allow-headers')?.toLowerCase()).toContain('if-match')
  })
  it('keeps a save receipt on the new revision while the owner list shows the older review', async () => {
    seedListing()
    const saved = await updateAppSubmission(user, app._id, { ...form, name: 'New name' }, await token())
    const [owned] = await listOwnedApps(user)
    expect(owned!.latestSubmission?._id).toBe('older-review')
    expect(saved.app.latestSubmission?._id).toBe(saved.submission._id)
    expect(saved.app.name).toBe('New name')
    expect(saved.app.writeVersion).toBe(owned!.writeVersion)
    expect(saved.app.ownerMetadataRevisionId).toBe(saved.submission._id)
  })
  it('creates a private version with a usable owner precondition and a matching draft receipt', async () => {
    const created = await createAppSubmission(user, { ...form, slug: 'new-private', audience: 'owner', isPublic: false })
    expect(created.app).toMatchObject({ audience: 'owner', isPublic: false, currentRevisionId: created.submission._id, latestSubmission: { _id: created.submission._id, reviewStatus: 'draft' } })
    const current = await readOwnedApplicationState(memory.db, created.app._id, user.uid)
    expect(created.app.writeVersion).toBe(current.writeVersion)
    expect(memory.read(`apps/${created.app._id}`)).not.toHaveProperty('writeVersion')
    expect(memory.commits).toBe(1)
  })
  it('returns an owner token for the same persisted state regardless of projected review status', async () => {
    const [owned] = await listOwnedApps(user)
    expect(owned!.status).toBe('pending')
    expect(`"${owned!.writeVersion}"`).toBe(await token())
    expect(memory.read('apps/app-one')).not.toHaveProperty('writeVersion')
  })
  it('binds a legacy listing by document ID without changing the hashed persisted fields', async () => {
    seedListing()
    memory.patch('public_market_listings/app-one', { appId: undefined })
    const [owned] = await listOwnedApps(user)
    expect(owned!.yunlefunListing?.appId).toBe(app._id)
    expect(`"${owned!.writeVersion}"`).toBe(await token())
    await delistOwnedApp(user, app._id, await token())
    expect(memory.commits).toBe(1)
  })
  it('rejects a stale version even when the revision and timestamp are unchanged', async () => {
    const old = await token()
    memory.patch('apps/app-one', { audience: 'owner' })
    const before = memory.dump()
    await expect(updateAppSubmission(user, app._id, form, old)).rejects.toMatchObject({ statusCode: 412 })
    expect(memory.dump()).toEqual(before)
    expect(memory.commits).toBe(0)
  })
  it.each(['update', 'market', 'delist'] as const)('checks ownership again inside the %s transaction', async (operation) => {
    const version = await token()
    memory.before(() => memory.patch('apps/app-one', { ownerUid: 'another', _openid: 'owner' }))
    const action = operation === 'update'
      ? updateAppSubmission(user, app._id, form, version)
      : operation === 'market' ? submitOwnedAppToPublicMarket(user, app._id, { shortName: 'my-app', ifMatch: version }) : delistOwnedApp(user, app._id, version)
    await expect(action).rejects.toMatchObject({ statusCode: 403 })
    expect(memory.read('apps/app-one')?.ownerUid).toBe('another')
    expect(memory.commits).toBe(0)
  })
  it('lets exactly one competing editor commit and rejects the SDK retry without rebasing', async () => {
    const version = await token()
    const results = await Promise.allSettled([
      updateAppSubmission(user, app._id, { ...form, name: 'Editor A' }, version),
      updateAppSubmission(user, app._id, { ...form, name: 'Editor B' }, version),
    ])
    expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1)
    expect(results.find(result => result.status === 'rejected')).toMatchObject({ reason: { statusCode: 412 } })
    expect(memory.commits).toBe(1)
    expect(memory.attempts).toBe(3)
    expect(memory.dump().filter(([key]) => key.startsWith('app_submissions/'))).toHaveLength(2)
    expect(memory.dump().filter(([key]) => key.startsWith('app_review_events/'))).toHaveLength(1)
    const [fresh] = await listOwnedApps(user)
    const receipt = results.find(result => result.status === 'fulfilled')
    expect(receipt).toMatchObject({ value: { app: { writeVersion: fresh!.writeVersion } } })
  })
  it.each(['update', 'market', 'delist'] as const)('rejects concurrent review changes during %s before any write', async (operation) => {
    const version = await token()
    memory.before(() => memory.patch('app_submissions/revision-one', { reviewStatus: 'approved' }))
    const action = operation === 'update'
      ? updateAppSubmission(user, app._id, form, version)
      : operation === 'market' ? submitOwnedAppToPublicMarket(user, app._id, { shortName: 'my-app', ifMatch: version }) : delistOwnedApp(user, app._id, version)
    await expect(action).rejects.toMatchObject({ statusCode: 412 })
    expect(memory.commits).toBe(0)
    expect(memory.read('app_submissions/revision-one')?.reviewStatus).toBe('approved')
  })
  function seedListing() {
    memory.patch('app_submissions/older-review', { ...submission, _id: 'older-review', reviewStatus: 'pending' })
    memory.patch('public_market_listings/app-one', { _id: 'app-one', appId: app._id, shortName: 'my-app', status: 'listed', approvedRevisionId: 'revision-one', activeSubmissionId: 'older-review', updatedAt: 1, createdAt: 1 })
  }
  it.each(['private', 'delist'] as const)('atomically removes the listing and withdraws the older pending review on %s', async (operation) => {
    seedListing()
    const version = await token()
    if (operation === 'private')
      await updateAppSubmission(user, app._id, { ...form, audience: 'owner', isPublic: false }, version)
    else
      await delistOwnedApp(user, app._id, version)
    expect(memory.read('public_market_listings/app-one')).toMatchObject({ status: 'delisted', activeSubmissionId: '' })
    expect(memory.read('app_submissions/older-review')?.reviewStatus).toBe('withdrawn')
    expect(memory.read('app_submissions/revision-one')?.reviewStatus).toBe('draft')
    expect(memory.commits).toBe(1)
  })
  it('rolls back the revision, app, identifier and event if market invalidation fails', async () => {
    seedListing()
    const version = await token()
    const before = memory.dump()
    memory.failOn('public_market_listings')
    await expect(updateAppSubmission(user, app._id, { ...form, audience: 'owner', isPublic: false }, version)).rejects.toThrow('fixture write failed')
    expect(memory.dump()).toEqual(before)
    expect(memory.commits).toBe(0)
  })
  it.each([['POST', '/submissions'], ['POST', '/public-market'], ['DELETE', '']])('requires a strong If-Match header at the real %s %s route', async (method, suffix) => {
    for (const [header, expected] of [[undefined, 428], ['*', 412], ['W/"abc"', 412], [`"${'0'.repeat(64)}"`, 412]] as const) {
      const response = await fetch(`${origin}/api/apps/app-one${suffix}`, {
        method,
        headers: { 'Content-Type': 'application/json', ...(header ? { 'If-Match': header } : {}) },
        ...(method === 'POST' ? { body: JSON.stringify({ ...form, shortName: 'my-app' }) } : {}),
      })
      expect(response.status).toBe(expected)
    }
    expect(memory.commits).toBe(0)
  })
  it.each([['POST', '/submissions'], ['POST', '/public-market'], ['DELETE', '']])('forwards a valid strong header through the %s %s route', async (method, suffix) => {
    const response = await fetch(`${origin}/api/apps/app-one${suffix}`, {
      method,
      headers: { 'Content-Type': 'application/json', 'If-Match': await token() },
      ...(method === 'POST' ? { body: JSON.stringify({ ...form, shortName: 'my-app' }) } : {}),
    })
    expect(response.status).toBe(200)
    expect(memory.commits).toBe(1)
  })
})
