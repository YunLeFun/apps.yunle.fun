import { describe, expect, it, vi } from 'vitest'
import { catalogURL, readDesktopAssets, readOnlineCatalog, readWebsiteAssets, renderDesktopAssets, renderNativeAssets } from '../../scripts/sync-catalog-icons.mjs'

function asset(slug = 'cook', version = 'v2') {
  return { slug, desktopAsset: { kind: 'official', usage: 'desktop-selected', version, thumbnail: {
    url: `https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/desktop/app-icons/${version}/${slug}.webp`,
    width: 256,
    height: 256,
    mime: 'image/webp',
    bytes: 2000,
    sha256: 'a'.repeat(64),
  } } }
}

describe('central icon catalog sync', () => {
  it('syncs centrally registered website bindings into a URL-only native fallback', () => {
    const website = { origin: 'https://admin.yunle.fun', icon: 'brand-app-icon', url: 'https://icons.yunle.fun/products/brand/app-icon.svg', sha256: 'a'.repeat(64) }
    const selected = asset()
    selected.desktopAsset.kind = 'generated'
    const source = JSON.stringify({ schemaVersion: 1, assets: [selected], websiteIcons: [website] })
    expect(readWebsiteAssets(source)).toEqual([website])
    expect(renderNativeAssets(source)).toContain('"https://admin.yunle.fun": WebsiteAsset(url: "https://icons.yunle.fun/products/brand/app-icon.svg", role: .appIcon')
    for (const patch of [{ origin: 'https://admin.yunle.fun/path' }, { url: 'https://example.com/brand-app-icon.svg' }, { icon: 'bad' }, { sha256: 'bad' }]) {
      expect(() => readWebsiteAssets(JSON.stringify({ websiteIcons: [{ ...website, ...patch }] }))).toThrow()
    }
    expect(() => readWebsiteAssets(JSON.stringify({ websiteIcons: [website, website] }))).toThrow()
  })
  it('reads the shared online catalog and uses only its source mirror when unavailable', async () => {
    const source = JSON.stringify({ schemaVersion: 1, assets: [asset()] })
    const fetchCatalog = vi.fn().mockResolvedValueOnce(new Response(source))
    expect(await readOnlineCatalog(fetchCatalog)).toBe(source)
    expect(fetchCatalog.mock.calls[0][0]).toBe(catalogURL)
    expect(fetchCatalog).toHaveBeenCalledTimes(1)
    fetchCatalog.mockReset().mockRejectedValueOnce(new Error('ECONNRESET')).mockResolvedValueOnce(new Response(source))
    const warning = vi.spyOn(console, 'warn').mockImplementation(() => {})
    try {
      expect(await readOnlineCatalog(fetchCatalog)).toBe(source)
      expect(fetchCatalog.mock.calls[1][0]).toBe('https://raw.githubusercontent.com/YunLeFun/icons/main/assets/catalog/app-assets.json')
      expect(warning).toHaveBeenCalledOnce()
    }
    finally { warning.mockRestore() }
  })

  it('syncs selected desktop assets without promoting candidate variants', () => {
    const assets = [asset('fc'), { ...asset(), candidates: [asset('cook', 'v1')] }]
    const source = JSON.stringify({ schemaVersion: 1, assets })
    expect(readDesktopAssets(source).map(([slug]) => slug)).toEqual(['cook', 'fc'])
    const output = renderDesktopAssets(source)
    expect(output).toContain('/v2/cook.webp')
    expect(output).not.toContain('/v1/cook.webp')
    expect(output).toContain('Source SHA-256:')
    expect(renderDesktopAssets(source)).toBe(output)
  })

  it('rejects duplicate slugs and malformed or empty catalogs', () => {
    for (const manifest of [{ schemaVersion: 2, assets: [asset()] }, { schemaVersion: 1, assets: [] }, { schemaVersion: 1, assets: [asset(), asset()] }])
      expect(() => readDesktopAssets(JSON.stringify(manifest))).toThrow()
    for (const patch of [{ usage: 'comparison-only' }, { status: 'candidate' }, { version: 'v1' }, { kind: 'unverified' }]) {
      const selected = asset()
      const modified = { ...selected, desktopAsset: { ...selected.desktopAsset, ...patch } }
      expect(() => readDesktopAssets(JSON.stringify({ schemaVersion: 1, assets: [modified] }))).toThrow()
    }
  })

  it('rejects foreign origins, signed URLs, wrong assets and invalid image metadata', () => {
    const base = asset()
    const image = base.desktopAsset.thumbnail
    for (const patch of [
      { url: 'https://example.com/cook.webp' },
      { url: `${image.url}?token=private` },
      { url: image.url.replace('cook.webp', 'fc.webp') },
      { width: 1024 },
      { mime: 'image/png' },
      { sha256: '' },
    ]) {
      const modified = { ...base, desktopAsset: { ...base.desktopAsset, thumbnail: { ...image, ...patch } } }
      expect(() => readDesktopAssets(JSON.stringify({ schemaVersion: 1, assets: [modified] }))).toThrow()
    }
  })

  it('shares official sources and selected fallbacks with both native platforms', () => {
    const official = asset()
    official.desktopAsset.source = { kind: 'official-source', url: 'https://cook.yunle.fun/brand/cook-app-icon.svg', sha256: 'b'.repeat(64) }
    const generated = asset('air-conditioner', 'v1')
    generated.desktopAsset.kind = 'generated'
    generated.candidates = [{ url: 'https://example.com/never-selected.svg' }]
    const source = JSON.stringify({ schemaVersion: 1, assets: [official, generated] })
    const output = renderNativeAssets(source)
    expect(output).toContain('official: "https://cook.yunle.fun/brand/cook-app-icon.svg"')
    expect(output).toContain('"air-conditioner": Asset(official: nil')
    expect(output).toContain('/v2/cook.webp')
    expect(output).not.toContain('never-selected')
    expect(output.match(/Source SHA-256: (.*)/)[1]).toBe(renderDesktopAssets(source).match(/Source SHA-256: (.*)/)[1])
  })

  it('rejects invalid official sources instead of generating a partially valid snapshot', () => {
    for (const url of ['http://example.com/a.svg', 'https://user:secret@example.com/a.svg', 'https://example.com/a.svg?token=private', 'https://example.com/page.html']) {
      const selected = asset()
      selected.desktopAsset.source = { kind: 'official-source', url, sha256: 'b'.repeat(64) }
      expect(() => renderNativeAssets(JSON.stringify({ schemaVersion: 1, assets: [selected] }))).toThrow()
    }
  })
})
