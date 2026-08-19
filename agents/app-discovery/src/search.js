import Fuse from 'fuse.js/basic'

const DEFAULT_LIMIT = 6
const MAX_LIMIT = 6
const MIN_FUZZY_QUERY_LENGTH = 4

const FUZZY_SEARCH_KEYS = [
  { name: 'name', weight: 0.4 },
  { name: 'slug', weight: 0.25 },
  { name: 'tags', weight: 0.15 },
  { name: 'category', weight: 0.08 },
  { name: 'developer', weight: 0.07 },
  { name: 'description', weight: 0.05 },
]

export function searchAppsInMemory(records, input) {
  const category = stringValue(input.category)
  const terms = tokenizeQuery(input.query)
  const limit = normalizeLimit(input.limit)
  const candidates = records
    .map((record, order) => ({ record, order }))
    .filter(({ record }) => record?.isPublic === true && record?.status === 'approved')
    .filter(({ record }) => !category || record.category === category)

  if (terms.length === 0) {
    return candidates
      .sort(comparePopularity)
      .slice(0, limit)
      .map(({ record }) => recordToAgentCard(record, defaultReason(record)))
  }

  const deterministic = candidates
    .map(({ record, order }) => scoreApp(record, terms, order))
    .filter(item => item.matchScore > 0)
    .sort(compareDeterministic)

  const fuzzy = fuzzySearchApps(candidates, terms, new Set(deterministic.map(item => item.record._id)))

  return [
    ...deterministic.map(item => item.card),
    ...fuzzy,
  ].slice(0, limit)
}

function fuzzySearchApps(candidates, terms, excludedIds) {
  const fuzzyTerms = terms.filter(term => term.length >= MIN_FUZZY_QUERY_LENGTH)
  if (fuzzyTerms.length === 0)
    return []

  const documents = candidates.map(({ record, order }) => ({
    record,
    order,
    name: normalizeText(record.name),
    slug: normalizeText(record.slug),
    tags: Array.isArray(record.tags) ? record.tags.map(normalizeText) : [],
    category: normalizeText(record.category),
    developer: [record.developerName, record.developer, record.ownerLogin]
      .map(normalizeText)
      .filter(Boolean),
    description: normalizeText(record.description),
  }))
  const bestById = new Map()

  for (const term of fuzzyTerms) {
    const fuse = new Fuse(documents, {
      keys: FUZZY_SEARCH_KEYS,
      threshold: term.length <= 4 ? 0.25 : 0.35,
      ignoreLocation: true,
      ignoreDiacritics: true,
      includeScore: true,
      minMatchCharLength: 2,
      shouldSort: true,
    })

    for (const result of fuse.search(term)) {
      const id = result.item.record._id
      if (excludedIds.has(id))
        continue
      const score = result.score ?? 1
      const existing = bestById.get(id)
      if (!existing || score < existing.score)
        bestById.set(id, { ...result.item, score, term })
    }
  }

  return [...bestById.values()]
    .sort((a, b) => a.score - b.score || comparePopularity(a, b))
    .map(item => recordToAgentCard(item.record, `名称或标识与「${item.term}」近似匹配`))
}

function scoreApp(record, terms, order) {
  let matchScore = 0
  let bestMatchScore = 0
  let bestReason = defaultReason(record)

  for (const term of terms) {
    const match = scoreTerm(record, term)
    matchScore += match.score
    if (match.score > bestMatchScore && match.reason) {
      bestMatchScore = match.score
      bestReason = match.reason
    }
  }

  return {
    card: recordToAgentCard(record, bestReason),
    matchScore,
    order,
    popularity: popularityScore(record),
    record,
  }
}

function scoreTerm(record, term) {
  const name = normalizeText(record.name)
  const slug = normalizeText(record.slug)
  const description = normalizeText(record.description)
  const category = normalizeText(record.category)
  const owner = normalizeText(record.ownerLogin)
  const developerName = normalizeText(record.developerName)
  const tags = Array.isArray(record.tags) ? record.tags.map(normalizeText) : []

  if (name === term)
    return { score: 120, reason: `名称匹配「${record.name}」` }
  if (slug === term)
    return { score: 95, reason: `标识匹配「${record.slug}」` }
  if (name.includes(term))
    return { score: 70, reason: `名称包含「${term}」` }
  if (slug.includes(term))
    return { score: 45, reason: `标识包含「${term}」` }
  if (category && category === term)
    return { score: 42, reason: `${record.category} 分类匹配` }
  if (tags.includes(term))
    return { score: 36, reason: `标签匹配「${term}」` }
  if (tags.some(tag => tag.includes(term)))
    return { score: 28, reason: `标签包含「${term}」` }
  if (category && category.includes(term))
    return { score: 24, reason: `${record.category} 分类相关` }
  if (description.includes(term))
    return { score: 16, reason: `描述包含「${term}」` }
  if (owner.includes(term) || developerName.includes(term))
    return { score: 10, reason: `开发者匹配「${term}」` }

  return { score: 0, reason: '' }
}

function compareDeterministic(a, b) {
  return b.matchScore - a.matchScore
    || b.popularity - a.popularity
    || a.order - b.order
}

function comparePopularity(a, b) {
  return popularityScore(b.record) - popularityScore(a.record)
    || a.order - b.order
}

function popularityScore(record) {
  return (numberValue(record.rating) || 0) * 0.4
    + Math.min(numberValue(record.ratingCount) || 0, 50) * 0.04
}

function defaultReason(record) {
  return stringValue(record.category) ? `${record.category} 分类应用` : '公开审核应用'
}

function recordToAgentCard(record, reason) {
  return {
    id: stringValue(record._id),
    slug: stringValue(record.slug) || '',
    name: stringValue(record.name) || '',
    description: stringValue(record.description),
    logo: stringValue(record.logo),
    emoji: stringValue(record.emoji) || '📱',
    themeColor: stringValue(record.themeColor) || '#007AFF',
    category: stringValue(record.category),
    rating: numberValue(record.rating),
    ratingCount: numberValue(record.ratingCount),
    coinCost: numberValue(record.coinCost),
    requiresMembership: booleanValue(record.requiresMembership),
    websiteUrl: stringValue(record.websiteUrl),
    trustedHosts: Array.isArray(record.trustedHosts)
      ? record.trustedHosts.filter(item => typeof item === 'string' && item.length > 0)
      : undefined,
    reason,
  }
}

export function normalizeLimit(limit) {
  if (typeof limit !== 'number' || !Number.isFinite(limit))
    return DEFAULT_LIMIT
  return Math.max(1, Math.min(MAX_LIMIT, Math.floor(limit)))
}

export function tokenizeQuery(query) {
  if (typeof query !== 'string')
    return []

  const normalized = normalizeText(query)
  if (!normalized)
    return []

  const terms = new Set([normalized])
  const decomposedQuery = query
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLocaleLowerCase()

  for (const segment of decomposedQuery.split(/[\p{P}\p{S}\s]+/gu)) {
    const term = normalizeText(segment)
    if (term)
      terms.add(term)
  }

  const cjk = decomposedQuery.match(/\p{Script=Han}+/gu) || []
  for (const segment of cjk) {
    if (segment.length <= 1)
      continue
    for (let index = 0; index < segment.length - 1; index += 1)
      terms.add(segment.slice(index, index + 2))
  }

  return [...terms]
}

export function normalizeText(value) {
  if (typeof value !== 'string')
    return ''

  return value
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLocaleLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '')
}

function stringValue(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined
}

function numberValue(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

function booleanValue(value) {
  return typeof value === 'boolean' ? value : undefined
}
