import type { AppRecord } from '~/types/app'

export type YunLeFunSubmissionAction = 'submit' | 'make_public' | null

export interface YunLeFunSubmissionState {
  status:
    | 'private'
    | 'draft'
    | 'pending'
    | 'in_review'
    | 'changes_requested'
    | 'rejected'
    | 'awaiting_publication'
    | 'listed'
    | 'suspended'
    | 'delisted'
  statusLabel: string
  detail: string
  action: YunLeFunSubmissionAction
  actionLabel: string
}

export function getYunLeFunSubmissionState(app: AppRecord): YunLeFunSubmissionState {
  if ((app.audience || 'public') !== 'public') {
    return {
      status: 'private',
      statusLabel: '个人工坊专属',
      detail: '投稿后会创建公开版本；站点自身的登录或访问保护保持不变。',
      action: 'make_public',
      actionLabel: '设为公开并投稿云乐坊',
    }
  }

  const reviewStatus = app.latestSubmission?.reviewStatus
  const currentRevisionId = app.currentRevisionId || app.publishedSubmissionId || ''
  const activeSubmissionId = app.yunlefunListing?.activeSubmissionId || app.activeSubmissionId || ''
  const approvedRevisionId = app.yunlefunListing?.approvedRevisionId || ''
  const listingStatus = app.yunlefunListing?.status
  const isCurrentRevisionListed = Boolean(currentRevisionId && approvedRevisionId === currentRevisionId)
  const hasOlderListedRevision = listingStatus === 'listed'
    && Boolean(approvedRevisionId)
    && approvedRevisionId !== currentRevisionId

  if (isCurrentRevisionListed && listingStatus === 'listed') {
    return {
      status: 'listed',
      statusLabel: '已上架云乐坊',
      detail: '当前版本正在云乐坊公开展示。',
      action: null,
      actionLabel: '已上架云乐坊',
    }
  }

  if (isCurrentRevisionListed && (listingStatus === 'suspended' || listingStatus === 'delisted')) {
    return {
      status: listingStatus,
      statusLabel: listingStatus === 'suspended' ? '云乐坊展示已暂停' : '已从云乐坊下架',
      detail: app.yunlefunListing?.reason || (
        listingStatus === 'suspended'
          ? '当前版本已被管理员暂停展示。'
          : '当前版本已由管理员从云乐坊下架。'
      ),
      action: null,
      actionLabel: listingStatus === 'suspended' ? '等待恢复展示' : '已从云乐坊下架',
    }
  }

  if (reviewStatus === 'approved' && currentRevisionId && activeSubmissionId === currentRevisionId) {
    return {
      status: 'awaiting_publication',
      statusLabel: '审核通过',
      detail: '当前版本已通过审核，等待管理员上架到云乐坊。',
      action: null,
      actionLabel: '等待上架云乐坊',
    }
  }

  if (reviewStatus === 'pending' || reviewStatus === 'in_review') {
    return {
      status: reviewStatus,
      statusLabel: reviewStatus === 'pending' ? '等待审核' : '审核中',
      detail: hasOlderListedRevision
        ? '新版正在审核，云乐坊继续展示上一批准版本。'
        : reviewStatus === 'pending'
          ? '投稿已进入云乐坊审核队列。'
          : '管理员正在核验当前版本。',
      action: null,
      actionLabel: '云乐坊审核中',
    }
  }

  if (reviewStatus === 'changes_requested' || reviewStatus === 'rejected') {
    return {
      status: reviewStatus,
      statusLabel: reviewStatus === 'changes_requested' ? '需要修改' : '审核未通过',
      detail: app.latestSubmission?.reviewNote || (
        reviewStatus === 'changes_requested'
          ? '请按审核意见修改后重新投稿。'
          : '当前版本未通过云乐坊审核，可以修改后重新投稿。'
      ),
      action: 'submit',
      actionLabel: '重新投稿云乐坊',
    }
  }

  if (hasOlderListedRevision) {
    return {
      status: 'draft',
      statusLabel: '新版未投稿',
      detail: '云乐坊仍展示上一批准版本；你可以投稿当前新版。',
      action: 'submit',
      actionLabel: '投稿新版到云乐坊',
    }
  }

  return {
    status: 'draft',
    statusLabel: '尚未投稿',
    detail: '当前公开版本还没有投稿云乐坊。',
    action: 'submit',
    actionLabel: '投稿云乐坊',
  }
}
