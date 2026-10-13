import type { CloudbaseAdminDb } from './cloudbase-admin'
import type { AppRecord } from '~/types/app'
import { catalogAppViewToRecord, createCloudbaseCatalogResolver } from '../domain/catalog/cloudbase'
import { useCloudbaseAdmin } from './cloudbase-admin'

const PUBLIC_QUERY = {
  isPublic: true,
  status: 'approved',
  publicationStatus: 'published',
} as const

const PAGE_SIZE = 100
const MAX_PUBLIC_APPS = 1000

export async function listPublicApps(db: CloudbaseAdminDb = useCloudbaseAdmin().db): Promise<AppRecord[]> {
  const records: AppRecord[] = []

  for (let skip = 0; skip < MAX_PUBLIC_APPS; skip += PAGE_SIZE) {
    const { data } = await db
      .collection('apps')
      .where(PUBLIC_QUERY)
      .orderBy('updatedAt', 'desc')
      .skip(skip)
      .limit(PAGE_SIZE)
      .get()
    const page = ((data as AppRecord[] | undefined) || [])
      .map(toPublicAppRecord)
      .filter((record): record is AppRecord => Boolean(record))
    records.push(...page)
    if ((data?.length || 0) < PAGE_SIZE)
      break
  }

  return records
}

export async function getPublicAppByKey(
  key: string,
  db: CloudbaseAdminDb = useCloudbaseAdmin().db,
): Promise<AppRecord | null> {
  const catalog = await createCloudbaseCatalogResolver(db).resolveCatalog({ surface: 'public_market' }, null)
  const app = catalog.apps.find(app => app._id === key || app.marketShortName === key.toLowerCase())
  return app ? catalogAppViewToRecord(app) : null
}

/**
 * 公开目录使用显式白名单投影，避免把所有者 UID、待审提交、驳回原因等控制面字段下发。
 */
export function toPublicAppRecord(record: AppRecord | null | undefined): AppRecord | null {
  if (!record
    || record.isPublic !== true
    || record.status !== 'approved'
    || record.publicationStatus !== 'published') {
    return null
  }

  return {
    _id: record._id,
    ownerLogin: record.ownerLogin,
    name: record.name,
    slug: record.slug,
    description: record.description,
    githubRepo: record.githubRepo,
    websiteUrl: record.websiteUrl,
    privacyPolicyUrl: record.privacyPolicyUrl,
    supportUrl: record.supportUrl,
    trustedHosts: record.trustedHosts,
    backupUrl: record.backupUrl,
    logo: record.logo,
    iconAssets: record.iconAssets,
    emoji: record.emoji,
    themeColor: record.themeColor,
    category: record.category,
    tags: record.tags,
    rating: record.rating,
    ratingCount: record.ratingCount,
    ratingUpdatedAt: record.ratingUpdatedAt,
    age: record.age,
    screenshots: record.screenshots,
    developerName: record.developerName,
    coinCost: record.coinCost,
    requiresMembership: record.requiresMembership,
    isPublic: true,
    accessMode: record.accessMode,
    releaseStage: record.releaseStage,
    isOfficial: record.isOfficial === true,
    publicationStatus: 'published',
    status: 'approved',
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  }
}
