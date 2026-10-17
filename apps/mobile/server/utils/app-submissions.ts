import type {
  PublicMarketListingRecord,
  PublicMarketSubmissionChange,
} from '../domain/public-market-submission'
import type { CloudbaseTransaction } from './cloudbase-admin'
import type { ServerAuthUser } from './cloudbase-auth'
import type {
  AppRecord,
  AppReviewEvent,
  AppSubmission,
  AppSubmissionAccess,
  AppSubmissionResult,
} from '~/types/app'
import { randomUUID } from 'node:crypto'
import { createError } from 'h3'
import { claimAppIdentifier } from '../domain/app-identifiers'
import {
  isDuplicateKeyError,
  normalizeAppNameKey,
} from '../domain/app-name'
import { PUBLIC_MARKET_LISTINGS_COLLECTION } from '../domain/catalog/cloudbase'
import {
  createPublicMarketSubmissionModule,
  PublicMarketSubmissionError,
} from '../domain/public-market-submission'
import {
  isYunLeFunFirstPartyHostname,
  normalizeSubmissionInput,
  publicProjectionFromSubmission,
} from './app-submission-validation'
import { applicationRevisionIds, applicationWriteVersion, readOwnedApplicationState, requireApplicationWriteVersion } from './app-write-version'
import { useCloudbaseAdmin } from './cloudbase-admin'

export const APPS_COLLECTION = 'apps'
export const APP_SUBMISSIONS_COLLECTION = 'app_submissions'
export const APP_REVIEW_EVENTS_COLLECTION = 'app_review_events'
export async function checkAppNameAvailability(name: string, _excludeAppId?: string) {
  return { available: true, nameKey: normalizeAppNameKey(name) }
}

async function rethrowDuplicateIdentity(_db: unknown, error: unknown, _name: string, _slug: string, _appId: string): Promise<never> {
  if (!isDuplicateKeyError(error))
    throw error
  throw createError({ statusCode: 409, message: '应用标识冲突，请刷新重试', data: { code: 'APP_IDENTITY_TAKEN' } })
}

export async function getAppSubmissionAccess(user: ServerAuthUser): Promise<AppSubmissionAccess> {
  const canSubmitFirstParty = !user.anonymous
    && user.phoneVerified
    && user.accountStatus === 'active'
  return {
    canSubmitFirstParty,
    writePreconditionVersion: 1,
    thirdPartyEnabled: thirdPartySubmissionsEnabled(),
    thirdPartyMessage: '第三方应用入驻敬请期待',
  }
}

export async function requireFirstPartySubmitter(user: ServerAuthUser): Promise<void> {
  const access = await getAppSubmissionAccess(user)
  if (!access.canSubmitFirstParty) {
    throw createError({
      statusCode: 403,
      statusMessage: access.thirdPartyMessage,
      data: { code: 'FIRST_PARTY_SUBMITTER_REQUIRED' },
    })
  }
}

