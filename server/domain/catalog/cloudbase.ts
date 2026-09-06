import type {
  CatalogAppRecord,
  CatalogAppView,
  CatalogDataSource,
  CatalogPublicationStatus,
  CatalogRevision,
  PersonalWorkshop,
  PublicMarketListing,
  WorkshopMembership,
} from '.'
import type { CloudbaseAdminDb } from '../../utils/cloudbase-admin'
import type { AppAudience, AppRecord, AppSubmission } from '~/types/app'
import { createHash } from 'node:crypto'
import { createCatalogResolver } from '.'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'

/** CloudBase Adapter for the catalog Module. */
export const PUBLIC_MARKET_LISTINGS_COLLECTION = 'public_market_listings'
export const PERSONAL_WORKSHOPS_COLLECTION = 'personal_workshops'
export const WORKSHOP_MEMBERSHIPS_COLLECTION = 'workshop_memberships'
export const WORKSHOP_EVENTS_COLLECTION = 'workshop_events'

const PAGE_SIZE = 100
const MAX_RECORDS = 1000

export function createCloudbaseCatalogResolver(
  db: CloudbaseAdminDb = useCloudbaseAdmin().db,
) {
  return createCatalogResolver(createCloudbaseCatalogDataSource(db))
}

export async function resolveOwnerUidByLogin(
  login: string,
  db: CloudbaseAdminDb = useCloudbaseAdmin().db,
): Promise<string | null> {
  const normalized = await db.collection('apps').where({ ownerLoginKey: login.toLowerCase() }).limit(1).get()
  const owner = first<AppRecord>(normalized.data)
  if (owner)
    return owner.ownerUid || owner._openid || null
  const { data } = await db.collection('apps')
    .where({ ownerLogin: login })
    .limit(1)
    .get()
  const record = first<AppRecord>(data)
  return record?.ownerUid || record?._openid || null
}

export function createCloudbaseCatalogDataSource(db: CloudbaseAdminDb): CatalogDataSource {
  return {
    async listApps() {
      const records = await listCollection<AppRecord>(db, 'apps')
      return records.map(normalizeCatalogApp).filter(isPresent)
    },
    async listPublicMarketListings() {
      return listCollection<PublicMarketListing>(db, PUBLIC_MARKET_LISTINGS_COLLECTION)
    },
    async getRevisions(ids) {
      if (!ids.length)
        return []
      const records: AppSubmission[] = []
      for (let offset = 0; offset < ids.length; offset += PAGE_SIZE) {
        const pageIds = ids.slice(offset, offset + PAGE_SIZE)
        const { data } = await db.collection('app_submissions')
          .where({ _id: db.command.in([...pageIds]) })
          .limit(pageIds.length)
          .get()
        records.push(...asArray<AppSubmission>(data))
      }
      return records.map(toCatalogRevision)
    },
    async getWorkshop(id) {
      const { data } = await db.collection(PERSONAL_WORKSHOPS_COLLECTION).doc(id).get()
      return first<PersonalWorkshop>(data)
    },
    async getMembership(workshopId, userUid) {
      const { data } = await db.collection(WORKSHOP_MEMBERSHIPS_COLLECTION)
        .doc(workshopMembershipId(workshopId, userUid))
        .get()
      return first<WorkshopMembership>(data)
    },
  }
}

export function catalogAppViewToRecord(view: CatalogAppView): AppRecord {
  return {
    _id: view._id,
    marketShortName: view.marketShortName,
    ownerLogin: view.ownerLogin || '',
    name: view.name,
    slug: view.slug,
    description: view.description,
    githubRepo: view.githubRepo,
    websiteUrl: view.websiteUrl,
    privacyPolicyUrl: view.privacyPolicyUrl,
    supportUrl: view.supportUrl,
    trustedHosts: view.trustedHosts,
    backupUrl: view.backupUrl,
    logo: view.logo,
    iconAssets: view.iconAssets,
    emoji: view.emoji,
    themeColor: view.themeColor,
    category: view.category,
    tags: view.tags,
    accessMode: view.accessMode,
    releaseStage: view.releaseStage,
    rating: view.rating,
    ratingCount: view.ratingCount,
    ratingUpdatedAt: view.ratingUpdatedAt,
    screenshots: view.screenshots,
    developerName: view.developerName,
    coinCost: view.coinCost,
    requiresMembership: view.requiresMembership,
    isPublic: view.audience === 'public',
    audience: view.audience,
    isOfficial: view.isOfficial,
    publicationStatus: 'published',
    status: 'approved',
    createdAt: view.createdAt,
    updatedAt: view.updatedAt,
  }
}

