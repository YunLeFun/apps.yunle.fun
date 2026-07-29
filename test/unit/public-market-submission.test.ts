import type { AppRecord, AppSubmission } from '../../app/types/app'
import type {
  PublicMarketListingRecord,
  PublicMarketSubmissionChange,
  PublicMarketSubmissionError,
  PublicMarketSubmissionSource,
} from '../../server/domain/public-market-submission'
import { describe, expect, it } from 'vitest'
import {
  createPublicMarketSubmissionModule,
} from '../../server/domain/public-market-submission'

function appRecord(overrides: Partial<AppRecord> = {}): AppRecord {
  return {
    _id: 'app-1',
    ownerLogin: 'YunYouJun',
    ownerUid: 'owner-1',
    name: '示例应用',
    slug: 'example',
    websiteUrl: 'https://example.yunle.fun/',
    privacyPolicyUrl: 'https://example.yunle.fun/privacy',
    supportUrl: 'https://example.yunle.fun/support',
    isPublic: true,
    audience: 'public',
    status: 'approved',
    publicationStatus: 'published',
    currentRevisionId: 'revision-2',
    publishedSubmissionId: 'revision-2',
    activeSubmissionId: '',
    createdAt: 1,
    updatedAt: 2,
    ...overrides,
  }
}

function submission(overrides: Partial<AppSubmission> = {}): AppSubmission {
  return {
    _id: 'revision-2',
    appId: 'app-1',
    revision: 2,
    kind: 'first_party',
    submitterUid: 'owner-1',
    submitterLogin: 'YunYouJun',
    reviewStatus: 'approved',
    snapshot: {
      name: '示例应用',
      slug: 'example',
      websiteUrl: 'https://example.yunle.fun/',
      privacyPolicyUrl: 'https://example.yunle.fun/privacy',
      supportUrl: 'https://example.yunle.fun/support',
      isPublic: true,
      audience: 'public',
    },
    ownership: {
      status: 'verified',
      checks: [],
    },
    submittedAt: 2,
    createdAt: 1,
    updatedAt: 2,
    ...overrides,
  }
}

function sourceFixture(options: {
  app?: AppRecord
  submission?: AppSubmission
  listing?: PublicMarketListingRecord | null
} = {}) {
  const changes: PublicMarketSubmissionChange[] = []
  const app = options.app || appRecord()
  const currentSubmission = options.submission || submission()
  const source: PublicMarketSubmissionSource = {
    async getOwnedApp() {
      return app
    },
    async getSubmission() {
      return currentSubmission
    },
    async getListing() {
      return options.listing || null
    },
    async getLatestRevisionNumber() {
      return currentSubmission.revision
    },
    async commit(change) {
      changes.push(change)
    },
  }
  return { source, changes }
}

