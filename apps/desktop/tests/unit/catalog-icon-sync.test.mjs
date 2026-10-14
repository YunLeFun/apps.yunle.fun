import { describe, expect, it } from 'vitest'
import { readDesktopAssets, renderDesktopAssets } from '../../scripts/sync-catalog-icons.mjs'

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
})
