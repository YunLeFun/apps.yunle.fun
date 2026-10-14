import { describe, expect, it } from 'vitest'
import {
  normalizeAppSearchText,
  rankAppSearch,
  tokenizeAppSearchQuery,
} from '../../app/utils/app-search'

interface TestApp {
  name: string
  slug: string
  description?: string
  category?: string
  tags?: string[]
  developer?: string
}

function rank(apps: TestApp[], query: string): TestApp[] {
  return rankAppSearch(apps, query, app => app)
}

describe('application catalog search', () => {
  it('normalizes punctuation, symbols, spacing, case, width, and diacritics', () => {
    expect(normalizeAppSearchText(' Adv.JS Studio ')).toBe('advjsstudio')
    expect(normalizeAppSearchText('ＡＤＶ—ＪＳ')).toBe('advjs')
    expect(normalizeAppSearchText('Café App')).toBe('cafeapp')
  })

  it('matches a compact query against a punctuated application name', () => {
    const apps = [
      { name: 'Notes', slug: 'notes' },
      { name: 'Adv.js Studio', slug: 'adv-js-studio' },
    ]

    expect(rank(apps, 'advjs').map(app => app.slug)).toEqual(['adv-js-studio'])
  })

  it('recalls slug, tags, category, developer, and description fields', () => {
    const apps = [{
      name: '创作台',
      slug: 'creative-studio',
      tags: ['JavaScript'],
      category: '开发',
      developer: 'yunyoujun',
      description: '制作互动广告',
    }]

    for (const query of ['creative', 'javascript', '开发', 'yunyou', '互动广告'])
      expect(rank(apps, query)).toHaveLength(1)
  })

  it('ranks name matches ahead of slug, tags, and descriptions', () => {
    const apps = [
      { name: 'First', slug: 'first', description: 'advjs helper' },
      { name: 'Second', slug: 'second', tags: ['advjs'] },
      { name: 'Third', slug: 'advjs' },
      { name: 'Adv.js', slug: 'fourth' },
    ]

    expect(rank(apps, 'advjs').map(app => app.slug)).toEqual([
      'fourth',
      'advjs',
      'second',
      'first',
    ])
  })

  it('can satisfy separated query terms across multiple fields', () => {
    const apps = [
      { name: 'Studio', slug: 'studio', developer: 'yunyou' },
      { name: 'Studio', slug: 'studio-other', developer: 'someone' },
    ]

    expect(rank(apps, 'studio yunyou').map(app => app.slug)).toEqual(['studio'])
  })

  it('falls back to typo-tolerant matching when deterministic search is empty', () => {
    const apps = [
      { name: 'Notes', slug: 'notes' },
      { name: 'Adv.js Studio', slug: 'adv-js-studio' },
    ]

    expect(rank(apps, 'advjx').map(app => app.slug)).toEqual(['adv-js-studio'])
  })

  it('uses field weights to rank fuzzy name matches ahead of descriptions', () => {
    const apps = [
      { name: 'Code Notes', slug: 'notes', description: 'JavaScript reference' },
      { name: 'JavaScript Studio', slug: 'javascript-studio' },
    ]

    expect(rank(apps, 'javscript').map(app => app.slug)).toEqual([
      'javascript-studio',
      'notes',
    ])
  })

  it('appends typo-corrected names after weak deterministic description matches', () => {
    const apps = [
      { name: 'Reference', slug: 'reference', description: 'advjx reference' },
      { name: 'Adv.js Studio', slug: 'advjs-studio' },
    ]

    expect(rank(apps, 'advjx').map(app => app.slug)).toEqual([
      'reference',
      'advjs-studio',
    ])
  })

  it('does not mix fuzzy candidates into deterministic results', () => {
    const apps = [
      { name: 'Advjx', slug: 'exact' },
      { name: 'Adv.js Studio', slug: 'fuzzy' },
    ]

    expect(rank(apps, 'advjx').map(app => app.slug)).toEqual(['exact'])
  })

  it('disables fuzzy fallback for short queries', () => {
    const apps = [{ name: 'Application', slug: 'application' }]

    expect(rank(apps, 'apx')).toEqual([])
  })

  it('preserves source order for an empty query and equal scores', () => {
    const apps = [
      { name: 'Adv One', slug: 'one' },
      { name: 'Adv Two', slug: 'two' },
    ]

    expect(rank(apps, '').map(app => app.slug)).toEqual(['one', 'two'])
    expect(rank(apps, 'adv').map(app => app.slug)).toEqual(['one', 'two'])
  })

  it('tokenizes punctuation variants and CJK bigrams for agent search', () => {
    expect(tokenizeAppSearchQuery('Adv.js Studio')).toEqual([
      'advjsstudio',
      'adv',
      'js',
      'studio',
    ])
    expect(tokenizeAppSearchQuery('开发工具')).toEqual([
      '开发工具',
      '开发',
      '发工',
      '工具',
    ])
  })
})
