import type { CatalogEntry } from '../../shared/desktop'
import { describe, expect, it } from 'vitest'
import { deriveBrowseCategories, deriveCategories, filterCatalog, getBrowseCategory, parseRecentSlugs, promoteRecentSlug, resolveFeatured, resolveRecentApps } from '../../app/utils/catalog-view'
import { offlineCatalog } from '../../electron/catalog'

function entry(slug: string, extra: Partial<CatalogEntry> = {}): CatalogEntry {
  return {
    id: `document-${slug}`,
    slug,
    name: slug,
    description: '',
    emoji: '📱',
    category: '应用',
    websiteUrl: `https://${slug}.example/`,
    available: true,
    unavailableReason: '',
    ...extra,
  }
}

describe('catalog views use current public metadata', () => {
  it('derives canonical groups in the same stable order as Web without synthetic empty groups', () => {
    const apps = [entry('one', { category: '设计' }), entry('two', { category: '开发' }), entry('three', { category: '设计' })]
    expect(deriveCategories(apps)).toEqual(['创意设计', '开发'])
    expect(deriveCategories(apps.slice(1, 2))).toEqual(['开发'])
    expect(deriveCategories([])).toEqual([])
    expect(deriveBrowseCategories([])).toEqual([{ id: 'all', name: '全部', icon: '📱', count: 0 }])
  })

  it('searches names, descriptions and slugs with category filtering while retaining unavailable rows', () => {
    const apps = [
      entry('air-conditioner', { name: '云空调', description: '便携夏日小空调', category: '整活' }),
      entry('char-dust', { name: 'Char Dust', description: '在线图片转字符画' }),
      entry('gated', { name: '会员设计工具', category: '设计', available: false }),
    ]
    expect(filterCatalog(apps, { query: '  CHAR DUST  ' }).map(app => app.slug)).toEqual(['char-dust'])
    expect(filterCatalog(apps, { query: 'air-conditioner', category: '整活' }).map(app => app.slug)).toEqual(['air-conditioner'])
    expect(filterCatalog(apps, { query: '图片', category: '整活' })).toEqual([])
    expect(filterCatalog(apps, { query: '图片' }).map(app => app.slug)).toEqual(['char-dust'])
    expect(filterCatalog(apps, { category: '设计' })).toEqual([apps[1], apps[2]])
    expect(filterCatalog(apps, { category: '', query: ' ' })).toEqual(apps)
  })

  it('classifies Pixi Painter and FC using shared rules without mutating their legacy metadata', () => {
    const apps = Object.freeze([
      Object.freeze(entry('pixi-painter', { category: '工具' })),
      Object.freeze(entry('fc', { category: '整活' })),
      Object.freeze(entry('char-dust')),
      Object.freeze(entry('cook')),
      Object.freeze(entry('ai-sfc')),
      Object.freeze(entry('tool', { category: '工具' })),
      Object.freeze(entry('plugin', { category: '插件' })),
      Object.freeze(entry('birthday')),
    ])

    expect(apps.map(getBrowseCategory)).toEqual(['创意设计', '游戏', '创意设计', '生活方式', 'AI', '效率工具', '开发', '趣味娱乐'])
    expect(filterCatalog(apps, { category: '创意设计' })).toEqual([apps[0], apps[2]])
    expect(filterCatalog(apps, { category: '游戏' })).toEqual([apps[1]])
    expect(filterCatalog(apps, { category: '效率工具' })).toEqual([apps[5]])
    expect(filterCatalog(apps, { category: '工具' })).toEqual([apps[5]])
    expect(filterCatalog(apps, { category: '整活' })).toEqual([apps[7]])
    expect(apps.map(app => app.category)).toEqual(['工具', '整活', '应用', '应用', '应用', '工具', '插件', '应用'])
  })

  it('keeps full-catalog counts independent of search and includes every unavailable or custom entry', () => {
    const apps = [
      entry('one', { category: '工具' }),
      entry('two', { category: '效率工具', available: false }),
      entry('three', { category: '教育' }),
      entry('four', { category: '' }),
    ]
    const categories = deriveBrowseCategories(apps)

    expect(categories.map(({ name, count }) => [name, count])).toEqual([
      ['全部', 4],
      ['效率工具', 2],
      ['其他', 1],
      ['教育', 1],
    ])
    expect(filterCatalog(apps, { query: 'one' })).toEqual([apps[0]])
    expect(deriveBrowseCategories(apps)).toEqual(categories)
    for (const category of categories)
      expect(filterCatalog(apps, { category: category.name })).toHaveLength(category.count)
  })

  it('searches canonical browse labels and applies group filtering before the query', () => {
    const apps = [entry('fc', { category: '整活' }), entry('pixi-painter', { category: '工具' }), entry('tool', { category: '工具' })]
    expect(filterCatalog(apps, { query: '创意设计' })).toEqual([apps[1]])
    expect(filterCatalog(apps, { query: '游戏' })).toEqual([apps[0]])
    expect(filterCatalog(apps, { category: '创意设计', query: '工具' })).toEqual([apps[1]])
    expect(filterCatalog(apps, { category: '效率工具', query: 'pixi' })).toEqual([])
  })

  it('resolves the six real featured slugs only when available in the current catalog', () => {
    const offline = offlineCatalog()
    expect(resolveFeatured(offline).map(app => app.slug)).toEqual(['air-conditioner', 'electric-fan', 'char-dust', 'color-dust', 'fc'])
    const pixi = entry('pixi-painter', { name: 'Pixi Painter', category: '工具' })
    expect(resolveFeatured([pixi, ...offline]).map(app => app.slug))
      .toEqual(['air-conditioner', 'electric-fan', 'char-dust', 'color-dust', 'pixi-painter', 'fc'])
    expect(resolveFeatured([entry('fc', { available: false })])).toEqual([])
    expect(resolveFeatured([], ['cook'])).toEqual([])
  })

  it('keeps editorial order, deduplicates selections and returns original entries without inventing metadata', () => {
    const apps = [entry('first'), entry('second')]
    const result = resolveFeatured(apps, ['second', 'absent', 'first', 'second'])
    expect(result).toEqual([apps[1], apps[0]])
    expect(result[0]).toBe(apps[1])
    expect(apps.map(app => app.slug)).toEqual(['first', 'second'])
  })
})

