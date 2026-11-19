import assert from 'node:assert/strict'
import { Buffer } from 'node:buffer'
import { afterEach, it, vi } from 'vitest'
import worker from './index.mjs'

const origin = 'https://build.yunle.app'
const project = '1'.repeat(32)
const old = '2'.repeat(32)
const next = '3'.repeat(32)
const token = 'f'.repeat(64)

afterEach(() => vi.unstubAllGlobals())

function fixture() {
  const objects = new Map()
  const env = {
    WEB_BUILD_WRITE_TOKEN: token,
    APPS_ORIGIN: 'https://apps.yunle.fun',
    PAGES: {
      async put(key, bytes, options) {
        assert.equal(options.onlyIf.get('if-none-match'), '*')
        if (objects.has(key))
          return null
        const object = { html: bytes.toString(), checksums: { sha256: Buffer.from(options.sha256, 'hex') } }
        objects.set(key, object)
        return object
      },
      async head(key) {
        return objects.get(key) ?? null
      },
      async get(key) {
        const object = objects.get(key)
        return object ? { ...object, body: new Response(object.html).body } : null
      },
    },
  }
  return { objects, env }
}

function upload(env, version, html, secret = token) {
  return worker.fetch(new Request(`${origin}/_publish/${project}/${version}.html`, {
    method: 'PUT',
    headers: { 'Authorization': `Bearer ${secret}`, 'Content-Type': 'text/html; charset=utf-8' },
    body: html,
  }), env)
}

it('stores private HTML files once and rejects writes to an existing version', async () => {
  const { objects, env } = fixture()
  assert.equal((await upload(env, old, 'private', 'a'.repeat(64))).status, 404)
  assert.equal((await upload(env, old, '<h1>旧版</h1>')).status, 201)
  assert.equal((await upload(env, old, '<h1>旧版</h1>')).status, 204)
  assert.equal((await upload(env, old, '<h1>覆盖</h1>')).status, 409)
  assert.equal(objects.get(`${project}/${old}.html`).html, '<h1>旧版</h1>')
  assert.equal((await upload(env, next, 'a'.repeat(25_000))).status, 413)
})

it('serves static HTML through both URLs and revokes direct versions when the project is withdrawn', async () => {
  const { objects, env } = fixture()
  await upload(env, old, '<h1>旧版</h1>')
  await upload(env, next, '<h1>新版</h1>')
  let disabled = false
  vi.stubGlobal('fetch', async (url, options) => {
    assert.equal(url.origin, env.APPS_ORIGIN)
    assert.equal(options.redirect, 'manual')
    assert.equal(options.headers, undefined)
    if (disabled)
      return new Response(null, { status: 404 })
    const releaseId = url.pathname.endsWith(old) ? old : next
    return Response.json({ releaseId, sha256: objects.get(`${project}/${releaseId}.html`).checksums.sha256.toString('hex') })
  })
  const get = path => worker.fetch(new Request(`${origin}${path}`, {
    headers: { Cookie: 'identity=private', Authorization: 'Bearer browser' },
  }), env)
  const shared = await get(`/site/${project}`)
  assert.equal(await shared.text(), '<h1>新版</h1>')
  assert.match(shared.headers.get('content-security-policy'), /default-src 'none'/)
  assert.equal(shared.headers.get('cache-control'), 'no-store')
  const pinned = await get(`/site/${project}/${old}.html`)
  assert.equal(await pinned.text(), '<h1>旧版</h1>')
  assert.equal(pinned.headers.get('x-yunle-web-build-release'), old)
  const head = await worker.fetch(new Request(`${origin}/site/${project}/${old}.html`, { method: 'HEAD' }), env)
  assert.equal(head.status, 200)
  assert.equal(head.body, null)
  assert.equal((await get('/api/session')).status, 404)

  disabled = true
  assert.equal((await get(`/site/${project}`)).status, 404)
  assert.equal((await get(`/site/${project}/${old}.html`)).status, 404)
})
