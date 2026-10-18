import type { CloudbaseAdminDb } from './cloudbase-admin'
import type { AppIconAssets, AppRecord } from '~/types/app'
import { normalizeAppSearchText, tokenizeAppSearchQuery } from '~/utils/app-search'
import { catalogAppViewToRecord, createCloudbaseCatalogResolver } from '../domain/catalog/cloudbase'

export interface SearchAppsInput {
  query: string
  category?: string
  limit?: number
}

export interface AgentSearchAppCard {
  id: string
  slug: string
  name: string
  description?: string
  logo?: string
  iconAssets?: AppIconAssets
  emoji?: string
  themeColor?: string
  category?: string
  rating?: number
  ratingCount?: number
  coinCost?: number
  requiresMembership?: boolean
  websiteUrl?: string
  trustedHosts?: string[]
  reason: string
}

interface SearchAppsOptions {
  db?: CloudbaseAdminDb
  candidateLimit?: number
}

interface ScoredApp {
  card: AgentSearchAppCard
  score: number
  order: number
}

const DEFAULT_LIMIT = 6
const MAX_LIMIT = 6
const DEFAULT_CANDIDATE_LIMIT = 100

export async function searchApps(
  input: SearchAppsInput,
  options: SearchAppsOptions = {},
): Promise<AgentSearchAppCard[]> {
  const limit = normalizeLimit(input.limit)
  const view = await createCloudbaseCatalogResolver(options.db).resolveCatalog({ surface: 'public_market' }, null)
  const candidateLimit = Math.max(1, Math.min(1000, Math.floor(options.candidateLimit || DEFAULT_CANDIDATE_LIMIT)))
  return searchAppsInMemory(view.apps.slice(0, candidateLimit).map(catalogAppViewToRecord), input, limit)
}

export function searchAppsInMemory(
  records: AppRecord[],
  input: SearchAppsInput,
  resolvedLimit = normalizeLimit(input.limit),
): AgentSearchAppCard[] {
  const category = input.category?.trim()
  const terms = tokenizeQuery(input.query)

  return records
    .map((record, order) => ({ record, order }))
    .filter(({ record }) => isPublicApproved(record))
    .filter(({ record }) => !category || record.category === category)
    .map(({ record, order }) => scoreApp(record, terms, order))
    .filter(item => item.score > 0 || terms.length === 0)
    .sort((a, b) => b.score - a.score || (b.card.rating ?? 0) - (a.card.rating ?? 0) || a.order - b.order)
    .slice(0, resolvedLimit)
    .map(item => item.card)
}

function scoreApp(record: AppRecord, terms: string[], order: number): ScoredApp {
  let score = 0
  let bestReason = record.category ? `${record.category} 分类应用` : '公开审核应用'

  for (const term of terms) {
    const match = scoreTerm(record, term)
    score += match.score
    if (match.score > 0 && match.reason)
      bestReason = match.reason
  }

  score += (record.rating ?? 0) * 0.4
  score += Math.min(record.ratingCount ?? 0, 50) * 0.04

  return {
    card: recordToAgentCard(record, bestReason),
    score,
    order,
  }
}

function scoreTerm(record: AppRecord, term: string) {
  const name = normalizeText(record.name)
  const slug = normalizeText(record.slug)
  const description = normalizeText(record.description)
  const category = normalizeText(record.category)
  const owner = normalizeText(record.ownerLogin)
  const developerName = normalizeText(record.developerName)
  const tags = (record.tags ?? []).map(normalizeText)

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

function recordToAgentCard(record: AppRecord, reason: string): AgentSearchAppCard {
  return {
    id: record._id,
    slug: record.marketShortName || record._id,
    name: record.name,
    description: record.description,
    logo: record.logo,
    ...(record.iconAssets ? { iconAssets: record.iconAssets } : {}),
    emoji: record.emoji || '📱',
    themeColor: record.themeColor || '#007AFF',
    category: record.category,
    rating: record.rating,
    ratingCount: record.ratingCount,
    coinCost: record.coinCost,
    requiresMembership: record.requiresMembership,
    websiteUrl: record.websiteUrl,
    trustedHosts: record.trustedHosts,
    reason,
  }
}

function isPublicApproved(record: AppRecord) {
  return record.isPublic === true
    && record.status === 'approved'
    && record.publicationStatus === 'published'
}

function normalizeLimit(limit: number | undefined) {
  if (typeof limit !== 'number' || !Number.isFinite(limit))
    return DEFAULT_LIMIT
  return Math.max(1, Math.min(MAX_LIMIT, Math.floor(limit)))
}

function tokenizeQuery(query: string) {
  return tokenizeAppSearchQuery(query)
}

function normalizeText(value: unknown) {
  return normalizeAppSearchText(value)
}