describe('bounded slug-only recent history', () => {
  it('rejects corrupt, oversized and non-array storage', () => {
    for (const raw of [null, undefined, 123, '', '{', '{}', JSON.stringify({ slug: 'cook' }), ' '.repeat(8193)])
      expect(parseRecentSlugs(raw)).toEqual([])
  })

  it('drops URLs, identities, malformed strings and duplicates while preserving recent order', () => {
    expect(parseRecentSlugs(JSON.stringify([
      'cook',
      'https://cook.yunle.fun/?token=secret',
      { slug: 'fc', account: 'private' },
      '../shell',
      '',
      ' char-dust ',
      null,
      7,
      'a'.repeat(129),
      'char-dust',
      'cook',
      'fc',
    ]))).toEqual(['cook', 'char-dust', 'fc'])
  })

  it('limits reads and promotions to twenty distinct valid slugs', () => {
    const current = Array.from({ length: 30 }, (_, index) => `app-${index}`)
    expect(parseRecentSlugs(JSON.stringify(current))).toEqual(current.slice(0, 20))
    expect(promoteRecentSlug(current.slice(0, 20), 'new-app')).toEqual(['new-app', ...current.slice(0, 19)])
    expect(promoteRecentSlug(current, 'app-9')).toEqual(['app-9', ...current.filter(slug => slug !== 'app-9').slice(0, 19)])
    expect(current).toHaveLength(30)
  })

  it('promotes an existing slug and ignores invalid launch identifiers', () => {
    expect(promoteRecentSlug(['cook', 'fc', 'cook'], 'fc')).toEqual(['fc', 'cook'])
    expect(promoteRecentSlug(['cook', 'fc'], 'https://arbitrary.example/')).toEqual(['cook', 'fc'])
  })

  it('resolves stable slugs to refreshed document IDs without restoring withdrawn or gated entries', () => {
    const refreshed = entry('cook', { id: 'new-document-id' })
    const apps = [entry('fc', { available: false }), refreshed, entry('char-dust')]
    expect(resolveRecentApps(apps, ['missing', 'char-dust', 'cook', 'cook', 'fc']))
      .toEqual([apps[2], refreshed])
    expect(resolveRecentApps([], ['cook', 'char-dust'])).toEqual([])
  })
})
