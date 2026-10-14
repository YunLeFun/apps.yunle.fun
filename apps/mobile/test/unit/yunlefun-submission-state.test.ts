import type { AppRecord, AppSubmission } from '../../app/types/app'
import { describe, expect, it } from 'vitest'
import { getYunLeFunSubmissionState } from '../../app/utils/yunlefunSubmission'

function submission(overrides: Partial<AppSubmission> = {}): AppSubmission {
  return {
    _id: 'revision-2',
    appId: 'app-1',
    revision: 2,
    kind: 'first_party',
    submitterUid: 'owner-1',
    reviewStatus: 'draft',
    snapshot: {
      name: '内部工具',
      slug: 'internal-tool',
      websiteUrl: 'https://tool.example.com/',
      isPublic: false,
      audience: 'workshop',
    },
    ownership: { status: 'pending', checks: [] },
    submittedAt: 2,
    createdAt: 1,
    updatedAt: 2,
    ...overrides,
  }
}

function appRecord(overrides: Partial<AppRecord> = {}): AppRecord {
  return {
    _id: 'app-1',
    ownerLogin: 'YunYouJun',
    ownerUid: 'owner-1',
    name: '内部工具',
    slug: 'internal-tool',
    websiteUrl: 'https://tool.example.com/',
    isPublic: false,
    audience: 'workshop',
    status: 'approved',
    publicationStatus: 'published',
    currentRevisionId: 'revision-2',
    publishedSubmissionId: 'revision-2',
    activeSubmissionId: '',
    latestSubmission: submission(),
    createdAt: 1,
    updatedAt: 2,
    ...overrides,
  }
}

describe('yunLeFun submission state', () => {
  it('offers an explicit public conversion for a private workshop work', () => {
    expect(getYunLeFunSubmissionState(appRecord())).toMatchObject({
      status: 'private',
      statusLabel: '个人工坊专属',
      action: 'make_public',
      actionLabel: '设为公开并投稿云乐坊',
    })
  })

  it('uses a disabled Chinese reviewing state while YunLeFun is checking the revision', () => {
    expect(getYunLeFunSubmissionState(appRecord({
      isPublic: true,
      audience: 'public',
      status: 'pending',
      activeSubmissionId: 'revision-2',
      latestSubmission: submission({
        reviewStatus: 'in_review',
        snapshot: {
          ...submission().snapshot,
          audience: 'public',
          isPublic: true,
        },
      }),
      yunlefunListing: {
        appId: 'app-1',
        status: 'unlisted',
        approvedRevisionId: '',
        activeSubmissionId: 'revision-2',
        createdAt: 1,
        updatedAt: 2,
      },
    }))).toMatchObject({
      status: 'in_review',
      statusLabel: '审核中',
      action: null,
      actionLabel: '云乐坊审核中',
    })
  })

  it('shows an approved revision as awaiting publication instead of offering resubmission', () => {
    expect(getYunLeFunSubmissionState(appRecord({
      isPublic: true,
      audience: 'public',
      activeSubmissionId: 'revision-2',
      latestSubmission: submission({
        reviewStatus: 'approved',
        snapshot: {
          ...submission().snapshot,
          audience: 'public',
          isPublic: true,
        },
      }),
      yunlefunListing: {
        appId: 'app-1',
        status: 'unlisted',
        approvedRevisionId: '',
        activeSubmissionId: 'revision-2',
        createdAt: 1,
        updatedAt: 2,
      },
    }))).toMatchObject({
      status: 'awaiting_publication',
      statusLabel: '审核通过',
      action: null,
      actionLabel: '等待上架云乐坊',
    })
  })

  it('shows the approved listing as already available in YunLeFun', () => {
    expect(getYunLeFunSubmissionState(appRecord({
      isPublic: true,
      audience: 'public',
      latestSubmission: submission({
        reviewStatus: 'approved',
        snapshot: {
          ...submission().snapshot,
          audience: 'public',
          isPublic: true,
        },
      }),
      yunlefunListing: {
        appId: 'app-1',
        status: 'listed',
        approvedRevisionId: 'revision-2',
        activeSubmissionId: '',
        createdAt: 1,
        updatedAt: 2,
      },
    }))).toMatchObject({
      status: 'listed',
      statusLabel: '已上架云乐坊',
      action: null,
      actionLabel: '已上架云乐坊',
    })
  })

  it.each([
    ['changes_requested', '需要修改'],
    ['rejected', '审核未通过'],
  ] as const)('offers resubmission when review status is %s', (reviewStatus, statusLabel) => {
    expect(getYunLeFunSubmissionState(appRecord({
      isPublic: true,
      audience: 'public',
      latestSubmission: submission({
        reviewStatus,
        reviewNote: '请补充隐私政策',
        snapshot: {
          ...submission().snapshot,
          audience: 'public',
          isPublic: true,
        },
      }),
    }))).toMatchObject({
      status: reviewStatus,
      statusLabel,
      detail: '请补充隐私政策',
      action: 'submit',
      actionLabel: '重新投稿云乐坊',
    })
  })

  it('keeps the approved version listed while offering the newer draft for submission', () => {
    expect(getYunLeFunSubmissionState(appRecord({
      isPublic: true,
      audience: 'public',
      currentRevisionId: 'revision-3',
      publishedSubmissionId: 'revision-3',
      latestSubmission: submission({
        _id: 'revision-3',
        revision: 3,
        reviewStatus: 'draft',
        snapshot: {
          ...submission().snapshot,
          audience: 'public',
          isPublic: true,
        },
      }),
      yunlefunListing: {
        appId: 'app-1',
        status: 'listed',
        approvedRevisionId: 'revision-2',
        activeSubmissionId: '',
        createdAt: 1,
        updatedAt: 3,
      },
    }))).toMatchObject({
      status: 'draft',
      statusLabel: '新版未投稿',
      action: 'submit',
      actionLabel: '投稿新版到云乐坊',
    })
  })

  it.each([
    ['suspended', '云乐坊展示已暂停'],
    ['delisted', '已从云乐坊下架'],
  ] as const)('does not offer duplicate submission for a %s listing', (status, statusLabel) => {
    expect(getYunLeFunSubmissionState(appRecord({
      isPublic: true,
      audience: 'public',
      latestSubmission: submission({
        reviewStatus: 'approved',
        snapshot: {
          ...submission().snapshot,
          audience: 'public',
          isPublic: true,
        },
      }),
      yunlefunListing: {
        appId: 'app-1',
        status,
        approvedRevisionId: 'revision-2',
        activeSubmissionId: '',
        reason: '管理员操作',
        createdAt: 1,
        updatedAt: 2,
      },
    }))).toMatchObject({
      status,
      statusLabel,
      action: null,
    })
  })
})