export async function createAppSubmission(
  user: ServerAuthUser,
  input: unknown,
): Promise<AppSubmissionResult> {
  const { db } = useCloudbaseAdmin()
  const normalized = normalizeSubmissionInput(input, {
    thirdPartyEnabled: thirdPartySubmissionsEnabled(),
  })
  await enforceSubmissionRateLimit(db, user.uid)
  const nameKey = normalizeAppNameKey(normalized.snapshot.name)

  const { data: duplicates } = await db.collection(APPS_COLLECTION)
    .where({ ownerUid: user.uid, slug: normalized.snapshot.slug })
    .limit(1)
    .get()
  if (duplicates?.length)
    throw createError({ statusCode: 409, statusMessage: '你的命名空间内已存在此 slug' })

  const now = Date.now()
  const appId = entityId('app')
  const submissionId = entityId('submission')
  const eventId = entityId('review_event')
  const hostname = new URL(normalized.snapshot.websiteUrl || '').hostname
  const submission: AppSubmission = {
    _id: submissionId,
    appId,
    revision: 1,
    kind: normalized.kind,
    submitterUid: user.uid,
    ...(user.handle ? { submitterLogin: user.handle } : {}),
    reviewStatus: 'draft',
    snapshot: normalized.snapshot,
    ownership: {
      status: 'pending',
      hostname,
      checks: [{
        key: 'hostname',
        status: normalized.kind === 'first_party' && isYunLeFunFirstPartyHostname(hostname) ? 'pass' : 'warning',
        summary: normalized.kind === 'first_party' ? '域名属于 yunle.fun 第一方候选范围' : '等待第三方归属验证',
      }],
    },
    submittedAt: now,
    createdAt: now,
    updatedAt: now,
  }
  const projection = publicProjectionFromSubmission(normalized.snapshot)
  const developerName = user.name?.trim()
  const app: AppRecord = {
    _id: appId,
    identityVersion: 2,
    ownerUid: user.uid,
    ownerLogin: user.handle || user.uid,
    ownerLoginKey: (user.handle || user.uid).toLowerCase(),
    ...(developerName ? { developerName } : {}),
    ...projection,
    nameKey,
    isPublic: normalized.snapshot.audience === 'public',
    audience: normalized.snapshot.audience || 'public',
    isOfficial: false,
    publicationStatus: 'published',
    currentRevisionId: submissionId,
    publishedSubmissionId: submissionId,
    activeSubmissionId: '',
    status: 'approved',
    createdAt: now,
    updatedAt: now,
  }
  const event = submissionEvent(eventId, appId, submissionId, user, 'submission.created', now)

  try {
    await db.runTransaction(async (transaction: CloudbaseTransaction) => {
      await claimAppIdentifier(transaction, 'namespace', normalized.snapshot.slug, appId, user.uid)
      await transaction.collection(APPS_COLLECTION).doc(appId).set(documentPayload(app))
      await transaction.collection(APP_SUBMISSIONS_COLLECTION).doc(submissionId).set(documentPayload(submission))
      await transaction.collection(APP_REVIEW_EVENTS_COLLECTION).doc(eventId).set(documentPayload(event))
    })
  }
  catch (error) {
    await rethrowDuplicateIdentity(db, error, normalized.snapshot.name, normalized.snapshot.slug, appId)
  }

  return { app: await savedApplication(db, appId, user.uid, submissionId), submission }
}

