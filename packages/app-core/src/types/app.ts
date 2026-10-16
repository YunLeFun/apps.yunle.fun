/** 默认 emoji */
export const DEFAULT_EMOJI = '📱'

/** 默认主题色 */
export const DEFAULT_THEME_COLOR = '#007AFF'

/** 预设主题色列表 */
export const THEME_COLORS = [
  '#007AFF', // iOS 蓝
  '#34C759', // iOS 绿
  '#FF9500', // iOS 橙
  '#FF3B30', // iOS 红
  '#AF52DE', // iOS 紫
  '#FF2D55', // iOS 粉
  '#5856D6', // iOS 靛蓝
  '#00C7BE', // iOS 青
  '#FFD60A', // iOS 黄
  '#8E8E93', // iOS 灰
] as const

/** 预设分类列表 */
export const APP_CATEGORIES = [
  { label: '工具', icon: '🔧' },
  { label: '效率', icon: '⚡' },
  { label: '社交', icon: '💬' },
  { label: '娱乐', icon: '🎮' },
  { label: '游戏', icon: '🕹️' },
  { label: '教育', icon: '📚' },
  { label: '生活', icon: '🏠' },
  { label: '开发', icon: '💻' },
  { label: '设计', icon: '🎨' },
  { label: '整活', icon: '🤡' },
  { label: '其他', icon: '📦' },
] as const

/**
 * 应用审核状态
 *
 * - `pending`：等待审核（新创建或重新提交后默认状态）
 * - `approved`：审核通过，配合 `isPublic: true` 才会在工坊/寻乐对所有人可见
 * - `rejected`：审核被拒，用户可在工坊看到 `rejectedReason` 后修改重新提交
 */
export type AppStatus = 'pending' | 'approved' | 'rejected'

/** 默认审核状态 */
export const DEFAULT_APP_STATUS: AppStatus = 'pending'

/** 目录访问方式。受限访问不代表审核不通过。 */
export type AppAccessMode = 'public' | 'login_required' | 'invite_only'

/** App 元数据在云乐坊目录中的可见受众。 */
export type AppAudience = 'public' | 'workshop' | 'owner'

/** 面向用户展示的发布阶段。 */
export type AppReleaseStage = 'stable' | 'beta'

/** 图标在启动器中的用途：完整图标自带背景，主体图标由启动器补背景。 */
export type AppIconAssetRole = 'app-icon' | 'mark'

/** 同一用途的默认与深色模式资源。深色资源缺省时回退默认资源。 */
export interface AppIconAssetVariants {
  src: string
  darkSrc?: string
}

/** 应用图标资产；完整图标建议提供，主体图标和深色版本均可选。 */
export interface AppIconAssets {
  appIcon?: AppIconAssetVariants
  mark?: AppIconAssetVariants
}

/** 一次提交的审核状态。 */
export type AppReviewStatus
  = | 'draft'
    | 'pending'
    | 'in_review'
    | 'changes_requested'
    | 'approved'
    | 'rejected'
    | 'withdrawn'

/** 应用在公开目录中的分发状态。 */
export type AppPublicationStatus
  = | 'unpublished'
    | 'published'
    | 'suspended'
    | 'delisted'

export type YunLeFunListingStatus = 'unlisted' | 'listed' | 'suspended' | 'delisted'

export interface YunLeFunListing {
  shortName?: string
  appId: string
  status: YunLeFunListingStatus
  approvedRevisionId?: string
  activeSubmissionId?: string
  reason?: string
  submittedAt?: number
  reviewedAt?: number
  reviewedBy?: string
  createdAt: number
  updatedAt: number
}

/** 当前仅开放 first_party；third_party 保留为后续兼容入口。 */
export type AppSubmissionKind = 'first_party' | 'third_party'

export type AppOwnershipStatus = 'pending' | 'verified' | 'failed'

export type AppOwnershipMethod
  = | 'yunle_infra'
    | 'dns_txt'
    | 'well_known'
    | 'github'
    | 'admin_override'

export interface AppOwnershipCheck {
  key: 'hostname' | 'cloudflare_dns' | 'deployment_project' | 'https' | 'redirect' | 'repository' | 'privacy' | 'support'
  status: 'pass' | 'warning' | 'fail'
  summary: string
  detail?: string
}

export interface AppOwnershipVerification {
  status: AppOwnershipStatus
  method?: AppOwnershipMethod
  hostname?: string
  checks: AppOwnershipCheck[]
  verifiedAt?: number
  verifiedBy?: string
}

