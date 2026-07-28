import type { AppRecord } from '../../app/types/app'
import { describe, expect, it, vi } from 'vitest'
import {
  getPublicAppByKey,
  listPublicApps,
  toPublicAppRecord,
} from '../../server/utils/public-apps'

function makeApp(overrides: Partial<AppRecord> = {}): AppRecord {
  return {
    _id: 'app_1',
    _openid: 'private-openid',
    ownerLogin: 'YunYouJun',
    ownerUid: 'private-uid',
    name: '问 TA',
    slug: 'wenta',
    websiteUrl: 'https://wenta.yunle.fun/',
    privacyPolicyUrl: 'https://wenta.yunle.fun/privacy',
    supportUrl: 'https://support.yunle.fun/',
    isPublic: true,
    isOfficial: true,
    status: 'approved',
    publicationStatus: 'published',
    publishedSubmissionId: 'submission_1',
    activeSubmissionId: 'submission_pending',
    rejectedReason: 'private-reason',
    createdAt: 1,
    updatedAt: 2,
    ...overrides,
  }
}

function mockDb(records: AppRecord[]) {
  const get = vi.fn(async () => ({ data: records }))
  const limit = vi.fn(() => ({ get }))
  const skip = vi.fn(() => ({ limit }))
  const orderBy = vi.fn(() => ({ skip }))
  const where = vi.fn(() => ({ orderBy, limit }))
  const collection = vi.fn(() => ({ where }))
  return {
    db: { collection } as any,
    collection,
    where,
  }
}

describe('public app read model', () => {
  it('returns only published apps and strips control-plane fields', () => {
    const publicApp = toPublicAppRecord(makeApp())

    expect(publicApp).toMatchObject({
      slug: 'wenta',
      status: 'approved',
      publicationStatus: 'published',
      isOfficial: true,
    })
    expect(publicApp).not.toHaveProperty('_openid')
    expect(publicApp).not.toHaveProperty('ownerUid')
    expect(publicApp).not.toHaveProperty('publishedSubmissionId')
    expect(publicApp).not.toHaveProperty('activeSubmissionId')
    expect(publicApp).not.toHaveProperty('rejectedReason')
  })

  it('rejects pending, unpublished, or private records defensively', () => {
    expect(toPublicAppRecord(makeApp({ status: 'pending' }))).toBeNull()
    expect(toPublicAppRecord(makeApp({ publicationStatus: 'unpublished' }))).toBeNull()
    expect(toPublicAppRecord(makeApp({ isPublic: false }))).toBeNull()
  })

  it('lists public apps through the server database adapter', async () => {
    const { db, where } = mockDb([makeApp()])

    await expect(listPublicApps(db)).resolves.toMatchObject([{ slug: 'wenta' }])
    expect(where).toHaveBeenCalledWith({
      isPublic: true,
      status: 'approved',
      publicationStatus: 'published',
    })
  })

  it('resolves a public app by id or slug', async () => {
    const { db } = mockDb([makeApp()])

    await expect(getPublicAppByKey('wenta', db)).resolves.toMatchObject({ slug: 'wenta' })
  })
})
