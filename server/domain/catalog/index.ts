/** Central catalog authorization Module. */
export type CatalogSurface = 'public_market' | 'personal_market' | 'workshop'
export type CatalogAudience = 'public' | 'workshop' | 'owner'
export type CatalogPublicationStatus = 'unpublished' | 'published' | 'suspended' | 'delisted'
export type WorkshopJoinPolicy = 'approval' | 'open' | 'closed'
export type WorkshopStatus = 'active' | 'disabled'
export type WorkshopMembershipStatus = 'pending' | 'active' | 'rejected' | 'left' | 'removed' | 'blocked'
export type WorkshopAccess = 'anonymous' | 'none' | 'pending' | 'active' | 'owner' | 'blocked'

export interface CatalogPrincipal {
  uid: string
  name?: string
  avatar?: string
}

export interface CatalogAppRecord {
  _id: string
  ownerUid: string
  ownerLogin?: string
  audience: CatalogAudience
  publicationStatus: CatalogPublicationStatus
  currentRevisionId: string
  rating?: number
  ratingCount?: number
  ratingUpdatedAt?: number
  screenshots?: string[]
  developerName?: string
  coinCost?: number
  requiresMembership?: boolean
  isOfficial?: boolean
  createdAt: number
  updatedAt: number
}

export interface CatalogRevisionSnapshot {
  name: string
  slug: string
  description?: string
  websiteUrl?: string
  privacyPolicyUrl?: string
  supportUrl?: string
  trustedHosts?: string[]
  backupUrl?: string
  logo?: string
  emoji?: string
  themeColor?: string
  category?: string
  tags?: string[]
}

export interface CatalogRevision {
  _id: string
  appId: string
  revision: number
  snapshot: CatalogRevisionSnapshot
}

export interface PublicMarketListing {
  appId: string
  status: 'unlisted' | 'listed' | 'suspended' | 'delisted'
  approvedRevisionId?: string
}

export interface PersonalWorkshop {
  _id: string
  ownerUid: string
  ownerName: string
  ownerAvatar?: string
  name: string
  description?: string
  joinPolicy: WorkshopJoinPolicy
  status: WorkshopStatus
  createdAt: number
  updatedAt: number
}

export interface WorkshopMembership {
  workshopId: string
  userUid: string
  userName?: string
  userAvatar?: string
  status: WorkshopMembershipStatus
  requestedAt?: number
  joinedAt?: number
  updatedAt: number
}

export interface CatalogDataSource {
  listApps: () => Promise<CatalogAppRecord[]>
  listPublicMarketListings: () => Promise<PublicMarketListing[]>
  getRevisions: (ids: readonly string[]) => Promise<CatalogRevision[]>
  getWorkshop: (id: string) => Promise<PersonalWorkshop | null>
  getMembership: (workshopId: string, userUid: string) => Promise<WorkshopMembership | null>
}

export interface CatalogAppView extends CatalogRevisionSnapshot {
  _id: string
  ownerUid: string
  revisionId: string
  audience: CatalogAudience
  publicationStatus: 'published'
  ownerLogin?: string
  rating?: number
  ratingCount?: number
  ratingUpdatedAt?: number
  screenshots?: string[]
  developerName?: string
  coinCost?: number
  requiresMembership?: boolean
  isOfficial?: boolean
  createdAt: number
  updatedAt: number
}

export interface MarketCatalogView {
  surface: 'public_market' | 'personal_market'
  apps: CatalogAppView[]
}

export interface WorkshopPublicView {
  _id: string
  ownerName: string
  ownerAvatar?: string
  name: string
  description?: string
  joinPolicy: WorkshopJoinPolicy
  status: WorkshopStatus
}

export interface WorkshopCatalogView {
  surface: 'workshop'
  access: WorkshopAccess
  workshop: WorkshopPublicView
  apps: CatalogAppView[]
}

export type CatalogView = MarketCatalogView | WorkshopCatalogView

export interface CatalogResolver {
  resolveCatalog: (
    request:
      | { surface: 'public_market' }
      | { surface: 'personal_market', ownerUid: string }
      | { surface: 'workshop', workshopId: string },
    principal: CatalogPrincipal | null,
  ) => Promise<CatalogView>
}

