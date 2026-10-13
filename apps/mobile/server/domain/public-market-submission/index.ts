import type {
  AppRecord,
  AppReviewEvent,
  AppSubmission,
} from '../../../app/types/app'
import { randomUUID } from 'node:crypto'

export type PublicMarketListingStatus = 'unlisted' | 'listed' | 'suspended' | 'delisted'

export interface PublicMarketListingRecord {
  appId: string
  status: PublicMarketListingStatus
  approvedRevisionId: string
  activeSubmissionId: string
  submittedAt?: number
  createdAt: number
  updatedAt: number
}

export interface PublicMarketSubmissionPrincipal {
  uid: string
  login?: string
}

export interface PublicMarketSubmissionChange {
  appId: string
  appPatch: Partial<AppRecord>
  submission: AppSubmission
  submissionMode: 'create' | 'update'
  listing: PublicMarketListingRecord
  event: AppReviewEvent
}

export interface PublicMarketSubmissionSource {
  getOwnedApp: (appId: string, ownerUid: string) => Promise<AppRecord | null>
  getSubmission: (submissionId: string) => Promise<AppSubmission | null>
  getListing: (appId: string) => Promise<PublicMarketListingRecord | null>
  getLatestRevisionNumber: (appId: string) => Promise<number>
  commit: (change: PublicMarketSubmissionChange) => Promise<void>
}

export interface PublicMarketSubmissionModule {
  submit: (
    appId: string,
    principal: PublicMarketSubmissionPrincipal,
    options?: { makePublic?: boolean },
  ) => Promise<{ appId: string, submissionId: string, reviewStatus: 'pending' }>
}

export interface PublicMarketSubmissionDependencies {
  now: () => number
  eventId: () => string
  submissionId: () => string
}

export class PublicMarketSubmissionError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'PublicMarketSubmissionError'
  }
}

