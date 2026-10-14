import type { BrowseCategory } from '@yunlefun/app-core/utils/appBrowseCategories'
import type { CatalogEntry } from '../../shared/desktop'
import { getAvailableBrowseCategories, getBrowseCategory, matchesBrowseCategory, normalizeBrowseCategorySelection } from '@yunlefun/app-core/utils/appBrowseCategories'

export { getBrowseCategory } from '@yunlefun/app-core/utils/appBrowseCategories'

export const DEFAULT_FEATURED_SLUGS = [
  'air-conditioner',
  'electric-fan',
  'char-dust',
  'color-dust',
  'pixi-painter',
  'fc',
] as const

const RECENT_LIMIT = 20

export function deriveCategories(apps: readonly CatalogEntry[]): string[] {
  return deriveBrowseCategories(apps).filter(category => category.name !== '全部').map(category => category.name)
}

/** Use the complete catalog so sidebar counts stay stable during search. */
export function deriveBrowseCategories(apps: readonly CatalogEntry[]): BrowseCategory[] {
  return getAvailableBrowseCategories(apps)
}

export function filterCatalog(apps: readonly CatalogEntry[], options: { query?: string, category?: string } = {}): CatalogEntry[] {
  const search = options.query?.trim().toLocaleLowerCase() || ''
  const category = normalizeBrowseCategorySelection(options.category || '')
  return apps.filter(app =>
    matchesBrowseCategory(app, category)
    && (!search || `${app.name} ${app.description} ${app.slug} ${getBrowseCategory(app)} ${app.category}`.toLocaleLowerCase().includes(search)),
  )
}

function resolveAvailableApps(apps: readonly CatalogEntry[], slugs: readonly string[]): CatalogEntry[] {
  const available = new Map(apps.filter(app => app.available).map(app => [app.slug, app]))
  return [...new Set(slugs)].flatMap((slug) => {
    const app = available.get(slug)
    return app ? [app] : []
  })
}

export function resolveFeatured(apps: readonly CatalogEntry[], slugs: readonly string[] = DEFAULT_FEATURED_SLUGS): CatalogEntry[] {
  return resolveAvailableApps(apps, slugs)
}

function isRecentSlug(value: unknown): value is string {
  return typeof value === 'string' && /^[a-z0-9][\w.-]{0,127}$/i.test(value)
}

function normalizeRecentSlugs(values: readonly unknown[]): string[] {
  const result: string[] = []
  for (const value of values) {
    if (!isRecentSlug(value) || result.includes(value))
      continue
    result.push(value)
    if (result.length === RECENT_LIMIT)
      break
  }
  return result
}

/** Local history contains bounded slugs only, never launch URLs or identities. */
export function parseRecentSlugs(raw: unknown): string[] {
  if (typeof raw !== 'string' || raw.length > 8192)
    return []
  try {
    const values: unknown = JSON.parse(raw)
    return Array.isArray(values) ? normalizeRecentSlugs(values) : []
  }
  catch { return [] }
}

export function promoteRecentSlug(current: readonly string[], slug: string): string[] {
  return normalizeRecentSlugs(isRecentSlug(slug) ? [slug, ...current] : current)
}

/** Missing or gated apps stay out of the view, including an empty online list. */
export function resolveRecentApps(apps: readonly CatalogEntry[], slugs: readonly string[]): CatalogEntry[] {
  return resolveAvailableApps(apps, normalizeRecentSlugs(slugs))
}