/** 应用数据模型 - 对应 CloudBase NoSQL 集合 `apps` */
export interface AppRecord {
  identityVersion?: number
  /** 市场上架时取得的全局唯一短名；所属空间 slug 独立。 */
  marketShortName?: string
  /** 文档 ID（CloudBase 自动生成） */
  _id: string
  /** 创建者用户 ID（CloudBase 服务端自动注入，用于安全规则校验） */
  _openid?: string
  /** 应用所有者用户名 */
  ownerLoginKey?: string
  ownerLogin: string
  /** 稳定所有者 UID；新流程不再依赖浏览器可写的 _openid。 */
  ownerUid?: string
  /** 应用名称 */
  name: string
  /** 展示名称的服务端标准化键；仅用于搜索归一化，不要求唯一，不向普通用户展示。 */
  nameKey?: string
  /** 所属空间内唯一标识符（URL slug） */
  slug: string
  /** 应用描述 */
  description?: string
  /** 绑定的 GitHub 仓库（可选，格式：owner/repo） */
  githubRepo?: string
  /** 应用网页链接 */
  websiteUrl?: string
  /** 面向用户公开的隐私政策。 */
  privacyPolicyUrl?: string
  /** 面向用户公开的支持入口。 */
  supportUrl?: string
  /** 授信 JSAPI 域名（可注册域，子域自动匹配；仅审核通过的应用配置） */
  trustedHosts?: string[]
  /** 备用链接 */
  backupUrl?: string
  /** 自定义 Logo 图片 URL（优先于 emoji 展示） */
  logo?: string
  /** 结构化图标资产；缺省时兼容使用旧版 logo。 */
  iconAssets?: AppIconAssets
  /** 应用 emoji 图标（无 logo 时展示，默认 📱） */
  emoji?: string
  /** 主题色（十六进制色值，默认 #007AFF） */
  themeColor?: string
  /** 分类 */
  category?: string
  /** 标签 */
  tags?: string[]
  /**
   * 评分（0-5）。真实来源为评论系统聚合（reviewSummary）；
   * 此字段仅作列表展示的去规范化缓存，详情页一律以评论实时聚合为准。
   * 由服务端在评论发布/删除时回写（见 server/utils/app-rating.ts）。
   */
  rating?: number
  /** 评分人数（已发布评论数）。与 rating 同为评论聚合缓存；为 0 / 缺省表示暂无真实评分 */
  ratingCount?: number
  /** 评分聚合最近回写时间戳 */
  ratingUpdatedAt?: number
  /** 年龄分级文案（展示用，如「4+」） */
  age?: string
  /** 应用截图 URL 列表（预览区真实截图；缺省回退占位面板） */
  screenshots?: string[]
  /** 开发者展示名（中文名等；缺省回退 ownerLogin / GitHub 资料） */
  developerName?: string
  /** 按次/一次性消费的云币数量（>0 表示付费应用，用于「App 内购买项目」展示与门控） */
  coinCost?: number
  /** 是否会员专属（用于「会员专属」展示与门控） */
  requiresMembership?: boolean
  /** 用户是否愿意公开（默认 false；与 status=approved 同时满足才会真正对外可见） */
  isPublic: boolean
  /** 目录受众；缺省记录按旧版 isPublic 兼容迁移。 */
  audience?: AppAudience
  /** 目录访问方式，与审核/发布状态正交。 */
  accessMode?: AppAccessMode
  /** Stable / Beta 展示标记。 */
  releaseStage?: AppReleaseStage
  /** 官方标记只能由管理后台授予。 */
  isOfficial?: boolean
  /** 当前目录分发状态。 */
  publicationStatus?: AppPublicationStatus
  /** 当前公开投影对应的提交。 */
  publishedSubmissionId?: string
  /** 坊主当前发布的不可变 revision。 */
  currentRevisionId?: string
  /** 最近一次待处理提交。 */
  activeSubmissionId?: string
  /** 管理/所有者视图附带的最近提交；公开目录不会返回。 */
  latestSubmission?: AppSubmission
  /** 仅所有者视图：表单元数据对应的 revision，独立于仍在审核的 submission。 */
  ownerMetadataRevisionId?: string
  /** 所有者视图附带的云乐坊上架指针；公开目录不会返回。 */
  yunlefunListing?: YunLeFunListing
  /** 审核状态（必填，默认 pending） */
  status: AppStatus
  /** 拒绝原因（仅 status=rejected 时有值） */
  rejectedReason?: string
  /** 最近一次审核时间戳 */
  reviewedAt?: number
  /** 创建时间 */
  createdAt: number
  /** 更新时间 */
  updatedAt: number
}

/** 创建/编辑应用时的表单数据 */
export interface CreateAppForm {
  name: string
  slug: string
  description?: string
  githubRepo?: string
  websiteUrl?: string
  privacyPolicyUrl?: string
  supportUrl?: string
  trustedHosts?: string[]
  backupUrl?: string
  logo?: string
  iconAssets?: AppIconAssets
  emoji?: string
  themeColor?: string
  category?: string
  tags?: string[]
  isPublic: boolean
  audience?: AppAudience
  accessMode?: AppAccessMode
  releaseStage?: AppReleaseStage
}

/**
 * 每次新增或修改都形成不可变提交快照。
 * 审核只改变 submission 的状态，不直接覆盖线上 AppRecord 投影。
 */
export interface AppSubmission {
  _id: string
  appId: string
  revision: number
  kind: AppSubmissionKind
  submitterUid: string
  submitterLogin?: string
  reviewStatus: AppReviewStatus
  snapshot: CreateAppForm
  ownership: AppOwnershipVerification
  submittedAt: number
  createdAt: number
  updatedAt: number
  reviewedAt?: number
  reviewedBy?: string
  reviewNote?: string
}

export type AppReviewEventAction
  = | 'submission.created'
    | 'submission.updated'
    | 'submission.withdrawn'
    | 'review.started'
    | 'review.changes_requested'
    | 'review.approved'
    | 'review.rejected'
    | 'ownership.verified'
    | 'ownership.failed'
    | 'publication.published'
    | 'publication.suspended'
    | 'publication.delisted'
    | 'publication.restored'
    | 'publication.emergency_published'
    | 'public_market.submitted'
    | 'public_market.listed'
    | 'public_market.delisted'

/** 追加写审核/发布事件；事件写入后不允许修改或删除。 */
export interface AppReviewEvent {
  _id: string
  appId: string
  submissionId?: string
  action: AppReviewEventAction
  actorType: 'submitter' | 'admin' | 'system'
  actorId: string
  actorLogin?: string
  note?: string
  metadata?: Record<string, unknown>
  createdAt: number
}

export interface AppSubmissionAccess {
  canSubmitFirstParty: boolean
  thirdPartyEnabled: boolean
  thirdPartyMessage: string
}

export interface AppSubmissionResult {
  app: AppRecord
  submission: AppSubmission
}
