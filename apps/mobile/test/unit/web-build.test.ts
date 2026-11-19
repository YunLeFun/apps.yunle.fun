import type { AddressInfo } from 'node:net'
import { createHash, createHmac } from 'node:crypto'
import { createServer } from 'node:http'
import { createApp, createRouter, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCloudbaseAuthCache } from '../../server/utils/cloudbase-auth'
import { getWebBuildWriteToken } from '../../server/utils/web-build-config'
import { renderWebBuildPage } from '../../server/utils/web-build-html'
import { parseWebBuildPage } from '../../server/utils/web-build-page'
import {
  getOwnedWebBuild,
  getPublicWebBuild,
  getWebBuildForSubmission,
  publishWebBuild,
  reserveWebBuildAction,
  saveWebBuildDraft,
  withdrawWebBuild,
} from '../../server/utils/web-build-storage'

const { documents, moderation } = vi.hoisted(() => ({
  documents: new Map<string, Record<string, unknown>>(),
  moderation: vi.fn(),
}))
vi.mock('../../server/utils/cloudbase-admin', () => {
  const db = {
    collection: () => ({
      where: ({ ownerUid }: { ownerUid: string }) => ({
        orderBy: () => ({
          limit: () => ({
            get: async () => ({
              data: Array.from(documents, ([_id, data]) => ({ ...data, _id })).filter(data => Reflect.get(data, 'ownerUid') === ownerUid),
            }),
          }),
        }),
      }),
      doc: (id: string) => ({
        get: async () => ({ data: documents.has(id) ? [structuredClone(documents.get(id))] : [] }),
        set: async (data: Record<string, unknown>) => documents.set(id, structuredClone(data)),
        update: async (data: Record<string, unknown>) => documents.set(id, { ...documents.get(id), ...structuredClone(data) }),
      }),
    }),
    runTransaction: (body: (database: unknown) => unknown) => body(db),
  }
  return { useCloudbaseAdmin: () => ({ db }) }
})
vi.mock('../../server/utils/moderation', () => ({ moderateText: moderation }))
vi.mock('../../server/utils/web-build-market', () => ({ submitWebBuildToMarket: vi.fn(async () => ({ slug: 'submitted' })) }))

const origin = 'https://build.yunle.app'
const token = 'a'.repeat(64)
const artifacts = new Map<string, string>()
const upload = vi.fn(async (url: string, options: RequestInit) => {
  const path = new URL(url).pathname
  expect(url.startsWith(origin)).toBe(true)
  expect(options.method).toBe('PUT')
  expect(options.headers).toHaveProperty('Authorization', `Bearer ${token}`)
  expect(path).toMatch(/^\/_publish\/[a-f0-9]{32}\/[a-f0-9]{32}\.html$/)
  artifacts.set(path, String(options.body))
  return new Response(null, { status: 201 })
})
const page = {
  title: '读书会',
  description: '周日见',
  palette: 'indigo',
  sections: [{ title: '活动安排', text: '下午三点签到', expandable: true }],
} as const

const draftPage = parseWebBuildPage(page)!

beforeEach(() => {
  documents.clear()
  moderation.mockReset().mockResolvedValue({ suggestion: 'Pass' })
  artifacts.clear()
  upload.mockClear()
  vi.stubGlobal('fetch', upload)
  vi.stubGlobal('useRuntimeConfig', () => ({ webBuildWriteToken: token }))
})

describe('web build content boundary', () => {
  it('accepts only the component schema and preserves its text as data', () => {
    const unsafe = '<script src="https://example.test/a.js"></script>'
    const parsed = parseWebBuildPage({
      ...page,
      title: unsafe.slice(0, 50),
      html: '<input type="password">',
      sections: [{ title: '详情', text: unsafe, expandable: true, href: 'https://example.test' }],
    })!
    expect(parsed).not.toHaveProperty('html')
    expect(parsed.sections[0]).not.toHaveProperty('href')
    expect(parsed.sections[0]?.text).toBe(unsafe)
    expect(renderWebBuildPage(parsed)).not.toContain('<script')
    expect(renderWebBuildPage(parsed)).toContain('&lt;script')
  })

  it('rejects invalid schemas and invalid write credentials', () => {
    expect(parseWebBuildPage({ ...page, palette: '__proto__' })).toBeNull()
    expect(parseWebBuildPage({ ...page, sections: [] })).toBeNull()
    expect(parseWebBuildPage({ ...page, sections: [{ title: 'A', text: 'a'.repeat(441), expandable: true }] })).toBeNull()
    expect(getWebBuildWriteToken()).toBe(token)
    vi.stubGlobal('useRuntimeConfig', () => ({ webBuildWriteToken: 'short' }))
    expect(getWebBuildWriteToken()).toBeNull()
  })
})