export function createPublicMarketSubmissionModule(
  source: PublicMarketSubmissionSource,
  dependencies: PublicMarketSubmissionDependencies = {
    now: () => Date.now(),
    eventId: () => entityId('review_event'),
    submissionId: () => entityId('submission'),
  },
): PublicMarketSubmissionModule {
  return {
    async submit(appId, principal, options = {}) {
      const app = await source.getOwnedApp(appId, principal.uid)
      if (!app)
        throw new PublicMarketSubmissionError('APP_NOT_FOUND', '应用不存在或无权管理')

      if ((app.audience || 'public') !== 'public' && !options.makePublic) {
        throw new PublicMarketSubmissionError(
          'YUNLEFUN_PUBLIC_AUDIENCE_REQUIRED',
          '只有公开作品可以投稿云乐坊',
        )
      }

      const submissionId = app.currentRevisionId || app.publishedSubmissionId
      if (!submissionId)
        throw new PublicMarketSubmissionError('APP_REVISION_MISSING', '应用还没有可投稿的版本')

      const [submission, listing] = await Promise.all([
        source.getSubmission(submissionId),
        source.getListing(appId),
      ])
      if (!submission || submission.appId !== appId)
        throw new PublicMarketSubmissionError('APP_REVISION_MISSING', '应用版本不存在')

      const makePublic = (app.audience || 'public') !== 'public' && options.makePublic === true
      if (makePublic) {
        const now = dependencies.now()
        const nextSubmissionId = dependencies.submissionId()
        const nextRevision = await source.getLatestRevisionNumber(appId) + 1
        const nextSubmission: AppSubmission = {
          _id: nextSubmissionId,
          appId,
          revision: nextRevision,
          kind: submission.kind,
          submitterUid: principal.uid,
          ...(principal.login ? { submitterLogin: principal.login } : {}),
          reviewStatus: 'pending',
          snapshot: {
            ...submission.snapshot,
            audience: 'public',
            isPublic: true,
          },
          ownership: {
            status: 'pending',
            ...(submission.ownership.hostname ? { hostname: submission.ownership.hostname } : {}),
            checks: submission.ownership.checks,
          },
          submittedAt: now,
          createdAt: now,
          updatedAt: now,
        }
        const change: PublicMarketSubmissionChange = {
          appId,
          appPatch: {
            audience: 'public',
            isPublic: true,
            publicationStatus: 'published',
            currentRevisionId: nextSubmissionId,
            publishedSubmissionId: nextSubmissionId,
            activeSubmissionId: nextSubmissionId,
            status: 'pending',
            rejectedReason: '',
            updatedAt: now,
          },
          submission: nextSubmission,
          submissionMode: 'create',
          listing: {
            appId,
            status: listing?.status === 'listed' ? 'listed' : 'unlisted',
            approvedRevisionId: listing?.approvedRevisionId || '',
            activeSubmissionId: nextSubmissionId,
            submittedAt: now,
            createdAt: listing?.createdAt || app.createdAt || now,
            updatedAt: now,
          },
          event: submittedEvent(
            dependencies.eventId(),
            appId,
            nextSubmissionId,
            principal,
            now,
            { visibilityChanged: true, previousAudience: app.audience || 'owner' },
          ),
        }
        await source.commit(change)
        return {
          appId,
          submissionId: nextSubmissionId,
          reviewStatus: 'pending',
        }
      }

      if (listing?.status === 'listed' && listing.approvedRevisionId === submissionId) {
        throw new PublicMarketSubmissionError(
          'YUNLEFUN_REVISION_ALREADY_LISTED',
          '当前版本已经上架云乐坊',
        )
      }
      if (listing?.approvedRevisionId === submissionId) {
        throw new PublicMarketSubmissionError(
          'YUNLEFUN_REVISION_PUBLICATION_MANAGED',
          listing.status === 'suspended'
            ? '当前版本的云乐坊展示已暂停，请等待管理员恢复'
            : '当前版本已由云乐坊完成审核，不能重复投稿',
        )
      }
      if (listing?.activeSubmissionId === submissionId && submission.reviewStatus === 'approved') {
        throw new PublicMarketSubmissionError(
          'YUNLEFUN_REVISION_AWAITING_PUBLICATION',
          '当前版本已通过审核，正在等待上架云乐坊',
        )
      }
      if (submission.reviewStatus === 'pending' || submission.reviewStatus === 'in_review') {
        throw new PublicMarketSubmissionError(
          'YUNLEFUN_REVISION_UNDER_REVIEW',
          '当前版本正在云乐坊审核中',
        )
      }

      const now = dependencies.now()
      const pendingSubmission: AppSubmission = {
        ...submission,
        reviewStatus: 'pending',
        submittedAt: now,
        updatedAt: now,
        reviewedAt: 0,
        reviewedBy: '',
        reviewNote: '',
      }
      const change: PublicMarketSubmissionChange = {
        appId,
        appPatch: {
          activeSubmissionId: submissionId,
          status: 'pending',
          updatedAt: now,
        },
        submission: pendingSubmission,
        submissionMode: 'update',
        listing: {
          appId,
          status: listing?.status === 'listed' ? 'listed' : 'unlisted',
          approvedRevisionId: listing?.approvedRevisionId || '',
          activeSubmissionId: submissionId,
          submittedAt: now,
          createdAt: listing?.createdAt || app.createdAt || now,
          updatedAt: now,
        },
        event: submittedEvent(dependencies.eventId(), appId, submissionId, principal, now),
      }
      await source.commit(change)
      return {
        appId,
        submissionId,
        reviewStatus: 'pending',
      }
    },
  }
}

function entityId(prefix: string): string {
  return `${prefix}_${randomUUID().replaceAll('-', '')}`
}

function submittedEvent(
  id: string,
  appId: string,
  submissionId: string,
  principal: PublicMarketSubmissionPrincipal,
  createdAt: number,
  metadata?: Record<string, unknown>,
): AppReviewEvent {
  return {
    _id: id,
    appId,
    submissionId,
    action: 'public_market.submitted',
    actorType: 'submitter',
    actorId: principal.uid,
    ...(principal.login ? { actorLogin: principal.login } : {}),
    ...(metadata ? { metadata } : {}),
    createdAt,
  }
}
