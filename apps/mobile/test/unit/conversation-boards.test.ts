import type { AddressInfo } from 'node:net'
import type { CloudbaseAdminDb } from '../../server/utils/cloudbase-admin'
import { randomUUID } from 'node:crypto'
import { createServer } from 'node:http'
import { createApp, createRouter, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'

const { db } = vi.hoisted(() => {
  const documents = new Map<string, unknown>()
  const collection = () => ({
    doc: (id: string) => ({
      get: async () => ({ data: documents.has(id) ? [structuredClone(documents.get(id))] : [] }),
      set: async (value: unknown) => {
        documents.set(id, structuredClone(value))
        return { updated: 1 }
      },
    }),
  })
  let queue: Promise<unknown> = Promise.resolve()
  const db = {
    collection,
    runTransaction<T>(work: (transaction: { collection: typeof collection }) => Promise<T>) {
      const result = queue.then(() => work({ collection }))
      queue = result.catch(() => undefined)
      return result
    },
  }
  return { db: db as unknown as CloudbaseAdminDb }
})

vi.mock('../../server/utils/cloudbase-admin', () => ({ useCloudbaseAdmin: () => ({ db }) }))
const client = globalThis.fetch
let server: ReturnType<typeof createServer>
let base: string

function request(id: string, method: string, viewer?: string, body?: unknown, signal?: AbortSignal, ns = '/api/boards') {
  return client(`${base}${ns}/${id}`, {
    method,
    signal,
    headers: { 'Content-Type': 'application/json', ...(viewer && { Authorization: `Bearer ${viewer}` }) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

function place(row: number, column: number, expectedRevision: number) {
  return { action: 'place', row, column, expectedRevision, actionId: randomUUID() }
}

async function watch(id: string, viewer: string, signal: AbortSignal, ns = '/api/boards') {
  const response = await request(`${id}/events`, 'GET', viewer, undefined, signal, ns)
  expect(response.headers.get('content-type')).toContain('text/event-stream')
  const reader = response.body!.pipeThrough(new TextDecoderStream()).getReader()
  let buffer = ''
  return async () => {
    while (true) {
      const end = buffer.indexOf('\n\n')
      if (end !== -1) {
        const frame = buffer.slice(0, end)
        buffer = buffer.slice(end + 2)
        if (frame.startsWith('data: '))
          return JSON.parse(frame.slice(6))
      }
      else {
        const { done, value } = await reader.read()
        if (done)
          throw new Error('SSE closed early')
        buffer += value
      }
    }
  }
}

beforeAll(async () => {
  vi.stubGlobal('defineEventHandler', defineEventHandler)
  vi.stubGlobal('useRuntimeConfig', () => ({ public: { tcbEnvId: 'test-env' } }))
  vi.stubGlobal('fetch', vi.fn(async (_url, request: RequestInit) => {
    const uid = new Headers(request.headers).get('Authorization')?.replace(/^Bearer /, '')
    return Response.json({ sub: uid, status: 'ACTIVE' })
  }))
  const handler = (await import('../../server/api/boards/[id]/index')).default
  const events = (await import('../../server/api/boards/[id]/events.get')).default
  const path = '/api/boards/:id'
  const common = (await import('../../server/api/conversation-cards/[type]/[id]/index')).default
  const commonEvents = (await import('../../server/api/conversation-cards/[type]/[id]/events.get')).default
  const signup = (await import('../../server/api/team-signups/[id]')).default
  const invite = (await import('../../server/routes/cards/[type]/[id].get')).default
  const cardPath = '/api/conversation-cards/:type/:id'
  const app = createApp()
  app.use(createRouter()
    .get(path, handler).put(path, handler).patch(path, handler).get(`${path}/events`, events)
    .put('/api/team-signups/:id', signup)
    .get(cardPath, common).patch(cardPath, common).get(`${cardPath}/events`, commonEvents)
    .get('/cards/:type/:id', invite))
  server = createServer(toNodeListener(app))
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
})

afterAll(async () => {
  vi.unstubAllGlobals()
  server.closeAllConnections()
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
})

describe('conversation board HTTP and SSE', () => {
  it('delivers a validated custom scene and keeps it on idempotent creation', async () => {
    const id = randomUUID()
    const scene = {
      schemaVersion: 1,
      size: 11,
      palette: { board: '#eedddd', grid: '#111111', black: '#000000', white: '#ffffff' },
      interaction: { gesture: 'drag-to-place', action: 'place' },
    }
    expect((await request(id, 'PUT', undefined, { scene })).status).toBe(401)
    expect((await request(`${id}/events`, 'GET')).status).toBe(401)
    expect((await request(id, 'PUT', 'black', { scene: { ...scene, size: 25 } })).status).toBe(400)
    expect((await request(id, 'PUT', 'black', { scene: { ...scene, interaction: { gesture: 'script', action: 'place' } } })).status).toBe(400)
    const created = await request(id, 'PUT', 'black', { scene })
    expect(created.headers.get('cache-control')).toBe('private, no-store')
    expect(await created.json()).toEqual({
      schemaVersion: 1,
      boardId: id,
      scene,
      revision: 1,
      status: 'waiting',
      seat: 'black',
      turn: null,
      winner: null,
      pieces: [],
    })
    expect(await (await request(id, 'PUT', 'black', {})).json()).toMatchObject({ scene, revision: 1 })
    expect((await request(id, 'PUT', 'white', { scene })).status).toBe(409)
  })

  it('pushes both turns to independent viewers, catches up after reconnect, and guards conflicting moves', async () => {
    const id = randomUUID()
    const close = new AbortController()
    const blackConnection = new AbortController()
    const timeout = setTimeout(() => close.abort(), 8_000)
    try {
      expect((await request(id, 'PUT', 'black', {})).status).toBe(200)
      const readBlack = await watch(id, 'black', AbortSignal.any([close.signal, blackConnection.signal]))
      expect(await readBlack()).toMatchObject({ revision: 1, status: 'waiting', seat: 'black' })
      const joiners = ['guest-a', 'guest-b']
      const joins = await Promise.all(joiners.map(viewer => request(id, 'PATCH', viewer, { action: 'join' })))
      expect(joins.map(result => result.status).sort()).toEqual([200, 409])
      const white = joiners[joins.findIndex(result => result.ok)]!
      const third = joiners[joins.findIndex(result => !result.ok)]!
      expect(await readBlack()).toMatchObject({ revision: 2, status: 'playing', turn: 'black' })
      const readWhite = await watch(id, white, close.signal)
      expect(await readWhite()).toMatchObject({ revision: 2, seat: 'white' })

      const first = place(4, 4, 2)
      expect((await request(id, 'PATCH', third, first)).status).toBe(403)
      expect((await request(id, 'PATCH', white, first)).status).toBe(409)
      expect((await request(id, 'PATCH', 'black', first)).status).toBe(200)
      expect(await readBlack()).toMatchObject({ revision: 3, turn: 'white', pieces: [{ row: 4, column: 4, color: 'black' }] })
      expect(await readWhite()).toMatchObject({ revision: 3, turn: 'white' })

      expect((await request(id, 'PATCH', white, place(9, 0, 3))).status).toBe(400)
      expect((await request(id, 'PATCH', white, place(4, 4, 3))).status).toBe(409)
      expect((await request(id, 'PATCH', white, place(4, 5, 2))).status).toBe(409)
      expect((await request(id, 'PATCH', white, place(4, 5, 3))).status).toBe(200)
      expect(await readBlack()).toMatchObject({ revision: 4, turn: 'black' })
      expect(await readWhite()).toMatchObject({ revision: 4, turn: 'black' })
      expect(await (await request(id, 'PATCH', 'black', first)).json()).toMatchObject({ revision: 4 })
      blackConnection.abort()
      const recovered = await watch(id, 'black', close.signal)
      expect(await recovered()).toMatchObject({
        revision: 4,
        seat: 'black',
        pieces: [
          { row: 4, column: 4, color: 'black' },
          { row: 4, column: 5, color: 'white' },
        ],
      })
      expect(await (await request(id, 'GET', third)).json()).toMatchObject({ revision: 4, seat: null })
    }
    finally {
      clearTimeout(timeout)
      close.abort()
    }
  }, 10_000)

  it('ends the game after five contiguous stones and rejects later moves', async () => {
    const id = randomUUID()
    await request(id, 'PUT', 'black', {})
    await request(id, 'PATCH', 'white', { action: 'join' })
    for (let i = 0; i < 4; i++) {
      expect((await request(id, 'PATCH', 'black', place(i, i, 2 + 2 * i))).status).toBe(200)
      expect((await request(id, 'PATCH', 'white', place(i, 8, 3 + 2 * i))).status).toBe(200)
    }
    const winning = await request(id, 'PATCH', 'black', place(4, 4, 10))
    expect(await winning.json()).toMatchObject({ revision: 11, status: 'won', turn: null, winner: 'black' })
    expect((await request(id, 'PATCH', 'white', place(4, 8, 11))).status).toBe(409)
  })
})

describe('common native conversation card contract', () => {
  const ns = '/api/conversation-cards'
  const command = (action: string, expectedRevision: number, input?: Record<string, number>) =>
    ({ schemaVersion: 1, action, actionId: randomUUID(), expectedRevision, input })

  it('supplies the signup template and pushes revisioned actions to a second viewer', async () => {
    const id = randomUUID()
    const card = `team.signup/${id}`
    const stream = new AbortController()
    const timeout = setTimeout(() => stream.abort(), 8_000)
    try {
      expect((await request(id, 'PUT', 'owner', { title: '开黑报名', capacity: 2 }, undefined, '/api/team-signups')).status).toBe(200)
      expect((await request(card, 'GET', undefined, undefined, undefined, ns)).status).toBe(401)
      const readOwner = await watch(card, 'owner', stream.signal, ns)
      const initial = await readOwner()
      expect(initial).toMatchObject({
        reference: { type: 'team.signup', instanceId: id },
        revision: 1,
        data: { title: '开黑报名', memberCount: 0, capacity: 2 },
        actions: { 'signup.join': { label: '报名', enabled: true } },
      })
      expect(initial.template.components).toContainEqual({ kind: 'seats', filled: 'memberCount', total: 'capacity' })
      const act = (body: unknown) => request(card, 'PATCH', 'member', body, undefined, ns)
      const join = command('signup.join', 1)
      expect(await (await act(join)).json()).toMatchObject({ revision: 2, actions: { 'signup.cancel': { enabled: true } } })
      expect(await (await act(join)).json()).toMatchObject({ revision: 2 })
      expect((await act(command('signup.cancel', 1))).status).toBe(409)
      expect(await readOwner()).toMatchObject({ revision: 2, data: { memberCount: 1 }, actions: { 'signup.join': { enabled: true } } })
      expect(await (await act(command('signup.cancel', 2))).json()).toMatchObject({ revision: 3, data: { memberCount: 0 } })
      expect(await readOwner()).toMatchObject({ revision: 3, data: { memberCount: 0 } })
    }
    finally {
      clearTimeout(timeout)
      stream.abort()
    }
  }, 10_000)

  it('shares the same action and snapshot envelopes for Canvas and rejects app-specific actions on another card', async () => {
    const id = randomUUID()
    await request(id, 'PUT', 'black', {})
    const card = `play.board/${id}`
    const response = await request(card, 'GET', 'white', undefined, undefined, ns)
    const state = await response.json()
    expect(state.template.components).toContainEqual({ kind: 'gomoku', field: 'board', action: 'board.place' })
    expect(state.actions).toEqual({ 'board.join': { label: '加入执白', enabled: true } })
    expect((await request(card, 'PATCH', 'white', command('signup.join', 1), undefined, ns)).status).toBe(400)
    expect((await request(card, 'PATCH', 'white', command('board.join', 1), undefined, ns)).status).toBe(200)
    const move = command('board.place', 2, { row: 4, column: 4 })
    const played = await request(card, 'PATCH', 'black', move, undefined, ns)
    expect(await played.json()).toMatchObject({ revision: 3, data: { board: { pieces: [{ row: 4, column: 4, color: 'black' }] } } })
    expect(await (await request(card, 'PATCH', 'black', move, undefined, ns)).json()).toMatchObject({ revision: 3 })

    const landing = await request(card, 'GET', undefined, undefined, undefined, '/cards')
    expect(landing.status).toBe(200)
    expect(landing.headers.get('referrer-policy')).toBe('no-referrer')
    expect(await landing.text()).toContain(`href="yunlefun://card/${card}"`)
    expect((await request(`${card}?role=player`, 'GET', undefined, undefined, undefined, '/cards')).status).toBe(404)
  })
})