describe('web build release workflow', () => {
  it('keeps drafts private and never changes a previously released review version', async () => {
    const initial = await saveWebBuildDraft('author', draftPage, '创建邀请页')
    await expect(getPublicWebBuild(initial.id)).rejects.toMatchObject({ statusCode: 404 })
    await expect(getOwnedWebBuild(initial.id, 'another-user')).rejects.toMatchObject({ statusCode: 404 })
    await expect(getWebBuildForSubmission(initial.id, 'author', 1)).rejects.toMatchObject({ statusCode: 409 })

    const published = await publishWebBuild(initial.id, 'author', 1)
    expect(published.shareUrl).toBe(`${origin}/site/${initial.id}`)
    const pinned = await getWebBuildForSubmission(initial.id, 'author', 1)
    expect(pinned.page.title).toBe('读书会')

    const revised = await saveWebBuildDraft('author', { ...draftPage, title: '新版邀请' }, '换个标题', initial)
    await expect(publishWebBuild(initial.id, 'author', 1)).rejects.toMatchObject({ statusCode: 409 })
    expect((await getPublicWebBuild(initial.id)).releaseId).toBe(pinned.releaseId)
    const firstHTML = artifacts.get(`/_publish/${initial.id}/${pinned.releaseId}.html`)
    expect(firstHTML).toContain('读书会')
    await publishWebBuild(initial.id, 'author', revised.revision)
    const latest = await getPublicWebBuild(initial.id)
    expect(latest.releaseId).not.toBe(pinned.releaseId)
    expect(artifacts.get(`/_publish/${initial.id}/${latest.releaseId}.html`)).toContain('新版邀请')
    expect((await getPublicWebBuild(initial.id, pinned.releaseId)).releaseId).toBe(pinned.releaseId)
    expect(artifacts.get(`/_publish/${initial.id}/${pinned.releaseId}.html`)).toBe(firstHTML)

    await withdrawWebBuild(initial.id, 'author', revised.revision)
    await expect(getPublicWebBuild(initial.id)).rejects.toMatchObject({ statusCode: 404 })
    await expect(getPublicWebBuild(initial.id, pinned.releaseId)).rejects.toMatchObject({ statusCode: 404 })
  })

  it('refuses publication for content review rejection and review service failure', async () => {
    const { id } = await saveWebBuildDraft('author', draftPage, '创建邀请页')
    moderation.mockResolvedValueOnce({ suggestion: 'Review' })
    await expect(publishWebBuild(id, 'author', 1)).rejects.toMatchObject({ statusCode: 422 })
    moderation.mockResolvedValueOnce({ suggestion: 'Review', error: 'unavailable' })
    await expect(publishWebBuild(id, 'author', 1)).rejects.toMatchObject({ statusCode: 503 })
    await expect(getPublicWebBuild(id)).rejects.toMatchObject({ statusCode: 404 })
  })

  it('keeps a release private when the HTML upload fails', async () => {
    const { id } = await saveWebBuildDraft('author', draftPage, '创建邀请页')
    upload.mockResolvedValueOnce(new Response(null, { status: 503 }))
    await expect(publishWebBuild(id, 'author', 1)).rejects.toMatchObject({ statusCode: 503 })
    await expect(getPublicWebBuild(id)).rejects.toMatchObject({ statusCode: 404 })
    expect((await publishWebBuild(id, 'author', 1)).shareUrl).toBe(`${origin}/site/${id}`)
  })

  it('denies every released version on operational takedown and prevents republishing', async () => {
    const { id } = await saveWebBuildDraft('author', draftPage, '创建邀请页')
    await publishWebBuild(id, 'author', 1)
    const { releaseId } = await getWebBuildForSubmission(id, 'author', 1)
    documents.set(id, { ...documents.get(id), blockedAt: Date.now() })
    await expect(getPublicWebBuild(id)).rejects.toMatchObject({ statusCode: 404 })
    await expect(getPublicWebBuild(id, releaseId)).rejects.toMatchObject({ statusCode: 404 })
    await expect(publishWebBuild(id, 'author', 1)).rejects.toMatchObject({ statusCode: 404 })
  })

  it('caps generation attempts per author', async () => {
    for (let attempt = 0; attempt < 8; attempt++)
      await reserveWebBuildAction('author', 'generate')
    await expect(reserveWebBuildAction('author', 'generate')).rejects.toMatchObject({ statusCode: 429 })
    await expect(reserveWebBuildAction('another-user', 'generate')).resolves.toBeUndefined()
  })
})