export function createCatalogResolver(source: CatalogDataSource): CatalogResolver {
  return {
    async resolveCatalog(request, principal) {
      if (request.surface === 'personal_market')
        return resolvePersonalMarket(source, request.ownerUid)
      if (request.surface === 'workshop')
        return resolveWorkshop(source, request.workshopId, principal)

      const [apps, listings] = await Promise.all([
        source.listApps(),
        source.listPublicMarketListings(),
      ])
      const appById = new Map(apps.map(app => [app._id, app]))
      const visibleListings = listings.filter((listing) => {
        const app = appById.get(listing.appId)
        return listing.status === 'listed'
          && Boolean(listing.approvedRevisionId)
          && app?.audience === 'public'
          && app.publicationStatus === 'published'
      })
      const revisionIds = visibleListings
        .map(listing => listing.approvedRevisionId)
        .filter((id): id is string => Boolean(id))
      const revisions = await source.getRevisions(revisionIds)
      const revisionById = new Map(revisions.map(revision => [revision._id, revision]))

      return {
        surface: 'public_market',
        apps: visibleListings.flatMap((listing) => {
          const app = appById.get(listing.appId)
          const revision = listing.approvedRevisionId
            ? revisionById.get(listing.approvedRevisionId)
            : undefined
          if (!app || !revision || revision.appId !== app._id)
            return []
          return [toAppView(app, revision)]
        }),
      }
    },
  }
}

async function resolveWorkshop(
  source: CatalogDataSource,
  workshopId: string,
  principal: CatalogPrincipal | null,
): Promise<WorkshopCatalogView> {
  const workshop = await source.getWorkshop(workshopId)
  if (!workshop)
    throw new CatalogNotFoundError('个人工坊不存在')

  const membership = principal && principal.uid !== workshop.ownerUid
    ? await source.getMembership(workshopId, principal.uid)
    : null
  const access = workshopAccess(workshop, membership, principal)
  const canViewApps = workshop.status === 'active'
    && (access === 'owner' || access === 'active')
  const apps = canViewApps
    ? await resolveCurrentApps(source, app =>
        app.ownerUid === workshop.ownerUid
        && app.publicationStatus === 'published'
        && (app.audience === 'public' || app.audience === 'workshop'))
    : []

  return {
    surface: 'workshop',
    access,
    workshop: {
      _id: workshop._id,
      ownerName: workshop.ownerName,
      ownerAvatar: workshop.ownerAvatar,
      name: workshop.name,
      description: workshop.description,
      joinPolicy: workshop.joinPolicy,
      status: workshop.status,
    },
    apps,
  }
}

async function resolvePersonalMarket(
  source: CatalogDataSource,
  ownerUid: string,
): Promise<CatalogView> {
  const apps = await resolveCurrentApps(source, app =>
    app.ownerUid === ownerUid
    && app.audience === 'public'
    && app.publicationStatus === 'published')

  return {
    surface: 'personal_market',
    apps,
  }
}

async function resolveCurrentApps(
  source: CatalogDataSource,
  predicate: (app: CatalogAppRecord) => boolean,
): Promise<CatalogAppView[]> {
  const apps = (await source.listApps())
    .filter(predicate)
    .sort((left, right) => right.updatedAt - left.updatedAt)
  const revisions = await source.getRevisions(apps.map(app => app.currentRevisionId))
  const revisionById = new Map(revisions.map(revision => [revision._id, revision]))
  return apps.flatMap((app) => {
    const revision = revisionById.get(app.currentRevisionId)
    return revision?.appId === app._id ? [toAppView(app, revision)] : []
  })
}

function workshopAccess(
  workshop: PersonalWorkshop,
  membership: WorkshopMembership | null,
  principal: CatalogPrincipal | null,
): WorkshopAccess {
  if (!principal)
    return 'anonymous'
  if (principal.uid === workshop.ownerUid)
    return 'owner'
  if (membership?.status === 'active')
    return 'active'
  if (membership?.status === 'pending')
    return 'pending'
  if (membership?.status === 'blocked')
    return 'blocked'
  return 'none'
}

function toAppView(app: CatalogAppRecord, revision: CatalogRevision): CatalogAppView {
  return {
    _id: app._id,
    ownerUid: app.ownerUid,
    revisionId: revision._id,
    audience: app.audience,
    publicationStatus: 'published',
    ownerLogin: app.ownerLogin,
    rating: app.rating,
    ratingCount: app.ratingCount,
    ratingUpdatedAt: app.ratingUpdatedAt,
    screenshots: app.screenshots,
    developerName: app.developerName,
    coinCost: app.coinCost,
    requiresMembership: app.requiresMembership,
    isOfficial: app.isOfficial,
    createdAt: app.createdAt,
    updatedAt: app.updatedAt,
    ...revision.snapshot,
  }
}

export class CatalogNotFoundError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'CatalogNotFoundError'
  }
}
