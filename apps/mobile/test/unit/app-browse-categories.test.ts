import { describe, expect, it } from 'vitest'
import {
  getAvailableBrowseCategories,
  getBrowseCategory,
  matchesBrowseCategory,
  normalizeBrowseCategorySelection,
} from '~/utils/appBrowseCategories'

describe('browse categories', () => {
  it('combines legacy labels into stable groups without changing records', () => {
    const apps = Object.freeze([
      Object.freeze({ id: 'plugin', category: '插件' }),
      Object.freeze({ id: 'design', category: ' 设计 ' }),
      Object.freeze({ id: 'tool', category: '工具' }),
      Object.freeze({ id: 'efficient', category: '效率工具' }),
      Object.freeze({ id: 'participation', category: '参与' }),
      Object.freeze({ id: 'lab', category: '实验' }),
      Object.freeze({ id: 'developer', category: '开发' }),
      Object.freeze({ id: 'life', category: '生活' }),
      Object.freeze({ id: 'game', category: '游戏' }),
      Object.freeze({ id: 'fun', category: '整活' }),
      Object.freeze({ id: 'ai', category: 'AI' }),
    ])

    expect(getAvailableBrowseCategories(apps).map(({ name, count }) => [name, count])).toEqual([
      ['全部', 11],
      ['效率工具', 2],
      ['创意设计', 1],
      ['生活方式', 1],
      ['游戏', 1],
      ['趣味娱乐', 1],
      ['AI', 1],
      ['开发', 4],
    ])
    expect(apps[0].category).toBe('插件')
    expect(apps[1].category).toBe(' 设计 ')
  })

  it('classifies known generic built-ins by stable ID before the slug', () => {
    expect(getBrowseCategory({ id: 'cook', slug: 'renamed-cook', category: '应用' })).toBe('生活方式')
    expect(getBrowseCategory({ id: 'ai-sfc', slug: 'cook', category: '应用' })).toBe('AI')
    expect(getBrowseCategory({ id: 'cloud-document', slug: 'char-dust', category: '应用' })).toBe('创意设计')
    expect(getBrowseCategory({ slug: 'color-dust', category: '应用' })).toBe('创意设计')
    expect(getBrowseCategory({ slug: 'pixi-painter', category: '应用' })).toBe('创意设计')
    expect(getBrowseCategory({ slug: 'birthday', category: '应用' })).toBe('趣味娱乐')
    expect(getBrowseCategory({ slug: 'go-far-away', category: '应用' })).toBe('生活方式')
  })

  it('respects explicit metadata instead of overriding every matching slug', () => {
    expect(getBrowseCategory({ id: 'cook', category: '游戏' })).toBe('游戏')
    expect(getBrowseCategory({ slug: 'pixi-painter', category: '效率工具' })).toBe('效率工具')
    expect(getBrowseCategory({ slug: 'ai-sfc', category: '教育' })).toBe('教育')
    expect(getBrowseCategory({ slug: 'cook' })).toBe('其他')
  })

  it('shows legacy Pixi Painter under creative design without reclassifying other tools', () => {
    const painter = Object.freeze({ id: 'pixi-painter', slug: 'renamed-painter', category: '工具' })
    const apps = [painter, { slug: 'unrelated-tool', category: '工具' }]

    expect(getBrowseCategory(painter)).toBe('创意设计')
    expect(apps.filter(app => matchesBrowseCategory(app, '创意设计'))).toEqual([painter])
    expect(apps.filter(app => matchesBrowseCategory(app, '效率工具'))).toHaveLength(1)
    expect(getAvailableBrowseCategories(apps).map(({ name, count }) => [name, count])).toEqual([
      ['全部', 2],
      ['效率工具', 1],
      ['创意设计', 1],
    ])
    expect(painter.category).toBe('工具')
    expect(getBrowseCategory({ slug: 'pixi-painter', category: '游戏' })).toBe('游戏')
  })

  it('shows legacy FC under games while respecting other entertainment and explicit metadata', () => {
    const game = Object.freeze({ id: 'cloud-document', slug: 'fc', category: '整活' })
    const apps = [game, { slug: 'unrelated-fun-app', category: '整活' }]

    expect(getBrowseCategory(game)).toBe('游戏')
    expect(apps.filter(app => matchesBrowseCategory(app, '游戏'))).toEqual([game])
    expect(apps.filter(app => matchesBrowseCategory(app, '趣味娱乐'))).toHaveLength(1)
    expect(getAvailableBrowseCategories(apps).map(({ name, count }) => [name, count])).toEqual([
      ['全部', 2],
      ['游戏', 1],
      ['趣味娱乐', 1],
    ])
    expect(game.category).toBe('整活')
    expect(getBrowseCategory({ id: 'fc', category: '教育' })).toBe('教育')
    expect(getBrowseCategory({ slug: 'fc', category: '应用' })).toBe('其他')
  })

  it('retains uncategorized applications and custom categories in scope counts', () => {
    const apps = [
      { category: ' 音乐 ' },
      { category: '应用', slug: 'unknown-app' },
      {},
      { category: '' },
      { category: '全部' },
      { category: '教育' },
      { category: '音乐' },
      { category: '其他' },
    ]
    const categories = getAvailableBrowseCategories(apps)

    expect(categories.map(({ name, count }) => [name, count])).toEqual([
      ['全部', 8],
      ['其他', 5],
      ['音乐', 2],
      ['教育', 1],
    ])
    expect(new Set(categories.map(category => category.id)).size).toBe(categories.length)
    expect(categories.slice(1).reduce((total, category) => total + category.count, 0)).toBe(apps.length)
    for (const category of categories) {
      expect(apps.filter(app => matchesBrowseCategory(app, category.name))).toHaveLength(category.count)
    }
  })

  it('keeps the all option for an empty scope and hides unused groups', () => {
    expect(getAvailableBrowseCategories([])).toEqual([
      { id: 'all', name: '全部', icon: '📱', count: 0 },
    ])
  })

  it('accepts renamed filters and exact generic or custom legacy selections', () => {
    expect(normalizeBrowseCategorySelection(' 设计 ')).toBe('创意设计')
    expect(normalizeBrowseCategorySelection('工具')).toBe('效率工具')
    expect(normalizeBrowseCategorySelection(' 音乐 ')).toBe('音乐')
    expect(normalizeBrowseCategorySelection('')).toBe('全部')
    expect(matchesBrowseCategory({ category: '效率工具' }, '工具')).toBe(true)
    expect(matchesBrowseCategory({ category: '设计' }, '创意设计')).toBe(true)
    expect(matchesBrowseCategory({ slug: 'cook', category: '应用' }, '应用')).toBe(true)
    expect(matchesBrowseCategory({ slug: 'cook', category: '应用' }, '其他')).toBe(false)
    expect(matchesBrowseCategory({ category: ' 音乐 ' }, '音乐')).toBe(true)
    expect(matchesBrowseCategory({ category: '游戏' }, '创意设计')).toBe(false)
    expect(matchesBrowseCategory({}, '全部')).toBe(true)
  })
})