describe('web build membership at the HTTP routes', () => {
  const nativeFetch = globalThis.fetch
  const gateway = 'https://fixture-env.api.tcloudbasegateway.com'
  const runtimeOrigin = 'https://runtime.example.test'
  const signingSecret = 'b'.repeat(64)
  const fixtureBearer = 'Bearer fixture-member'
  let server: ReturnType<typeof createServer>
  let api: string
  let enabled: boolean
  let pilotUid: string
  let profile: { sub: string, phone_verified: boolean, status: string }
  let membership: unknown
  const account = vi.fn()
  const model = vi.fn()

  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    const [availability, list, detail, write, manifest] = await Promise.all([
      import('../../server/api/web-builds/availability.get'),
      import('../../server/api/web-builds/index.get'),
      import('../../server/api/web-builds/[id].get'),
      import('../../server/api/web-builds/index.post'),
      import('../../server/api/web-builds/public/[...parts].get'),
    ])
    const router = createRouter()
    router.get('/api/web-builds/availability', availability.default)
    router.get('/api/web-builds', list.default)
    router.get('/api/web-builds/public/**', manifest.default)
    router.get('/api/web-builds/:id', detail.default)
    router.post('/api/web-builds', write.default)
    server = createServer(toNodeListener(createApp().use(router)))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    api = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/web-builds`
  })

  beforeEach(() => {
    clearCloudbaseAuthCache()
    enabled = true
    pilotUid = ''
    profile = { sub: 'author', phone_verified: true, status: 'ACTIVE' }
    membership = { isActive: true, expireAt: Date.now() + 86_400_000 }
    account.mockReset().mockImplementation(async () => Response.json({ coin: 0, membership }))
    model.mockReset().mockImplementation(async () => Response.json({ result: { content: JSON.stringify(page) } }))
    vi.stubGlobal('useRuntimeConfig', () => ({
      webBuildEnabled: enabled,
      webBuildWriteToken: token,
      webBuildRuntimeOrigin: runtimeOrigin,
      webBuildRuntimeSigningSecret: signingSecret,
      webBuildPilotUid: pilotUid,
      public: { tcbEnvId: 'fixture-env' },
    }))
    vi.stubGlobal('fetch', vi.fn(async (url: string | URL, options: RequestInit) => {
      switch (String(url)) {
        case `${gateway}/auth/v1/user/me`: return Response.json(profile)
        case `${gateway}/v1/functions/account-api`:
          expect(options.headers).toHaveProperty('Authorization', fixtureBearer)
          expect(options.redirect).toBe('error')
          expect(JSON.parse(String(options.body))).toEqual({ action: 'getAccount' })
          return account()
        case `${runtimeOrigin}/ai/v1/chat`: {
          expect(options.headers).toMatchObject({ 'Authorization': fixtureBearer, 'X-Application-Id': 'web-build', 'Origin': 'https://apps.yunle.fun' })
          expect(options.redirect).toBe('error')
          const requestId = (options.headers as Record<string, string>)['Idempotency-Key']!
          const { applicationId, messages, attestation } = JSON.parse(String(options.body))
          expect(applicationId).toBe('web-build')
          expect(messages).toMatchObject([{ role: 'system' }, { role: 'user' }])
          const digest = createHash('sha256').update(JSON.stringify(messages)).digest('hex')
          expect(attestation.signature).toBe(createHmac('sha256', signingSecret)
            .update(['v1', applicationId, requestId, String(attestation.timestamp), digest].join('\n')).digest('hex'))
          return model()
        }
        default: return upload(String(url), options)
      }
    }))
  })

  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })

  function request(path = '', body?: Record<string, unknown>, authorization = fixtureBearer) {
    return nativeFetch(api + path, {
      method: body ? 'POST' : 'GET',
      headers: { 'Accept': 'application/json', 'Content-Type': 'application/json', ...(authorization ? { Authorization: authorization } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    })
  }

  it('keeps the feature off by default and requires login and phone verification when enabled', async () => {
    enabled = false
    const off = await request('/availability', undefined, '')
    expect(await off.json()).toEqual({ enabled: false })
    expect(off.headers.get('cache-control')).toBe('private, no-store')
    expect((await request('', { action: 'generate', prompt: '读书会' })).status).toBe(503)
    enabled = true
    expect((await request('/availability', undefined, '')).status).toBe(401)
    profile.phone_verified = false
    expect((await request('/availability')).status).toBe(403)
    expect(account).not.toHaveBeenCalled()
    expect(documents.size).toBe(0)
    expect(model).not.toHaveBeenCalled()
  })

  it.each([false, true])('rejects inactive and expired memberships on every author route (active flag %s)', async (isActive) => {
    membership = { isActive, expireAt: Date.now() - 1 }
    const id = '1'.repeat(32)
    const requests = [request('/availability'), request(), request(`/${id}`), ...['generate', 'publish', 'withdraw', 'submit'].map(action =>
      request('', { action, id, revision: 1, prompt: '读书会' }))]
    for (const response of await Promise.all(requests)) {
      expect(response.status).toBe(403)
      expect(response.headers.get('cache-control')).toBe('private, no-store')
      expect(await response.json()).toMatchObject({ data: { code: 'MEMBERSHIP_REQUIRED' } })
    }
    expect(documents.size).toBe(0)
    expect(model).not.toHaveBeenCalled()
    expect(upload).not.toHaveBeenCalled()
  })

  it('does not start generation when the account service is unavailable or returns an invalid expiry', async () => {
    account.mockResolvedValueOnce(new Response(null, { status: 502 }))
    expect((await request('', { action: 'generate', prompt: '读书会' })).status).toBe(503)
    membership = { isActive: true, expireAt: 'invalid' }
    expect((await request('', { action: 'generate', prompt: '读书会' })).status).toBe(503)
    expect(model).not.toHaveBeenCalled()
    expect(documents.size).toBe(0)
  })

  it('admits only the configured member during a production pilot', async () => {
    enabled = false
    pilotUid = 'different-user'
    expect((await request('/availability')).status).toBe(503)
    expect(account).not.toHaveBeenCalled()
    pilotUid = 'author'
    expect(await (await request('/availability')).json()).toEqual({ enabled: true })
    membership = { isActive: false, expireAt: null }
    expect((await request('', { action: 'generate', prompt: '读书会' })).status).toBe(403)
    expect(model).not.toHaveBeenCalled()
  })

  it('allows a verified member to generate, revise and publish and serves published versions without login', async () => {
    const availability = await request('/availability')
    expect(await availability.json()).toEqual({ enabled: true })
    expect(availability.headers.get('cache-control')).toBe('private, no-store')
    const generated = await request('', { action: 'generate', prompt: '做一个读书会邀请页' })
    expect(generated.status).toBe(200)
    const { id } = await generated.json()
    expect(await (await request()).json()).toEqual([expect.objectContaining({ id, title: page.title })])
    expect(await (await request(`/${id}`)).json()).toMatchObject({ id, page })
    model.mockResolvedValueOnce(Response.json({ result: { content: `\`\`\`json\n${JSON.stringify({ ...page, title: '海边读书会' })}\n\`\`\`` } }))
    const revised = await request('', { action: 'generate', id, revision: 1, prompt: '修改标题' })
    expect(await revised.json()).toMatchObject({ id, revision: 2, page: { title: '海边读书会' } })
    const published = await request('', { action: 'publish', id, revision: 2 })
    expect(await published.json()).toMatchObject({ id, shareUrl: `${origin}/site/${id}`, publishedRevision: 2 })
    expect(await (await request('', { action: 'submit', id, revision: 2 })).json()).toEqual({ slug: 'submitted' })

    account.mockClear()
    enabled = false
    const manifest = await request(`/public/${id}`, undefined, '')
    expect(manifest.status).toBe(200)
    expect(await manifest.json()).toMatchObject({ releaseId: expect.stringMatching(/^[0-9a-f]{32}$/), sha256: expect.stringMatching(/^[0-9a-f]{64}$/) })
    expect(account).not.toHaveBeenCalled()
  })
})