export async function updateAppSubmission(
  user: ServerAuthUser,
  appId: string,
  input: unknown,
  ifMatch: string | undefined,
): Promise<AppSubmissionResult> {
  const { db } = useCloudbaseAdmin()
  const base = await readOwnedApplicationState(db, appId, user.uid)
  requireApplicationWriteVersion(ifMatch, base.writeVersion)
  const { app } = base
  const normalized = normalizeSubmissionInput(input, {
    thirdPartyEnabled: thirdPartySubmissionsEnabled(),
  })
  await enforceSubmissionRateLimit(db, user.uid)
  const nameKey = normalizeAppNameKey(normalized.snapshot.name)
  if (app.currentRevisionId && normalized.snapshot.slug !== app.slug) {
    throw createError({
      statusCode: 409,
      statusMessage: '已上架应用不能修改 slug',
    })
  }
  if (normalized.snapshot.slug !== app.slug) {
    const { data: duplicates } = await db.collection(APPS_COLLECTION)
      .where({ ownerUid: user.uid, slug: normalized.snapshot.slug })
      .limit(1)
      .get()
    if (duplicates?.some((item: AppRecord) => item._id !== appId))
      throw createError({ statusCode: 409, statusMessage: '你的命名空间内已存在此 slug' })
  }

  const { data: previous } = await db.collection(APP_SUBMISSIONS_COLLECTION)
    .where({ appId })
    .orderBy('revision', 'desc')
    .limit(1)
    .get()
  const revision = Number((previous?.[0] as AppSubmission | undefined)?.revision || 0) + 1
  const now = Date.now()
  const submissionId = entityId('submission')
  const eventId = entityId('review_event')
  const hostname = new URL(normalized.snapshot.websiteUrl || '').hostname
  const submission: AppSubmission = {
    _id: submissionId,
    appId,
    revision,
    kind: normalized.kind,
    submitterUid: user.uid,
    ...(user.handle ? { submitterLogin: user.handle } : {}),
    reviewStatus: 'draft',
    snapshot: normalized.snapshot,
    ownership: {
      status: 'pending',
      hostname,
      checks: [{
        key: 'hostname',
        status: normalized.kind === 'first_party' && isYunLeFunFirstPartyHostname(hostname) ? 'pass' : 'warning',
        summary: normalized.kind === 'first_party' ? '域名属于 yunle.fun 第一方候选范围' : '等待第三方归属验证',
      }],
    },
    submittedAt: now,
    createdAt: now,
    updatedAt: now,
  }
  const event = submissionEvent(eventId, appId, submissionId, user, 'submission.updated', now)
  const developerName = user.name?.trim()
  const appPatch: Record<string, unknown> = {
    ...publicProjectionFromSubmission(normalized.snapshot),
    ...(developerName ? { developerName } : {}),
    nameKey,
    audience: normalized.snapshot.audience || 'public',
    isPublic: normalized.snapshot.audience === 'public',
    publicationStatus: 'published',
    currentRevisionId: submissionId,
    publishedSubmissionId: submissionId,
    activeSubmissionId: '',
    status: 'approved',
    rejectedReason: '',
    updatedAt: now,
  }

  try {
    await db.runTransaction(async (transaction: CloudbaseTransaction) => {
      const current = await readOwnedApplicationState(transaction, appId, user.uid)
      requireApplicationWriteVersion(ifMatch, current.writeVersion)
      await claimAppIdentifier(transaction, 'namespace', normalized.snapshot.slug, appId, user.uid)
      await transaction.collection(APP_SUBMISSIONS_COLLECTION).doc(submissionId).set(documentPayload(submission))
      await transaction.collection(APPS_COLLECTION).doc(appId).update(appPatch)
      await transaction.collection(APP_REVIEW_EVENTS_COLLECTION).doc(eventId).set(documentPayload(event))
      if (normalized.snapshot.audience !== 'public')
        await invalidatePublicMarketListing(transaction, current, now, 'audience_changed')
    })
  }
  catch (error) {
    await rethrowDuplicateIdentity(db, error, normalized.snapshot.name, normalized.snapshot.slug, appId)
  }
  return { app: await savedApplication(db, appId, user.uid, submissionId), submission }
}

export async function submitOwnedAppToPublicMarket(
  user: ServerAuthUser,
  appId: string,
  options: { makePublic?: boolean, shortName?: string, ifMatch?: string } = {},
): Promise<{ appId: string, submissionId: string, reviewStatus: 'pending' }> {
  const { db } = useCloudbaseAdmin()
  const base = await readOwnedApplicationState(db, appId, user.uid)
  requireApplicationWriteVersion(options.ifMatch, base.writeVersion)
  const workflow = createPublicMarketSubmissionModule({
    async getOwnedApp() {
      return base.app
    },
    async getSubmission(id) {
      return base.submissions.get(id) ?? null
    },
    async getListing() {
      return base.listing
        ? { ...base.listing, appId, approvedRevisionId: base.listing.approvedRevisionId || '', activeSubmissionId: base.listing.activeSubmissionId || '' }
        : null
    },
    async getLatestRevisionNumber(id) {
      const { data } = await db.collection(APP_SUBMISSIONS_COLLECTION)
        .where({ appId: id })
        .orderBy('revision', 'desc')
        .limit(1)
        .get()
      return Number((data?.[0] as AppSubmission | undefined)?.revision || 0)
    },
    async commit(change) {
      await commitPublicMarketSubmission(db, change, user.uid, options.ifMatch)
    },
  })
  try {
    return await workflow.submit(
      appId,
      { uid: user.uid, ...(user.handle ? { login: user.handle } : {}) },
      options,
    )
  }
  catch (error: unknown) {
    if (error instanceof PublicMarketSubmissionError) {
      throw createError({
        statusCode: error.code === 'APP_NOT_FOUND' ? 404 : 409,
        message: error.message,
        data: { code: error.code },
      })
    }
    throw error
  }
}

