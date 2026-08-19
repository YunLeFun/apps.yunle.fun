import assert from 'node:assert/strict'
// This standalone deployment package intentionally uses Node's built-in runner.
// eslint-disable-next-line test/no-import-node-test
import { describe, it } from 'node:test'
import { searchAppsInMemory } from '../src/search.js'

function makeApp(slug, overrides = {}) {
  return {
    _id: slug,
    ownerLogin: 'yunyou',
    name: slug,
    slug,
    description: '',
    category: '工具',
    tags: [],
    rating: 0,
    ratingCount: 0,
    isPublic: true,
    status: 'approved',
    ...overrides,
  }
}

describe('CloudBase app-discovery search runtime', () => {
  it('matches punctuation-insensitive application names', () => {
    const results = searchAppsInMemory([
      makeApp('advjs-studio', { name: 'ADV.JS Studio' }),
    ], { query: 'advjs' })

    assert.deepEqual(results.map(item => item.slug), ['advjs-studio'])
  })

  it('uses Fuse typo tolerance when deterministic matching is empty', () => {
    const results = searchAppsInMemory([
      makeApp('notes', { name: 'Notes' }),
      makeApp('advjs-studio', { name: 'ADV.JS Studio' }),
    ], { query: 'advjx' })

    assert.deepEqual(results.map(item => item.slug), ['advjs-studio'])
    assert.match(results[0].reason, /近似匹配/)
  })

  it('keeps deterministic results first and appends fuzzy candidates', () => {
    const results = searchAppsInMemory([
      makeApp('description-match', {
        name: 'Reference',
        description: 'advjx reference',
      }),
      makeApp('advjs-studio', { name: 'ADV.JS Studio' }),
    ], { query: 'advjx' })

    assert.deepEqual(results.map(item => item.slug), [
      'description-match',
      'advjs-studio',
    ])
  })

  it('does not return popular but unrelated applications', () => {
    const results = searchAppsInMemory([
      makeApp('popular', { name: 'Weather', rating: 5, ratingCount: 50 }),
      makeApp('match', { name: 'ADV.JS Studio' }),
    ], { query: 'advjs' })

    assert.deepEqual(results.map(item => item.slug), ['match'])
  })

  it('does not fuzzy-match short queries', () => {
    const results = searchAppsInMemory([
      makeApp('application', { name: 'Application' }),
    ], { query: 'apx' })

    assert.deepEqual(results, [])
  })
})