describe('public market submission', () => {
  it('does not submit a revision that is already listed in YunLeFun', async () => {
    const { source, changes } = sourceFixture({
      listing: {
        appId: 'app-1',
        status: 'listed',
        approvedRevisionId: 'revision-2',
        activeSubmissionId: '',
        createdAt: 1,
        updatedAt: 2,
      },
    })
    const workflow = createPublicMarketSubmissionModule(source)

    await expect(workflow.submit('app-1', { uid: 'owner-1' }))
      .rejects
      .toMatchObject<Partial<PublicMarketSubmissionError>>({
        code: 'YUNLEFUN_REVISION_ALREADY_LISTED',
      })
    expect(changes).toHaveLength(0)
  })

  it.each(['suspended', 'delisted'] as const)(
    'does not let an owner bypass the administrator-managed %s state',
    async (status) => {
      const { source, changes } = sourceFixture({
        listing: {
          appId: 'app-1',
          status,
          approvedRevisionId: 'revision-2',
          activeSubmissionId: '',
          createdAt: 1,
          updatedAt: 2,
        },
      })
      const workflow = createPublicMarketSubmissionModule(source)

      await expect(workflow.submit('app-1', { uid: 'owner-1' }))
        .rejects
        .toMatchObject<Partial<PublicMarketSubmissionError>>({
          code: 'YUNLEFUN_REVISION_PUBLICATION_MANAGED',
        })
      expect(changes).toHaveLength(0)
    },
  )

  it('keeps an approved revision awaiting publication instead of returning it to pending', async () => {
    const { source, changes } = sourceFixture({
      listing: {
        appId: 'app-1',
        status: 'unlisted',
        approvedRevisionId: '',
        activeSubmissionId: 'revision-2',
        createdAt: 1,
        updatedAt: 2,
      },
    })
    const workflow = createPublicMarketSubmissionModule(source)

    await expect(workflow.submit('app-1', { uid: 'owner-1' }))
      .rejects
      .toMatchObject<Partial<PublicMarketSubmissionError>>({
        code: 'YUNLEFUN_REVISION_AWAITING_PUBLICATION',
      })
    expect(changes).toHaveLength(0)
  })

  it('resubmits a rejected public revision as the active YunLeFun submission', async () => {
    const { source, changes } = sourceFixture({
      app: appRecord({ status: 'rejected', activeSubmissionId: '' }),
      submission: submission({
        reviewStatus: 'rejected',
        reviewNote: '请补充支持入口',
      }),
      listing: {
        appId: 'app-1',
        status: 'unlisted',
        approvedRevisionId: '',
        activeSubmissionId: '',
        createdAt: 1,
        updatedAt: 2,
      },
    })
    const workflow = createPublicMarketSubmissionModule(source, {
      now: () => 1_750_000_000_000,
      eventId: () => 'event-1',
      submissionId: () => 'unused',
    })

    await expect(workflow.submit('app-1', { uid: 'owner-1', login: 'YunYouJun' }))
      .resolves
      .toEqual({
        appId: 'app-1',
        submissionId: 'revision-2',
        reviewStatus: 'pending',
      })
    expect(changes).toHaveLength(1)
    expect(changes[0]).toMatchObject({
      appId: 'app-1',
      appPatch: {
        activeSubmissionId: 'revision-2',
        status: 'pending',
      },
      submissionMode: 'update',
      submission: {
        _id: 'revision-2',
        reviewStatus: 'pending',
        reviewedAt: 0,
        reviewedBy: '',
        reviewNote: '',
      },
      listing: {
        activeSubmissionId: 'revision-2',
        status: 'unlisted',
      },
      event: {
        _id: 'event-1',
        action: 'public_market.submitted',
      },
    })
  })

  it('creates a new public revision when a private workshop work is submitted to YunLeFun', async () => {
    const { source, changes } = sourceFixture({
      app: appRecord({
        isPublic: false,
        audience: 'workshop',
        status: 'approved',
      }),
      submission: submission({
        reviewStatus: 'approved',
        snapshot: {
          ...submission().snapshot,
          audience: 'workshop',
          isPublic: false,
        },
      }),
      listing: null,
    })
    const workflow = createPublicMarketSubmissionModule(source, {
      now: () => 1_750_000_000_000,
      eventId: () => 'event-1',
      submissionId: () => 'revision-3',
    })

    await expect(workflow.submit(
      'app-1',
      { uid: 'owner-1', login: 'YunYouJun' },
      { makePublic: true },
    )).resolves.toEqual({
      appId: 'app-1',
      submissionId: 'revision-3',
      reviewStatus: 'pending',
    })

    expect(changes).toHaveLength(1)
    expect(changes[0]).toMatchObject({
      appPatch: {
        audience: 'public',
        isPublic: true,
        currentRevisionId: 'revision-3',
        publishedSubmissionId: 'revision-3',
        activeSubmissionId: 'revision-3',
        status: 'pending',
      },
      submissionMode: 'create',
      submission: {
        _id: 'revision-3',
        revision: 3,
        reviewStatus: 'pending',
        snapshot: {
          audience: 'public',
          isPublic: true,
        },
      },
      listing: {
        activeSubmissionId: 'revision-3',
        approvedRevisionId: '',
        status: 'unlisted',
      },
    })
    expect(changes[0]?.submission._id).not.toBe('revision-2')
  })
})
