import type { AppRecord } from '../../app/types/app'
import { describe, expect, it } from 'vitest'
import { searchAppsInMemory } from '../../server/utils/agent-search-apps'

function makeApp(slug: string, overrides: Partial<AppRecord> = {}): AppRecord {
  return {
    _id: slug,
    _openid: `user-${slug}`,
    ownerLogin: 'yunyou',
    name: slug,
    slug,
    description: '',
    emoji: '📱',
    themeColor: '#007AFF',
    category: '工具',
    tags: [],
    rating: 0,
    ratingCount: 0,
    isPublic: true,
    status: 'approved',
    createdAt: 1,
    updatedAt: 1,
    ...overrides,
  }
}

describe('agent search_apps tool', () => {
  it('only returns public approved apps', () => {
    const cards = searchAppsInMemory([
      makeApp('public-approved', { name: '公开工具' }),
      makeApp('private-approved', { name: '私有工具', isPublic: false }),
      makeApp('public-pending', { name: '待审工具', status: 'pending' }),
    ], { query: '工具' })

    expect(cards.map(card => card.slug)).toEqual(['public-approved'])
  })

  it('scores keyword matches across name, category, tags, description, and developer', () => {
    const cards = searchAppsInMemory([
      makeApp('weather', {
        name: '天气工具',
        category: '生活',
        tags: ['天气'],
        description: '查看天气',
      }),
      makeApp('code-helper', {
        name: '代码助手',
        category: '开发',
        tags: ['工具', '代码'],
        description: '适合开发者写代码',
        ownerLogin: 'dev-team',
      }),
      makeApp('notes', {
        name: '灵感记录',
        category: '效率',
        tags: ['笔记'],
      }),
    ], { query: '开发工具' })

    expect(cards.map(card => card.slug)).toEqual(['code-helper', 'weather'])
    expect(cards[0]).toMatchObject({
      slug: 'code-helper',
      name: '代码助手',
      reason: expect.any(String),
    })
  })

  it('filters by category and caps output at six cards with stable ordering', () => {
    const records = Array.from({ length: 8 }, (_, index) =>
      makeApp(`tool-${index}`, {
        name: `工具 ${index}`,
        category: index === 7 ? '生活' : '工具',
        rating: 4,
      }))

    const cards = searchAppsInMemory(records, {
      query: '工具',
      category: '工具',
      limit: 20,
    })

    expect(cards).toHaveLength(6)
    expect(cards.map(card => card.slug)).toEqual([
      'tool-0',
      'tool-1',
      'tool-2',
      'tool-3',
      'tool-4',
      'tool-5',
    ])
  })

  it('returns the public card schema only', () => {
    const [card] = searchAppsInMemory([
      makeApp('paid-tool', {
        name: '付费工具',
        description: '需要云币',
        coinCost: 9,
        requiresMembership: true,
        trustedHosts: ['tool.example.com'],
        websiteUrl: 'https://tool.example.com',
      }),
    ], { query: '付费' })

    expect(card).toEqual({
      id: 'paid-tool',
      slug: 'paid-tool',
      name: '付费工具',
      description: '需要云币',
      logo: undefined,
      emoji: '📱',
      themeColor: '#007AFF',
      category: '工具',
      rating: 0,
      ratingCount: 0,
      coinCost: 9,
      requiresMembership: true,
      websiteUrl: 'https://tool.example.com',
      trustedHosts: ['tool.example.com'],
      reason: expect.any(String),
    })
    expect(card).not.toHaveProperty('isPublic')
    expect(card).not.toHaveProperty('status')
    expect(card).not.toHaveProperty('ownerLogin')
    expect(card).not.toHaveProperty('tags')
  })
})
