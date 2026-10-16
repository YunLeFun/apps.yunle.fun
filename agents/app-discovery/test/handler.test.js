import assert from 'node:assert/strict'
import http from 'node:http'
// eslint-disable-next-line test/no-import-node-test
import { describe, it } from 'node:test'
import { authorizeAgent, createDiscoveryHandler, takeDailyUsage, validateAgentInput } from '../src/handler.js'

const validProfile = { sub: 'alice', status: 'ACTIVE' }
const account = { coin: 10, membership: { isActive: true, expireAt: 3000 } }
function fetchFixture({ profile = validProfile, wallet = account, failure } = {}) {
  const calls = []
  const fetchImpl = async (url, options) => {
    calls.push({ url, options })
    if (failure)
      return new Response('{}', { status: failure })
    return Response.json(url.endsWith('/auth/v1/user/me') ? profile : wallet)
  }
  return { calls, fetchImpl }
}
function memoryDB(initial = null, failure = false) {
  let current = initial
  let queue = Promise.resolve()
  let writes = 0
  return {
    get state() { return current },
    get writes() { return writes },
    runTransaction(operation) {
      const job = queue.then(async () => {
        let next = current ? { ...current } : null
        const doc = {
          async get() {
            if (failure)
              throw new Error('database unavailable')
            return { data: next ? [next] : [] }
          },
          async update(fields) {
            next = { ...next, ...fields }
            return { updated: 1 }
          },
          async set(fields) {
            next = fields
            return { upserted: [{}] }
          },
        }
        const result = await operation({ collection: () => ({ doc: () => doc }) })
        current = next
        writes += 1
        return result
      })
      queue = job.catch(() => {})
      return job
    },
  }
}
describe('agent account access', () => {
  it('delegates a real bearer only to the fixed environment and canonical account snapshot', async () => {
    const { calls, fetchImpl } = fetchFixture()
    assert.deepEqual(await authorizeAgent('fixture-only', { envId: 'fixture-env', fetchImpl, now: () => 1000 }), { uid: 'alice' })
    assert.equal(calls[1].url, 'https://fixture-env.api.tcloudbasegateway.com/v1/functions/account-api')
    assert.deepEqual(JSON.parse(calls[1].options.body), { action: 'getAccount' })
    assert.equal(calls[1].options.headers.Authorization, 'Bearer fixture-only')
    assert.equal(calls[1].options.redirect, 'error')
  })
  it('rejects stale active flags and missing membership expiration', async () => {
    for (const expireAt of [0, 999, null, '3000']) {
      const { fetchImpl } = fetchFixture({ wallet: { coin: 0, membership: { isActive: true, expireAt } } })
      await assert.rejects(authorizeAgent('fixture-only', { envId: 'fixture-env', fetchImpl, now: () => 1000 }), { statusCode: 403, code: 'MEMBERSHIP_REQUIRED' })
    }
  })
  it('rejects anonymous and suspended profiles before reading membership', async () => {
    for (const profile of [{ sub: 'guest-uid', is_anonymous: true }, { sub: 'alice', status: 'BLOCKED' }, { sub: 'alice', app_metadata: { provider: 'anonymous' } }]) {
      const { calls, fetchImpl } = fetchFixture({ profile })
      await assert.rejects(authorizeAgent('fixture-only', { envId: 'fixture-env', fetchImpl }), { statusCode: 403, code: 'ACCOUNT_RESTRICTED' })
      assert.equal(calls.length, 1)
    }
  })
  it('does not turn account outages into signed-out or nonmember states', async () => {
    const { fetchImpl } = fetchFixture({ failure: 503 })
    await assert.rejects(authorizeAgent('fixture-only', { envId: 'fixture-env', fetchImpl }), { statusCode: 503, code: 'ACCOUNT_UNAVAILABLE' })
  })
  it('keeps forbidden account-service actions distinct from membership upsell', async () => {
    const fetchImpl = async url => url.endsWith('/user/me') ? Response.json(validProfile) : new Response('{}', { status: 403 })
    await assert.rejects(authorizeAgent('fixture-only', { envId: 'fixture-env', fetchImpl }), { statusCode: 403, code: 'ACCOUNT_RESTRICTED' })
  })
})
describe('transactional daily agent usage', () => {
  it('does not admit concurrent requests beyond the exact limit', async () => {
    const db = memoryDB()
    const results = await Promise.allSettled(Array.from({ length: 8 }, () => takeDailyUsage(db, 'alice', 2, 1000)))
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 2)
    assert.equal(db.state.count, 2)
    assert.equal(db.writes, 2)
    assert.ok(results.filter(r => r.status === 'rejected').every(r => r.reason.statusCode === 429))
  })
  it('does not reset an existing counter after a read failure', async () => {
    const db = memoryDB({ uid: 'alice', date: '1970-01-01', count: 49 }, true)
    await assert.rejects(takeDailyUsage(db, 'alice', 50, 1000))
    assert.equal(db.state.count, 49)
    assert.equal(db.writes, 0)
  })
  it('does not overwrite corrupt or foreign owner counters', async () => {
    for (const value of [{ uid: 'bob', date: '1970-01-01', count: 1 }, { uid: 'alice', date: '1970-01-01', count: -1 }]) {
      const db = memoryDB(value)
      await assert.rejects(takeDailyUsage(db, 'alice', 50, 1000), { statusCode: 503 })
      assert.equal(db.writes, 0)
    }
  })
  it('rejects invalid message histories before taking usage', () => {
    for (const value of [{}, { threadId: 123, runId: 'r', messages: [{ role: 'user', content: 'hi' }] }, { threadId: 't', runId: {}, messages: [{ role: 'user', content: 'hi' }] }, { threadId: '../other', runId: 'r', messages: [{ role: 'user', content: 'hi' }] }, { threadId: 't', runId: 'r', messages: [{ role: 'system', content: 'hi' }] }])
      assert.throws(() => validateAgentInput(value), { statusCode: 400 })
  })
})
describe('agent HTTP stream', () => {
  async function withServer(options, run) {
    const server = http.createServer(createDiscoveryHandler({ db: memoryDB(), envId: 'fixture-env', now: () => 1000, ...options }))
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
    try {
      await run(`http://127.0.0.1:${server.address().port}`)
    }
    finally { await new Promise(resolve => server.close(resolve)) }
  }
  const payload = { threadId: 'thread_fixture', runId: 'run_fixture', messages: [{ role: 'user', content: '推荐开发工具' }] }
  const post = (url, token = 'fixture-only') => fetch(`${url}/send-message`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(payload),
  })
  it('returns no-store 401 without invoking a remote service', async () => {
    let called = false
    await withServer({ fetchImpl: async () => {
      called = true
    } }, async (url) => {
      const response = await post(url, '')
      assert.equal(response.status, 401)
      assert.equal(response.headers.get('cache-control'), 'private, no-store')
      assert.equal(called, false)
    })
  })
  it('streams published cards and a complete matching run without reflecting credentials', async () => {
    const calls = []
    const fetchImpl = async (url, options) => {
      calls.push({ url, options })
      if (url.endsWith('/public')) {
        return Response.json({ items: [
          { _id: 'dev', slug: 'local-dev', marketShortName: 'public-dev', name: '开发工具', isPublic: true, status: 'approved', publicationStatus: 'published' },
          { _id: 'draft', slug: 'draft', name: '开发工具草稿', isPublic: true, status: 'approved', publicationStatus: 'unpublished' },
        ] })
      }
      return Response.json(url.endsWith('/user/me') ? validProfile : account)
    }
    await withServer({ fetchImpl }, async (url) => {
      const response = await post(url)
      assert.equal(response.status, 200)
      assert.match(response.headers.get('content-type'), /event-stream/)
      const body = await response.text()
      const events = body.split('\n\n').filter(Boolean).map(line => JSON.parse(line.slice(6)))
      assert.equal(events[0].type, 'RUN_STARTED')
      assert.equal(events.at(-1).type, 'RUN_FINISHED')
      assert.equal(events.at(-1).runId, payload.runId)
      const cards = JSON.parse(events.find(e => e.type === 'TOOL_CALL_RESULT').content).apps
      assert.deepEqual(cards.map(c => c.slug), ['public-dev'])
      assert.equal(body.includes('fixture-only'), false)
      assert.equal(calls.at(-1).options.headers.Authorization, undefined)
    })
  })
  it('ends an established stream with RUN_ERROR when catalog lookup fails', async () => {
    const fetchImpl = async url => url.endsWith('/public') ? new Response('{}', { status: 503 }) : Response.json(url.endsWith('/user/me') ? validProfile : account)
    await withServer({ fetchImpl }, async (url) => {
      const response = await post(url)
      assert.equal(response.status, 200)
      const body = await response.text()
      assert.match(body, /"type":"RUN_ERROR"/)
      assert.equal(body.includes('"type":"RUN_FINISHED"'), false)
    })
  })
})
