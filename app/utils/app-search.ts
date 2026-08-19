import type { IFuseOptions } from 'fuse.js'
import Fuse from 'fuse.js/basic'

/** Fields supported by the application catalog search. */
export interface SearchableApp {
  name: string
  slug?: string
  description?: string
  category?: string
  tags?: string[]
  developer?: string
  developerName?: string
  ownerLogin?: string
}

interface WeightedSearchField {
  values: string[]
  exact: number
  prefix: number
  contains: number
}

interface FuzzySearchDocument<T> {
  item: T
  name: string
  slug: string
  tags: string[]
  category: string
  developer: string[]
  description: string
}

const MIN_FUZZY_QUERY_LENGTH = 4
const STRONG_DETERMINISTIC_SCORE = 200

const FUZZY_SEARCH_KEYS: IFuseOptions<FuzzySearchDocument<unknown>>['keys'] = [
  { name: 'name', weight: 0.4 },
  { name: 'slug', weight: 0.25 },
  { name: 'tags', weight: 0.15 },
  { name: 'category', weight: 0.08 },
  { name: 'developer', weight: 0.07 },
  { name: 'description', weight: 0.05 },
]

/**
 * Normalize catalog text so punctuation, symbols, spacing, case, and diacritics
 * don't prevent equivalent application names from matching.
 *
 * @param value - User query or catalog field value.
 * @returns A compact, case-insensitive search key.
 */
export function normalizeAppSearchText(value: unknown): string {
  if (typeof value !== 'string')
    return ''

  return value
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLocaleLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '')
}

/**
 * Build compact query terms for scored search, including CJK bigrams.
 *
 * @param query - Raw user-entered search query.
 * @returns Unique normalized terms, with the full compact query first.
 */
export function tokenizeAppSearchQuery(query: unknown): string[] {
  if (typeof query !== 'string')
    return []

  const normalizedQuery = normalizeAppSearchText(query)
  if (!normalizedQuery)
    return []

  const terms = new Set<string>([normalizedQuery])
  const decomposedQuery = query
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLocaleLowerCase()

  for (const segment of decomposedQuery.split(/[\p{P}\p{S}\s]+/gu)) {
    const term = normalizeAppSearchText(segment)
    if (term)
      terms.add(term)
  }

  const cjkSegments = decomposedQuery.match(/\p{Script=Han}+/gu) ?? []
  for (const segment of cjkSegments) {
    if (segment.length <= 1)
      continue
    for (let index = 0; index < segment.length - 1; index += 1)
      terms.add(segment.slice(index, index + 2))
  }

  return [...terms]
}

/**
 * Rank matching applications using deterministic field relevance.
 *
 * Exact and prefix name matches rank first, followed by slug, tags, category,
 * developer, and description matches. An empty query preserves source order.
 *
 * @param items - Values containing searchable application metadata.
 * @param query - Raw user-entered search query.
 * @param getApp - Extracts searchable metadata from each value.
 * @returns Matching values ordered by relevance, then their original order.
 */
export function rankAppSearch<T>(
  items: readonly T[],
  query: string,
  getApp: (item: T) => SearchableApp,
): T[] {
  const normalizedQuery = normalizeAppSearchText(query)
  if (!normalizedQuery)
    return [...items]

  const requiredTerms = query
    .split(/[\p{P}\p{S}\s]+/gu)
    .map(normalizeAppSearchText)
    .filter(Boolean)

  const deterministicResults = items
    .map((item, index) => ({
      index,
      item,
      score: scoreAppSearchQuery(getApp(item), normalizedQuery, requiredTerms),
    }))
    .filter(result => result.score > 0)
    .sort((a, b) => b.score - a.score || a.index - b.index)

  if (normalizedQuery.length < MIN_FUZZY_QUERY_LENGTH)
    return deterministicResults.map(result => result.item)

  const hasStrongDeterministicMatch = deterministicResults.some(
    result => result.score >= STRONG_DETERMINISTIC_SCORE,
  )
  if (hasStrongDeterministicMatch)
    return deterministicResults.map(result => result.item)

  const deterministicItems = new Set(deterministicResults.map(result => result.item))
  return [
    ...deterministicResults.map(result => result.item),
    ...fuzzySearchApps(items, normalizedQuery, getApp)
      .filter(item => !deterministicItems.has(item)),
  ]
}

function fuzzySearchApps<T>(
  items: readonly T[],
  normalizedQuery: string,
  getApp: (item: T) => SearchableApp,
): T[] {
  const documents = items.map((item): FuzzySearchDocument<T> => {
    const app = getApp(item)
    return {
      item,
      name: normalizeAppSearchText(app.name),
      slug: normalizeAppSearchText(app.slug),
      tags: (app.tags ?? []).map(normalizeAppSearchText),
      category: normalizeAppSearchText(app.category),
      developer: [app.developerName, app.developer, app.ownerLogin]
        .map(normalizeAppSearchText)
        .filter(Boolean),
      description: normalizeAppSearchText(app.description),
    }
  })
  const fuse = new Fuse(documents, {
    keys: FUZZY_SEARCH_KEYS as IFuseOptions<FuzzySearchDocument<T>>['keys'],
    threshold: normalizedQuery.length <= 4 ? 0.25 : 0.35,
    ignoreLocation: true,
    ignoreDiacritics: true,
    minMatchCharLength: 2,
    shouldSort: true,
  })

  return fuse.search(normalizedQuery).map(result => result.item.item)
}

function scoreAppSearchQuery(
  app: SearchableApp,
  normalizedQuery: string,
  requiredTerms: string[],
): number {
  const directScore = scoreAppSearch(app, normalizedQuery)
  if (directScore > 0 || requiredTerms.length <= 1)
    return directScore

  const termScores = requiredTerms.map(term => scoreAppSearch(app, term))
  return termScores.every(score => score > 0)
    ? termScores.reduce((total, score) => total + score, 0) / termScores.length
    : 0
}

function scoreAppSearch(app: SearchableApp, query: string): number {
  const fields: WeightedSearchField[] = [
    { values: [app.name], exact: 1000, prefix: 900, contains: 800 },
    { values: [app.slug ?? ''], exact: 700, prefix: 650, contains: 600 },
    { values: app.tags ?? [], exact: 550, prefix: 500, contains: 450 },
    { values: [app.category ?? ''], exact: 400, prefix: 360, contains: 320 },
    {
      values: [app.developerName ?? '', app.developer ?? '', app.ownerLogin ?? ''],
      exact: 280,
      prefix: 240,
      contains: 200,
    },
    { values: [app.description ?? ''], exact: 160, prefix: 140, contains: 120 },
  ]

  let bestScore = 0
  for (const field of fields) {
    for (const value of field.values) {
      const normalizedValue = normalizeAppSearchText(value)
      if (!normalizedValue)
        continue
      if (normalizedValue === query)
        bestScore = Math.max(bestScore, field.exact)
      else if (normalizedValue.startsWith(query))
        bestScore = Math.max(bestScore, field.prefix)
      else if (normalizedValue.includes(query))
        bestScore = Math.max(bestScore, field.contains)
    }
  }

  return bestScore
}