export async function listOwnedApps(user: ServerAuthUser): Promise<AppRecord[]> {
  const { db } = useCloudbaseAdmin()
  const [ownerResult, legacyResult] = await Promise.all([
    db.collection(APPS_COLLECTION).where({ ownerUid: user.uid }).limit(100).get(),
    db.collection(APPS_COLLECTION).where({ _openid: user.uid }).limit(100).get(),
  ])
  const map = new Map<string, AppRecord>()
  for (const row of [...(ownerResult.data || []), ...(legacyResult.data || [])] as AppRecord[]) {
    if (row.ownerUid ? row.ownerUid === user.uid : row._openid === user.uid)
      map.set(row._id, row)
  }
  const apps = [...map.values()].sort((a, b) => b.updatedAt - a.updatedAt)
  return attachLatestSubmissions(db, apps)
}

export async function getOwnedAppBySlug(user: ServerAuthUser, slug: string): Promise<AppRecord | null> {
  const apps = await listOwnedApps(user)
  return apps.find(app => app.slug === slug) ?? null
}

export async function getOwnedAppById(user: ServerAuthUser, appId: string): Promise<AppRecord | null> {
  const apps = await listOwnedApps(user)
  return apps.find(app => app._id === appId) ?? null
}

export async function isAppSlugTaken(slug: string, ownerUid: string): Promise<boolean> {
  if (!/^[a-z][a-z0-9-]{1,49}$/.test(slug))
    return false
  const { db } = useCloudbaseAdmin()
  const { data } = await db.collection(APPS_COLLECTION).where({ ownerUid, slug }).limit(1).get()
  return Boolean(data?.length)
}

export async function delistOwnedApp(user: ServerAuthUser, appId: string, ifMatch: string | undefined): Promise<void> {
  const { db } = useCloudbaseAdmin()
  const app = await ownedApp(db, appId, user.uid)
  const now = Date.now()
  const eventId = entityId('review_event')
  const event = submissionEvent(
    eventId,
    appId,
    app.activeSubmissionId,
    user,
    'publication.delisted',
    now,
    '应用所有者主动下架',
  )

  await db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const current = await readOwnedApplicationState(transaction, appId, user.uid)
    requireApplicationWriteVersion(ifMatch, current.writeVersion)
    await invalidatePublicMarketListing(transaction, current, now, 'owner_delisted')
    await transaction.collection(APPS_COLLECTION).doc(appId).update({
      isPublic: false,
      publicationStatus: 'delisted',
      activeSubmissionId: '',
      updatedAt: now,
    })
    await transaction.collection(APP_REVIEW_EVENTS_COLLECTION).doc(eventId).set(documentPayload(event))
  })
}

async function savedApplication(db: ReturnType<typeof useCloudbaseAdmin>['db'], appId: string, uid: string, revisionId: string): Promise<AppRecord> {
  const state = await readOwnedApplicationState(db, appId, uid)
  const latestSubmission = state.submissions.get(revisionId)
  if (!latestSubmission)
    throw createError({ statusCode: 409, message: '作品已再次变化，请刷新后核对保存结果' })
  return {
    ...state.app,
    writeVersion: state.writeVersion,
    ownerMetadataRevisionId: state.app.currentRevisionId || state.app.publishedSubmissionId,
    latestSubmission,
    ...(state.listing ? { yunlefunListing: { ...state.listing, appId } } : {}),
  }
}