export function workshopMembershipId(workshopId: string, userUid: string): string {
  const digest = createHash('sha256')
    .update(`${workshopId}\0${userUid}`)
    .digest('hex')
    .slice(0, 32)
  return `workshop_member_${digest}`
}

function normalizeCatalogApp(record: AppRecord): CatalogAppRecord | null {
  const ownerUid = record.ownerUid || record._openid
  const currentRevisionId = record.currentRevisionId
    || record.publishedSubmissionId
    || record.activeSubmissionId
  if (!ownerUid || !currentRevisionId)
    return null

  return {
    _id: record._id,
    ownerUid,
    ownerLogin: record.ownerLogin,
    audience: normalizeAudience(record.audience),
    publicationStatus: normalizePublicationStatus(record.publicationStatus),
    currentRevisionId,
    rating: record.rating,
    ratingCount: record.ratingCount,
    ratingUpdatedAt: record.ratingUpdatedAt,
    screenshots: record.screenshots,
    developerName: record.developerName,
    coinCost: record.coinCost,
    requiresMembership: record.requiresMembership,
    isOfficial: record.isOfficial,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  }
}

function normalizeAudience(value: AppAudience | undefined): AppAudience {
  return value === 'workshop' || value === 'owner' ? value : 'public'
}

function normalizePublicationStatus(
  value: AppRecord['publicationStatus'],
): CatalogPublicationStatus {
  if (value === 'published' || value === 'suspended' || value === 'delisted')
    return value
  return 'unpublished'
}

function toCatalogRevision(submission: AppSubmission): CatalogRevision {
  return {
    _id: submission._id,
    appId: submission.appId,
    revision: submission.revision,
    snapshot: {
      name: submission.snapshot.name,
      slug: submission.snapshot.slug,
      description: submission.snapshot.description,
      githubRepo: submission.snapshot.githubRepo,
      websiteUrl: submission.snapshot.websiteUrl,
      privacyPolicyUrl: submission.snapshot.privacyPolicyUrl,
      supportUrl: submission.snapshot.supportUrl,
      trustedHosts: submission.snapshot.trustedHosts,
      backupUrl: submission.snapshot.backupUrl,
      logo: submission.snapshot.logo,
      iconAssets: submission.snapshot.iconAssets,
      emoji: submission.snapshot.emoji,
      themeColor: submission.snapshot.themeColor,
      category: submission.snapshot.category,
      tags: submission.snapshot.tags,
      accessMode: submission.snapshot.accessMode,
      releaseStage: submission.snapshot.releaseStage,
    },
  }
}

async function listCollection<T>(
  db: CloudbaseAdminDb,
  collectionName: string,
): Promise<T[]> {
  const records: T[] = []
  for (let skip = 0; skip < MAX_RECORDS; skip += PAGE_SIZE) {
    const { data } = await db.collection(collectionName)
      .skip(skip)
      .limit(PAGE_SIZE)
      .get()
    const page = asArray<T>(data)
    records.push(...page)
    if (page.length < PAGE_SIZE)
      break
  }
  return records
}

function asArray<T>(value: unknown): T[] {
  if (Array.isArray(value))
    return value as T[]
  return value ? [value as T] : []
}

function first<T>(value: unknown): T | null {
  return asArray<T>(value)[0] || null
}

function isPresent<T>(value: T | null): value is T {
  return value !== null
}
