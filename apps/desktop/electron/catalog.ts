import type { AppRecord, CatalogAppInfo } from '@yunlefun/app-core'
import type { CatalogEntry, CatalogState } from '../shared/desktop'
import fs from 'node:fs/promises'
import path from 'node:path'
import { GENERATED_APPS, recordToAppInfo, withCanonicalAppDomain, withCanonicalAppIcon } from '@yunlefun/app-core'

export const CATALOG_ENDPOINT = 'https://apps.yunle.fun/api/apps/public'

// The old snapshot generator omits accessMode/audience. Only these known public,
// anonymous applications are usable offline until the snapshot includes policy.
const OFFLINE_PUBLIC_SLUGS = new Set([
  'cook',
  'give-me-money',
  'electric-fan',
  'air-conditioner',
  'dayun-kicker',
  'paper-star',
  'sponsors',
  'wc-github-corners',
  'explosions',
  'star-markdown-css',
  'augma',
  'ak-ui',
  'web-resume',
  'birthday',
  'go-far-away',
  'char-dust',
  'color-dust',
  'chat-generator',
  'fc',
])

export function isCatalogUrl(input: unknown, testOrigin?: string): input is string {
  if (typeof input !== 'string')
    return false
  try {
    const url = new URL(input)
    if (url.username || url.password)
      return false
    if (testOrigin && url.origin === testOrigin)
      return true
    // Never let remotely supplied metadata navigate a guest to local services.
    return url.protocol === 'https:' && !url.port
      && /^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(url.hostname)
      && !/^\d+(?:\.\d+){3}$/.test(url.hostname)
      && !/(?:^|\.)(?:localhost|local|internal|test|invalid)$/.test(url.hostname)
  }
  catch { return false }
}

export function toCatalogEntry(app: CatalogAppInfo, testOrigin?: string): CatalogEntry {
  const websiteUrl = isCatalogUrl(app.websiteUrl, testOrigin)
    ? new URL(app.websiteUrl).href
    : typeof app.websiteUrl === 'string' ? app.websiteUrl : ''
  let unavailableReason = ''
  if (!isCatalogUrl(app.websiteUrl, testOrigin))
    unavailableReason = '此应用暂不支持在桌面端打开'
  else if (app.accessMode && app.accessMode !== 'public')
    unavailableReason = '此应用需要登录或邀请，请先在 Web 或移动端使用'
  else if (app.requiresMembership)
    unavailableReason = '此应用需要会员，请先在 Web 或移动端使用'
  else if (app.coinCost !== undefined && (!Number.isFinite(app.coinCost) || app.coinCost !== 0))
    unavailableReason = '此应用需要购买，请先在 Web 或移动端使用'
  return {
    id: app.id || app.slug,
    slug: app.slug,
    name: app.name,
    description: app.description || '',
    emoji: app.emoji || '📱',
    category: app.category || '其他',
    websiteUrl,
    available: !unavailableReason,
    unavailableReason,
  }
}

export function offlineCatalog(): CatalogEntry[] {
  return GENERATED_APPS
    .filter(app => OFFLINE_PUBLIC_SLUGS.has(app.slug))
    .map(app => toCatalogEntry(withCanonicalAppIcon(withCanonicalAppDomain(app))))
    .filter(app => app.available)
}

function isPublicRecord(value: unknown): value is AppRecord {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return false
  const item = value as Record<string, unknown>
  return ['_id', 'slug', 'name'].every(key => typeof item[key] === 'string' && !!item[key])
    && /^[a-z0-9][\w.-]{0,127}$/i.test(item.slug as string)
    && /^[a-z0-9][\w.-]{0,127}$/i.test(item._id as string)
    && item.isPublic === true && item.status === 'approved'
    && (item.audience === undefined || item.audience === 'public')
    && item.publicationStatus === 'published'
}

export function parsePublicCatalog(payload: unknown, testOrigin?: string) {
  if (!payload || typeof payload !== 'object' || !Array.isArray((payload as { items?: unknown }).items))
    throw new Error('Invalid public catalog response')
  const records = (payload as { items: unknown[] }).items.filter(isPublicRecord)
  const seen = new Set<string>()
  const entries = records.map(record => toCatalogEntry(recordToAppInfo(record), testOrigin))
    .filter((entry) => {
      if (seen.has(entry.slug))
        return false
      seen.add(entry.slug)
      return true
    })
  return { records, entries }
}

interface CatalogOptions {
  cacheFile: string
  onChange: (state: CatalogState) => void
  endpoint?: string
  testOrigin?: string
  fetcher?: typeof fetch
}

/** The main process alone owns endpoint selection and authoritative app URLs. */
export class PublicCatalog {
  state: CatalogState = { apps: offlineCatalog(), source: 'snapshot', loading: false, error: '', updatedAt: null }
  private inflight?: Promise<void>

  constructor(private options: CatalogOptions) {}

  private notify() {
    this.options.onChange(this.state)
  }

  async restore() {
    try {
      const cache = JSON.parse(await fs.readFile(this.options.cacheFile, 'utf8'))
      if (cache.version !== 1 || typeof cache.updatedAt !== 'number')
        return
      const { entries } = parsePublicCatalog(cache, this.options.testOrigin)
      this.state = { apps: entries, source: 'cache', loading: false, error: '', updatedAt: cache.updatedAt }
      this.notify()
    }
    catch { /* A missing or invalid cache leaves the bundled public snapshot. */ }
  }

  get(appId: string): CatalogEntry {
    const entry = this.state.apps.find(item => item.id === appId || item.slug === appId)
    if (!entry?.available)
      throw new Error(entry?.unavailableReason || '此应用不存在或已下架，请刷新目录')
    return entry
  }

  refresh(): Promise<void> {
    if (this.inflight)
      return this.inflight
    this.inflight = this.load().finally(() => {
      this.inflight = undefined
    })
    return this.inflight
  }

  private async load() {
    this.state = { ...this.state, loading: true, error: '' }
    this.notify()
    try {
      const response = await (this.options.fetcher || fetch)(this.options.endpoint || CATALOG_ENDPOINT, {
        redirect: 'error',
        credentials: 'omit',
        signal: AbortSignal.timeout(8000),
      })
      if (!response.ok)
        throw new Error(`Catalog returned ${response.status}`)
      const { records, entries } = parsePublicCatalog(await response.json(), this.options.testOrigin)
      const updatedAt = Date.now()
      // An empty successful catalog is authoritative, including on next launch.
      this.state = { apps: entries, source: 'online', loading: false, error: '', updatedAt }
      try {
        await fs.mkdir(path.dirname(this.options.cacheFile), { recursive: true })
        const pendingFile = `${this.options.cacheFile}.pending`
        await fs.writeFile(pendingFile, JSON.stringify({ version: 1, updatedAt, items: records }), 'utf8')
        await fs.rename(pendingFile, this.options.cacheFile)
      }
      catch { /* A storage failure must not revert the online catalog. */ }
    }
    catch {
      this.state = { ...this.state, loading: false, error: '暂时无法刷新目录，正在使用本地快照或缓存' }
    }
    this.notify()
  }
}
