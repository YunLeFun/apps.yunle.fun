import type { AppRecord, CreateAppForm } from '../../app/types/app'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useApps } from '../../app/composables/useApps'

const api = vi.fn()
const where = vi.fn()
const get = vi.fn()
const limit = vi.fn(() => ({ get }))
const collection = vi.fn(() => ({ where }))

function appRecord(overrides: Partial<AppRecord> = {}): AppRecord {
  return {
    _id: 'app_1',
    writeVersion: 'a'.repeat(64),
    ownerLogin: 'YunYouJun',
    ownerUid: 'uid-1',
    name: '示例应用',
    slug: 'example',
    websiteUrl: 'https://example.yunle.fun/',
    privacyPolicyUrl: 'https://example.yunle.fun/privacy',
    supportUrl: 'https://support.yunle.fun',
    isPublic: false,
    accessMode: 'public',
    releaseStage: 'stable',
    status: 'pending',
    publicationStatus: 'unpublished',
    createdAt: 1,
    updatedAt: 1,
    ...overrides,
  }
}

function form(overrides: Partial<CreateAppForm> = {}): CreateAppForm {
  return {
    name: '示例应用',
    slug: 'example',
    websiteUrl: 'https://example.yunle.fun/',
    isPublic: true,
    accessMode: 'public',
    releaseStage: 'stable',
    ...overrides,
  }
}

describe('useApps server-mediated submission flow', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    where.mockReturnValue({ limit })
    vi.stubGlobal('useNuxtApp', () => ({ $api: api }))
    vi.stubGlobal('useCloudbase', () => ({
      app: { database: () => ({ collection }) },
    }))
  })

  it('reads submission access and owner list from Nitro APIs', async () => {
    api
      .mockResolvedValueOnce({
        canSubmitFirstParty: true,
        thirdPartyEnabled: false,
        thirdPartyMessage: '第三方应用入驻敬请期待',
      })
      .mockResolvedValueOnce({ items: [appRecord()] })

    const apps = useApps()
    await expect(apps.getSubmissionAccess()).resolves.toMatchObject({ canSubmitFirstParty: true })
    await expect(apps.getMyApps()).resolves.toHaveLength(1)
    expect(api).toHaveBeenNthCalledWith(1, '/api/apps/access')
    expect(api).toHaveBeenNthCalledWith(2, '/api/apps/mine')
  })

  it('returns an owned app by slug and maps a server 404 to null', async () => {
    api
      .mockResolvedValueOnce({ app: appRecord() })
      .mockRejectedValueOnce({ statusCode: 404 })
    const apps = useApps()

    await expect(apps.getMyAppBySlug('example')).resolves.toMatchObject({ slug: 'example' })
    await expect(apps.getMyAppBySlug('missing')).resolves.toBeNull()
  })

  it('reads the published public projection through the Nitro API', async () => {
    api.mockResolvedValue({ app: appRecord({ isPublic: true, status: 'approved', publicationStatus: 'published' }) })
    const apps = useApps()

    await expect(apps.getPublicAppBySlug('example')).resolves.toMatchObject({ slug: 'example' })
    expect(api).toHaveBeenCalledWith('/api/apps/public/example')
    expect(collection).not.toHaveBeenCalled()
  })

  it('falls back to the public projection when the owner endpoint is unauthorized', async () => {
    api
      .mockRejectedValueOnce({ statusCode: 401 })
      .mockResolvedValueOnce({ app: appRecord({ isPublic: true, status: 'approved', publicationStatus: 'published' }) })

    await expect(useApps().getAppBySlug('example')).resolves.toMatchObject({ slug: 'example' })
    expect(api).toHaveBeenNthCalledWith(2, '/api/apps/public/example')
  })

  it('creates a first-party submission through the server', async () => {
    api.mockResolvedValue({
      app: appRecord(),
      submission: { _id: 'submission_1' },
    })
    const input = form({ accessMode: 'invite_only', releaseStage: 'beta' })

    await expect(useApps().createApp(input)).resolves.toBe('app_1')
    expect(api).toHaveBeenCalledWith('/api/apps/submissions', {
      method: 'POST',
      body: { kind: 'first_party', ...input },
    })
  })

  it('creates a new immutable submission when editing', async () => {
    api
      .mockResolvedValueOnce({ app: appRecord(), submission: { _id: 'submission_2' } })

    await useApps().updateApp(appRecord({ description: '旧简介' }), { description: '新简介' })

    expect(api).toHaveBeenNthCalledWith(1, '/api/apps/app_1/submissions', {
      method: 'POST',
      headers: { 'If-Match': `"${'a'.repeat(64)}"` },
      body: expect.objectContaining({
        kind: 'first_party',
        slug: 'example',
        description: '新简介',
      }),
    })
  })

  it('refuses to rebase an edit without a captured owner version', async () => {
    api.mockResolvedValue({ items: [] })
    await expect(useApps().updateApp(appRecord({ writeVersion: undefined }), { name: '无权' })).rejects.toThrow('版本信息')
    expect(api).not.toHaveBeenCalled()
  })

  it('rejects multiline version values before constructing request headers', async () => {
    const app = appRecord({ writeVersion: `${'a'.repeat(64)}\n` })
    await expect(useApps().deleteApp(app)).rejects.toThrow('版本信息')
    expect(api).not.toHaveBeenCalled()
  })

  it('soft-delists through the server and checks slug availability there', async () => {
    api
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce({ taken: true })
    const apps = useApps()

    await apps.deleteApp(appRecord())
    await expect(apps.isSlugTaken('example')).resolves.toBe(true)
    expect(api).toHaveBeenNthCalledWith(1, '/api/apps/app_1', { method: 'DELETE', headers: { 'If-Match': `"${'a'.repeat(64)}"` } })
    expect(api).toHaveBeenNthCalledWith(2, '/api/apps/slug', { query: { slug: 'example' } })
  })

  it('can explicitly make a private work public when submitting it to YunLeFun', async () => {
    api.mockResolvedValue({
      appId: 'app_1',
      submissionId: 'submission_2',
      reviewStatus: 'pending',
    })

    await useApps().submitPublicMarket(appRecord(), { makePublic: true })

    expect(api).toHaveBeenCalledWith('/api/apps/app_1/public-market', {
      method: 'POST',
      headers: { 'If-Match': `"${'a'.repeat(64)}"` },
      body: { makePublic: true, shortName: undefined },
    })
  })
})
