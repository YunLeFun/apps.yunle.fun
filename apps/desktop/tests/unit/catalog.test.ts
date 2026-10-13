import type { AppRecord } from '@yunlefun/app-core'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { CATALOG_ENDPOINT, isCatalogUrl, offlineCatalog, parsePublicCatalog, PublicCatalog } from '../../electron/catalog'

const temporary: string[] = []
afterEach(async () => {
  await Promise.all(temporary.splice(0).map(directory => fs.rm(directory, { recursive: true, force: true })))
})
function record(extra: Partial<AppRecord> = {}): AppRecord {
  return {
    _id: 'public-app',
    slug: 'public-app',
    name: '公开应用',
    ownerLogin: 'yunlefun',
    websiteUrl: 'https://demo.yunle.fun/',
    isPublic: true,
    audience: 'public',
    status: 'approved',
    publicationStatus: 'published',
    createdAt: 1,
    updatedAt: 1,
    ...extra,
  }
}
async function directory() {
  const location = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-catalog-test-'))
  temporary.push(location)
  return location
}
function response(items: AppRecord[]) {
  return new Response(JSON.stringify({ items }), { headers: { 'Content-Type': 'application/json' } })
}

describe('trusted public application catalog', () => {
  it('bundles only explicitly public anonymous fallback apps and uses the shared canonical URLs', () => {
    const apps = offlineCatalog()
    expect(apps.find(app => app.slug === 'cook')?.available).toBe(true)
    expect(apps.find(app => app.slug === 'give-me-money')?.websiteUrl).toBe('https://gmm.yunle.fun/')
    expect(apps.find(app => app.slug === 'everything-generator')).toBeUndefined()
    expect(apps.every(app => app.available && isCatalogUrl(app.websiteUrl))).toBe(true)
  })
  it('rejects local services, credentials, non-HTTPS URLs and unrelated loopback origins', () => {
    expect(isCatalogUrl('https://cook.yunle.fun/')).toBe(true)
    for (const url of ['http://demo.yunle.fun', 'https://localhost', 'https://127.0.0.1', 'https://[::1]', 'https://host.local', 'https://user:password@demo.yunle.fun/', 'file:///secret', 'app://shell', 'https://example.com:8443/'])
      expect(isCatalogUrl(url)).toBe(false)
    expect(isCatalogUrl('http://127.0.0.1:4000/app', 'http://127.0.0.1:4000')).toBe(true)
    expect(isCatalogUrl('http://127.0.0.1:4001/app', 'http://127.0.0.1:4000')).toBe(false)
  })
  it('projects only published public records and disables account, paid and member apps', () => {
    const { entries } = parsePublicCatalog({ items: [
      record(),
      record({ _id: 'private', slug: 'private', audience: 'owner' }),
      record({ _id: 'unpublished', slug: 'unpublished', publicationStatus: 'unpublished' }),
      record({ _id: 'unapproved', slug: 'unapproved', status: 'pending' }),
      record({ _id: 'paid', slug: 'paid', coinCost: 10 }),
      record({ _id: 'member', slug: 'member', requiresMembership: true }),
      record({ _id: 'account', slug: 'account', accessMode: 'login_required' }),
      record({ _id: 'invite', slug: 'invite', accessMode: 'invite_only' }),
    ] })
    expect(entries.map(app => app.id)).toEqual(['public-app', 'paid', 'member', 'account', 'invite'])
    expect(entries.filter(app => app.available).map(app => app.id)).toEqual(['public-app'])
  })
  it('rejects malformed catalog envelopes and app identities', () => {
    expect(() => parsePublicCatalog({ data: [] })).toThrow()
    expect(parsePublicCatalog({ items: [record({ slug: '../../shell' }), record({ _id: 'https://evil.example' })] }).entries).toEqual([])
  })
  it('normalizes equivalent host URLs while preserving the full path and query', () => {
    expect(parsePublicCatalog({ items: [record({ websiteUrl: 'https://DEMO.yunle.fun:443' })] }).entries[0].websiteUrl)
      .toBe('https://demo.yunle.fun/')
    expect(parsePublicCatalog({ items: [record({ websiteUrl: 'https://demo.yunle.fun/Editor?mode=write#draft' })] }).entries[0].websiteUrl)
      .toBe('https://demo.yunle.fun/Editor?mode=write#draft')
  })
  it('requests only the fixed public API without cookies or redirects', async () => {
    const fetcher = vi.fn().mockResolvedValue(response([record()]))
    const catalog = new PublicCatalog({ cacheFile: path.join(await directory(), 'catalog.json'), onChange: vi.fn(), fetcher })
    await catalog.refresh()
    expect(fetcher).toHaveBeenCalledWith(CATALOG_ENDPOINT, expect.objectContaining({ credentials: 'omit', redirect: 'error' }))
    expect(catalog.state.source).toBe('online')
    expect(catalog.get('public-app').websiteUrl).toBe('https://demo.yunle.fun/')
    expect(() => catalog.get('cook')).toThrow()
    expect(() => catalog.get('https://arbitrary.example')).toThrow()
  })
  it('replaces an authoritative empty list and preserves the deletion across a cold start', async () => {
    const cacheFile = path.join(await directory(), 'catalog.json')
    const fetcher = vi.fn().mockResolvedValueOnce(response([record()])).mockResolvedValueOnce(response([]))
    const catalog = new PublicCatalog({ cacheFile, onChange: vi.fn(), fetcher })
    await catalog.refresh()
    await catalog.refresh()
    expect(catalog.state.apps).toEqual([])
    const restored = new PublicCatalog({ cacheFile, onChange: vi.fn(), fetcher })
    await restored.restore()
    expect(restored.state.source).toBe('cache')
    expect(restored.state.apps).toEqual([])
    expect(() => restored.get('public-app')).toThrow()
    expect(() => restored.get('cook')).toThrow()
  })
  it('keeps only the last authoritative cache during failure and rejects gated IDs', async () => {
    const cacheFile = path.join(await directory(), 'catalog.json')
    const fetcher = vi.fn().mockResolvedValueOnce(response([record({ coinCost: 1 })])).mockRejectedValueOnce(new Error('offline'))
    const catalog = new PublicCatalog({ cacheFile, onChange: vi.fn(), fetcher })
    await catalog.refresh()
    expect(() => catalog.get('public-app')).toThrow()
    await catalog.refresh()
    expect(catalog.state.apps.map(app => app.id)).toEqual(['public-app'])
    expect(catalog.state.error).toBeTruthy()
  })
})