async function attachLatestSubmissions(db: any, apps: AppRecord[]): Promise<AppRecord[]> {
  if (!apps.length)
    return apps
  const listingResult = await db.collection(PUBLIC_MARKET_LISTINGS_COLLECTION)
    .where({ _id: db.command.in(apps.map(app => app._id)) })
    .limit(apps.length)
    .get()
  const listings = new Map<string, PublicMarketListingRecord>(
    ((listingResult.data || []) as (PublicMarketListingRecord & { _id?: string })[])
      .map(item => [item.appId || item._id || '', item]),
  )
  const submissionIds = [...new Set(apps.flatMap(app => applicationRevisionIds(app, listings.get(app._id))))]
  if (!submissionIds.length) {
    return apps.map(app => ({
      ...app,
      writeVersion: applicationWriteVersion(app, listings.get(app._id) ?? null, new Map()),
      ...(listings.get(app._id) ? { yunlefunListing: { ...listings.get(app._id)!, appId: app._id } } : {}),
    }))
  }
  const { data } = await db.collection(APP_SUBMISSIONS_COLLECTION)
    .where({ _id: db.command.in(submissionIds) })
    .limit(submissionIds.length)
    .get()
  const submissions = new Map<string, AppSubmission>(
    ((data || []) as AppSubmission[]).map(item => [item._id, item]),
  )
  return apps.map((app) => {
    const listing = listings.get(app._id)
    const latestId = listing?.activeSubmissionId
      || app.activeSubmissionId
      || app.currentRevisionId
      || app.publishedSubmissionId
    const latest = latestId ? submissions.get(latestId) : undefined
    if (!latest) {
      return {
        ...app,
        writeVersion: applicationWriteVersion(app, listing ?? null, submissions),
        ...(listing ? { yunlefunListing: { ...listing, appId: app._id } } : {}),
      }
    }
    const currentId = app.currentRevisionId || app.publishedSubmissionId
    const reviewsCurrent = !currentId || latest._id === currentId
    const visibleSnapshot = reviewsCurrent ? latest.snapshot : undefined
    return {
      ...app,
      ...visibleSnapshot,
      writeVersion: applicationWriteVersion(app, listing ?? null, submissions),
      ownerMetadataRevisionId: currentId || latest._id,
      isPublic: app.publicationStatus === 'published' && (app.audience || visibleSnapshot?.audience || 'public') === 'public',
      status: reviewsCurrent ? reviewStatusToLegacy(latest.reviewStatus, app.status) : app.status,
      rejectedReason: reviewsCurrent && (latest.reviewStatus === 'rejected' || latest.reviewStatus === 'changes_requested')
        ? latest.reviewNote || ''
        : app.rejectedReason,
      latestSubmission: latest,
      ...(listing ? { yunlefunListing: { ...listing, appId: app._id } } : {}),
    }
  })
}

async function commitPublicMarketSubmission(
  db: ReturnType<typeof useCloudbaseAdmin>['db'],
  change: PublicMarketSubmissionChange,
  ownerUid: string,
  ifMatch: string | undefined,
): Promise<void> {
  await db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const state = await readOwnedApplicationState(transaction, change.appId, ownerUid)
    requireApplicationWriteVersion(ifMatch, state.writeVersion)
    const current = state.listing
    if (current?.shortName && current.shortName !== change.listing.shortName)
      throw createError({ statusCode: 409, message: '市场短名已确定，请刷新后重试' })
    await claimAppIdentifier(transaction, 'market', change.listing.shortName!, change.appId)
    const submissionRef = transaction.collection(APP_SUBMISSIONS_COLLECTION)
      .doc(change.submission._id)
    if (change.submissionMode === 'create') {
      await submissionRef.set(documentPayload(change.submission))
    }
    else {
      await submissionRef.update({
        reviewStatus: change.submission.reviewStatus,
        submittedAt: change.submission.submittedAt,
        updatedAt: change.submission.updatedAt,
        reviewedAt: change.submission.reviewedAt || 0,
        reviewedBy: change.submission.reviewedBy || '',
        reviewNote: change.submission.reviewNote || '',
      })
    }
    await transaction.collection(PUBLIC_MARKET_LISTINGS_COLLECTION)
      .doc(change.appId)
      .set(change.listing)
    await transaction.collection(APPS_COLLECTION).doc(change.appId).update(change.appPatch)
    await transaction.collection(APP_REVIEW_EVENTS_COLLECTION)
      .doc(change.event._id)
      .set(documentPayload(change.event))
  })
}

