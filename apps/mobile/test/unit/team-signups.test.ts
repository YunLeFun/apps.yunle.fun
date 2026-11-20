import type { AddressInfo } from 'node:net'
import type { CloudbaseAdminDb } from '../../server/utils/cloudbase-admin'
import { createServer } from 'node:http'
import { createApp, createRouter, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const storage = vi.hoisted(() => {
  const documents = new Map<string, unknown>()
  const write = vi.fn(async (id: string, value: unknown): Promise<{ updated: number, upserted?: unknown[] }> => {
    documents.set(id, structuredClone(value))
    return { updated: 1 }
  })
  const collection = () => ({
    doc: (id: string) => ({
      get: async () => ({ data: documents.has(id) ? [structuredClone(documents.get(id))] : [] }),
      set: (value: unknown) => write(id, value),
    }),
  })
  let queue: Promise<unknown> = Promise.resolve()
  const db = {
    collection,
    runTransaction<T>(run: (transaction: { collection: typeof collection }) => Promise<T>) {
      const result = queue.then(() => run({ collection }))
      queue = result.catch(() => undefined)
      return result
    },
  }
  return { documents, write, db: db as unknown as CloudbaseAdminDb }
})
vi.mock('../../server/utils/cloudbase-admin', () => ({ useCloudbaseAdmin: () => ({ db: storage.db }) }))

const id = '0ebd1cfc-e4cf-4a50-bf48-55c77709c04a'
const nativeFetch = globalThis.fetch
let server: ReturnType<typeof createServer>
let url: string

function request(method: string, uid?: string, body?: unknown, path = url) {
  return nativeFetch(path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(uid && { Authorization: `Bearer ${uid}` }) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

beforeAll(async () => {
  vi.stubGlobal('defineEventHandler', defineEventHandler)
  vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'test-env' } }))
  const route = (await import('../../server/api/team-signups/[id]')).default
  const path = '/api/team-signups/:id'
  const app = createApp()
  app.use(createRouter().get(path, route).put(path, route).patch(path, route))
  server = createServer(toNodeListener(app))
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/team-signups/${id}`
})

beforeEach(() => {
  storage.documents.clear()
  vi.stubGlobal('fetch', vi.fn(async (_url, request: RequestInit) => {
    const uid = new Headers(request.headers).get('Authorization')?.replace(/^Bearer /, '')
    return Response.json({ sub: uid, status: 'ACTIVE' })
  }))
})

afterAll(async () => {
  vi.unstubAllGlobals()
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
})

describe('team signup HTTP contract', () => {
  it('requires identity and only creates valid signup documents', async () => {
    const anonymous = await request('GET')
    expect(anonymous.status).toBe(401)
    expect(anonymous.headers.get('cache-control')).toBe('private, no-store')
    expect((await request('PUT', 'owner', { title: '周末联机', capacity: 17 })).status).toBe(400)
    expect((await request('GET', 'owner')).status).toBe(404)
    expect(storage.documents.size).toBe(0)
  })

  it('retries a creation by the same owner and preserves its existing seats', async () => {
    const body = { title: '周末联机', capacity: 4 }
    expect((await request('PUT', 'owner', body)).status).toBe(200)
    expect((await request('PATCH', 'member', { joined: true })).status).toBe(200)
    const repeated = await request('PUT', 'owner', body)
    expect(await repeated.json()).toEqual({
      schemaVersion: 1,
      signupId: id,
      title: '周末联机',
      capacity: 4,
      memberCount: 1,
      joined: false,
      revision: 2,
    })
    expect((await request('PUT', 'someone-else', body)).status).toBe(409)
    expect((await request('PUT', 'owner', { ...body, capacity: 6 })).status).toBe(409)
  })

  it('protects the last seat and supports idempotent cancellation and cross-account refresh', async () => {
    await request('PUT', 'owner', { title: '周末联机', capacity: 2 })
    await request('PATCH', 'first', { joined: true, uid: 'someone-else' })
    const results = await Promise.all(['second', 'third'].map(uid => request('PATCH', uid, { joined: true })))
    expect(results.map(result => result.status).sort()).toEqual([200, 409])
    expect(await results.find(result => result.status === 409)?.json()).toMatchObject({ data: { code: 'SIGNUP_FULL' } })
    expect(await (await request('GET', 'first')).json()).toMatchObject({ memberCount: 2, joined: true, revision: 3 })
    expect(await (await request('GET', 'owner')).json()).toMatchObject({ memberCount: 2, joined: false, revision: 3 })
    const cancel = await request('PATCH', 'first', { joined: false })
    expect(await cancel.json()).toMatchObject({ memberCount: 1, joined: false, revision: 4 })
    expect(await (await request('PATCH', 'first', { joined: false })).json()).toMatchObject({ memberCount: 1, revision: 4 })
  })

  it('requires CloudBase to acknowledge the stored document before reporting success', async () => {
    storage.write.mockResolvedValueOnce({ updated: 0, upserted: [{}] })
    expect((await request('PUT', 'owner', { title: '周末联机', capacity: 4 })).status).toBe(503)
    expect(storage.documents.size).toBe(0)
  })
})
