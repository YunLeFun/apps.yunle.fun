import type { FeaturedAppRecord, WeeklyChartRecord } from '~/types/homeScreen'
import { setResponseHeader } from 'h3'
import { createCloudbaseCatalogResolver } from '../../domain/catalog/cloudbase'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'

/** Public editorial references only; app metadata still comes from the approved catalog. */
export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'no-store')
  const { db } = useCloudbaseAdmin()
  const now = Date.now()
  const offset = 8 * 60 * 60 * 1000
  const localDay = new Date(now + offset)
  const dayStart = Date.UTC(localDay.getUTCFullYear(), localDay.getUTCMonth(), localDay.getUTCDate()) - offset
  const weekStart = dayStart - ((localDay.getUTCDay() + 6) % 7) * 24 * 60 * 60 * 1000
  const [catalog, featuredResult, chartResult] = await Promise.all([
    createCloudbaseCatalogResolver(db).resolveCatalog({ surface: 'public_market' }, null),
    db.collection('featured_apps').where({ isActive: true }).orderBy('sortOrder', 'asc').limit(50).get(),
    db.collection('weekly_charts').where({ weekStart }).orderBy('rank', 'asc').limit(10).get(),
  ])

  function resolveReference(reference: string): string | null {
    const matches = catalog.apps.filter(app => app._id === reference || app.slug === reference || app.marketShortName === reference)
    return matches.length === 1 ? matches[0]!._id : null
  }
  const text = (value: unknown, limit: number) => typeof value === 'string' ? value.trim().slice(0, limit) || undefined : undefined
  const featuredIDs = new Set<string>()
  const featured = (Array.isArray(featuredResult.data) ? featuredResult.data as FeaturedAppRecord[] : [])
    .filter(record => record.isActive === true && ['daily', 'editor'].includes(record.type)
      && Number.isFinite(record.startDate) && Number.isFinite(record.endDate)
      && record.startDate <= now && record.endDate > now)
    .flatMap((record) => {
      const appId = typeof record.appId === 'string' ? resolveReference(record.appId) : null
      if (!appId || featuredIDs.has(appId))
        return []
      featuredIDs.add(appId)
      return [{ appId, title: text(record.title, 100), subtitle: text(record.subtitle, 240), startsAt: record.startDate, expiresAt: record.endDate }]
    })
    .slice(0, 10)
  const rankedIDs = new Set<string>()
  const ranks = new Set<number>()
  const items = (Array.isArray(chartResult.data) ? chartResult.data as WeeklyChartRecord[] : [])
    .filter(record => record.weekStart === weekStart && Number.isInteger(record.rank) && record.rank >= 1 && record.rank <= 10)
    .sort((left, right) => left.rank - right.rank)
    .flatMap((record) => {
      const appId = typeof record.appId === 'string' ? resolveReference(record.appId) : null
      if (!appId || rankedIDs.has(appId) || ranks.has(record.rank))
        return []
      rankedIDs.add(appId)
      ranks.add(record.rank)
      return [{ appId, rank: record.rank }]
    })

  return { schemaVersion: 1, generatedAt: now, featured, weeklyChart: items.length ? { weekStart, items } : null }
})