async function invalidatePublicMarketListing(
  transaction: CloudbaseTransaction,
  state: Awaited<ReturnType<typeof readOwnedApplicationState>>,
  updatedAt: number,
  reason: 'audience_changed' | 'owner_delisted',
): Promise<void> {
  for (const id of new Set([state.app.activeSubmissionId, state.listing?.activeSubmissionId].filter((id): id is string => Boolean(id)))) {
    const submission = state.submissions.get(id)
    if (submission?.appId === state.app._id && ['pending', 'in_review'].includes(submission.reviewStatus)) {
      await transaction.collection(APP_SUBMISSIONS_COLLECTION).doc(id).update({ reviewStatus: 'withdrawn', updatedAt })
    }
  }
  if (state.listing) {
    await transaction.collection(PUBLIC_MARKET_LISTINGS_COLLECTION).doc(state.app._id).update({
      status: 'delisted',
      activeSubmissionId: '',
      delistedReason: reason,
      updatedAt,
    })
  }
}

async function ownedApp(db: any, appId: string, uid: string): Promise<AppRecord> {
  const { data } = await db.collection(APPS_COLLECTION).doc(appId).get()
  const app = (Array.isArray(data) ? data[0] : data) as AppRecord | undefined
  if (!app)
    throw createError({ statusCode: 404, statusMessage: '应用不存在' })
  if (app.ownerUid ? app.ownerUid !== uid : app._openid !== uid)
    throw createError({ statusCode: 403, statusMessage: '无权管理此应用' })
  return app
}

async function enforceSubmissionRateLimit(db: any, uid: string): Promise<void> {
  const now = Date.now()
  const collection = db.collection(APP_SUBMISSIONS_COLLECTION)
  const { data } = await collection
    .where({ submitterUid: uid })
    .orderBy('submittedAt', 'desc')
    .limit(1)
    .get()
  const latest = (data?.[0] || {}) as Partial<AppSubmission>
  if (latest.submittedAt && now - latest.submittedAt < 60_000) {
    throw createError({
      statusCode: 429,
      statusMessage: '提交过于频繁，请一分钟后再试',
      data: { code: 'APP_SUBMISSION_RATE_LIMITED' },
    })
  }

  const since = now - 24 * 60 * 60 * 1000
  const { total } = await collection
    .where({
      submitterUid: uid,
      submittedAt: db.command.gte(since),
    })
    .count()
  if ((total || 0) >= 20) {
    throw createError({
      statusCode: 429,
      statusMessage: '今日提交次数已达上限，请明天再试',
      data: { code: 'APP_SUBMISSION_DAILY_LIMITED' },
    })
  }
}

function thirdPartySubmissionsEnabled(): boolean {
  const config = useRuntimeConfig() as Record<string, unknown>
  return config.appThirdPartySubmissionsEnabled === true
}

function submissionEvent(
  id: string,
  appId: string,
  submissionId: string | undefined,
  user: ServerAuthUser,
  action: AppReviewEvent['action'],
  createdAt: number,
  reason?: string,
): AppReviewEvent {
  return {
    _id: id,
    appId,
    ...(submissionId ? { submissionId } : {}),
    action,
    actorType: 'submitter',
    actorId: user.uid,
    ...(user.handle ? { actorLogin: user.handle } : {}),
    ...(reason ? { note: reason } : {}),
    createdAt,
  }
}

function reviewStatusToLegacy(
  status: AppSubmission['reviewStatus'],
  fallback: AppRecord['status'],
): AppRecord['status'] {
  if (status === 'approved')
    return 'approved'
  if (status === 'rejected' || status === 'changes_requested')
    return 'rejected'
  if (status === 'withdrawn')
    return fallback
  return 'pending'
}

function entityId(prefix: string): string {
  return `${prefix}_${randomUUID().replace(/-/g, '')}`
}

function documentPayload<T extends { _id: string }>(document: T): Omit<T, '_id'> {
  const { _id: _documentId, ...payload } = document
  return payload
}
