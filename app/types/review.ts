export type ReviewStatus = 'published' | 'pending' | 'rejected'

export type ReportReason = 'illegal' | 'porn' | 'abuse' | 'spam' | 'privacy' | 'other'

export interface ReviewModerationInfo {
  suggestion: string
  label?: string
  subLabel?: string
  keywords?: string[]
  requestId?: string
  error?: string
}

export interface ReviewRecord {
  _id: string
  appKey: string
  appId: string
  uid: string
  authorName: string
  authorAvatar?: string
  rating: number
  title?: string
  content: string
  status: ReviewStatus
  rejectedReason?: string
  moderation?: ReviewModerationInfo
  createdAt: number
  updatedAt: number
  publishedAt?: number
}

export interface ReviewPublic {
  _id: string
  appKey: string
  authorName: string
  authorAvatar?: string
  rating: number
  title?: string
  content: string
  createdAt: number
  updatedAt: number
  publishedAt?: number
}

export interface ReviewSummary {
  average: number
  count: number
  distribution: Record<1 | 2 | 3 | 4 | 5, number>
}

export interface ReviewListResponse {
  summary: ReviewSummary
  reviews: ReviewPublic[]
  myReview: ReviewRecord | null
}

export interface SubmitReviewInput {
  appKey: string
  rating: number
  title?: string
  content: string
}

export interface SubmitReviewResponse {
  status: ReviewStatus
  message?: string
  review: ReviewRecord
}

export interface SubmitReportInput {
  targetType: 'app' | 'review'
  targetId: string
  appKey?: string
  reason: ReportReason
  detail?: string
}

export const REPORT_REASON_LABELS: Record<ReportReason, string> = {
  illegal: '违法违规',
  porn: '色情低俗',
  abuse: '人身攻击',
  spam: '垃圾营销',
  privacy: '隐私泄露',
  other: '其他',
}

export type ReportStatus = 'open' | 'resolved' | 'dismissed'

export const REPORT_STATUS_LABELS: Record<ReportStatus, string> = {
  open: '待处理',
  resolved: '已处理',
  dismissed: '已忽略',
}

/**
 * 「我的举报」列表项：用户视角，仅暴露对举报人安全的字段，
 * 不含机审结果 / 处理人 / 处理备注等内部审核信息。
 */
export interface MyReportItem {
  _id: string
  targetType: 'app' | 'review'
  targetId: string
  appKey?: string
  /** 关联应用名称（服务端按 appKey 回填，缺省回退展示 slug）。 */
  appName?: string
  reason: ReportReason
  detail?: string
  status: ReportStatus
  createdAt: number
  handledAt?: number
}

export interface MyReportListResponse {
  reports: MyReportItem[]
}
