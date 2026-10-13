import { describe, expect, it } from 'vitest'
import { offlineCatalog } from '../../electron/catalog'
import { APP_ICON_URLS, appIconUrl } from '../../shared/app-icons'

describe('curated desktop icon assets', () => {
  it('contains unique HTTPS objects on the already permitted COS origin', () => {
    const entries = Object.entries(APP_ICON_URLS)
    expect(entries).toHaveLength(28)
    expect(new Set(entries.map(([, value]) => value)).size).toBe(entries.length)
    for (const [slug, value] of entries) {
      const url = new URL(value)
      expect(url.origin).toBe('https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com')
      expect(url.pathname).toBe(`/desktop/app-icons/v1/${slug}.webp`)
      expect([url.username, url.password, url.port, url.search, url.hash]).toEqual(['', '', '', '', ''])
      expect(appIconUrl(slug)).toBe(value)
    }
    const offline = offlineCatalog()
    expect(offline.length).toBeGreaterThan(0)
    expect(offline.filter(app => !appIconUrl(app.slug)).map(app => app.slug)).toEqual([])
  })

  it('selects fallback for unknown slugs, URLs and inherited property names', () => {
    for (const slug of ['unknown', '../cook', 'cook?token=private', 'https://example.com/icon.png', '__proto__', 'constructor', 'toString'])
      expect(appIconUrl(slug)).toBe('')
  })
})
