import type {
  AppAccessMode,
  AppAudience,
  AppReleaseStage,
  AppSubmissionKind,
  CreateAppForm,
} from '~/types/app'
import { createError } from 'h3'

const SLUG_PATTERN = /^[a-z][a-z0-9-]{1,49}$/
const THEME_COLOR_PATTERN = /^#[0-9a-f]{6}$/i
const GITHUB_REPO_PATTERN = /^[\w.-]+\/[\w.-]+$/
const FIRST_PARTY_ZONE = 'yunle.fun'

export interface NormalizedSubmissionInput {
  kind: AppSubmissionKind
  snapshot: CreateAppForm
}

export function isYunLeFunFirstPartyHostname(hostname: string): boolean {
  const normalized = hostname.trim().replace(/\.$/, '').toLowerCase()
  return normalized === FIRST_PARTY_ZONE || normalized.endsWith(`.${FIRST_PARTY_ZONE}`)
}

export function normalizeSubmissionInput(
  value: unknown,
  options: { thirdPartyEnabled?: boolean } = {},
): NormalizedSubmissionInput {
  if (!isRecord(value))
    invalid('提交内容格式不正确')

  const kind = normalizeKind(value.kind)
  const audience = normalizeAudience(value.audience)
  if (kind === 'third_party' && !options.thirdPartyEnabled) {
    throw createError({
      statusCode: 403,
      statusMessage: '第三方应用入驻敬请期待',
      data: { code: 'THIRD_PARTY_NOT_OPEN' },
    })
  }

  const name = requiredString(value.name, '应用名称', 50)
  const slug = requiredString(value.slug, 'slug', 50).toLowerCase()
  if (!SLUG_PATTERN.test(slug))
    invalid('slug 必须以小写字母开头，且只能包含小写字母、数字和连字符')

  const websiteUrl = normalizeHttpsUrl(value.websiteUrl, '应用网址', true)
  const privacyPolicyUrl = normalizeHttpsUrl(value.privacyPolicyUrl, '隐私政策链接', true)
  const supportUrl = normalizeHttpsUrl(value.supportUrl, '支持链接', true)
  const hostname = new URL(websiteUrl).hostname
  if (kind === 'first_party' && audience === 'public' && !isYunLeFunFirstPartyHostname(hostname))
    invalid('第一方应用网址必须属于 yunle.fun')

  const githubRepo = optionalString(value.githubRepo, 'GitHub 仓库', 160)
  if (githubRepo && !GITHUB_REPO_PATTERN.test(githubRepo))
    invalid('GitHub 仓库格式必须为 owner/repo')

  const themeColor = optionalString(value.themeColor, '主题色', 7) || '#007AFF'
  if (!THEME_COLOR_PATTERN.test(themeColor))
    invalid('主题色必须为 #RRGGBB')

  const tags = normalizeTags(value.tags)

  return {
    kind,
    snapshot: {
      name,
      slug,
      description: optionalString(value.description, '应用简介', 300),
      githubRepo,
      websiteUrl,
      privacyPolicyUrl,
      supportUrl,
      trustedHosts: normalizeTrustedHosts(value.trustedHosts, hostname),
      backupUrl: normalizeHttpsUrl(value.backupUrl, '备用链接'),
      logo: normalizeHttpsUrl(value.logo, 'Logo 链接'),
      emoji: optionalString(value.emoji, 'Emoji', 16) || '📱',
      themeColor,
      category: optionalString(value.category, '分类', 40) || '其他',
      tags,
      isPublic: audience === 'public',
      audience,
      accessMode: normalizeAccessMode(value.accessMode),
      releaseStage: normalizeReleaseStage(value.releaseStage),
    },
  }
}

export function publicProjectionFromSubmission(snapshot: CreateAppForm) {
  return {
    name: snapshot.name,
    slug: snapshot.slug,
    description: snapshot.description || '',
    githubRepo: snapshot.githubRepo || '',
    websiteUrl: snapshot.websiteUrl || '',
    privacyPolicyUrl: snapshot.privacyPolicyUrl || '',
    supportUrl: snapshot.supportUrl || '',
    trustedHosts: snapshot.trustedHosts || [],
    backupUrl: snapshot.backupUrl || '',
    logo: snapshot.logo || '',
    emoji: snapshot.emoji || '📱',
    themeColor: snapshot.themeColor || '#007AFF',
    category: snapshot.category || '其他',
    tags: snapshot.tags || [],
    isPublic: snapshot.audience === 'public',
    audience: snapshot.audience || 'public',
    accessMode: snapshot.accessMode || 'public',
    releaseStage: snapshot.releaseStage || 'stable',
  }
}

function normalizeKind(value: unknown): AppSubmissionKind {
  if (value === undefined || value === 'first_party')
    return 'first_party'
  if (value === 'third_party')
    return value
  return invalid('提交类型不正确')
}

function normalizeAccessMode(value: unknown): AppAccessMode {
  if (value === undefined || value === 'public')
    return 'public'
  if (value === 'login_required' || value === 'invite_only')
    return value
  return invalid('访问方式不正确')
}

function normalizeAudience(value: unknown): AppAudience {
  if (value === undefined || value === 'public')
    return 'public'
  if (value === 'workshop' || value === 'owner')
    return value
  return invalid('可见范围不正确')
}

function normalizeReleaseStage(value: unknown): AppReleaseStage {
  if (value === undefined || value === 'stable')
    return 'stable'
  if (value === 'beta')
    return value
  return invalid('发布阶段不正确')
}

function normalizeHttpsUrl(value: unknown, label: string, required = false): string {
  const raw = typeof value === 'string' ? value.trim() : ''
  if (!raw) {
    if (required)
      invalid(`${label}必填`)
    return ''
  }
  if (raw.length > 2048)
    invalid(`${label}不能超过 2048 个字符`)
  let parsed: URL
  try {
    parsed = new URL(raw)
  }
  catch {
    return invalid(`${label}格式不正确`)
  }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password)
    invalid(`${label}必须使用不含账号信息的 HTTPS 地址`)
  parsed.hash = ''
  return parsed.toString()
}

function normalizeTrustedHosts(value: unknown, websiteHostname: string): string[] {
  if (value === undefined)
    return [websiteHostname]
  if (!Array.isArray(value))
    invalid('授信域名格式不正确')
  const hosts = [...new Set(value.map(item => String(item).trim().toLowerCase()).filter(Boolean))]
  if (hosts.length > 10)
    invalid('授信域名最多 10 个')
  for (const host of hosts) {
    if (host.length > 253 || host.includes('/') || host.includes(':'))
      invalid('授信域名格式不正确')
  }
  return hosts.includes(websiteHostname) ? hosts : [websiteHostname, ...hosts]
}

function normalizeTags(value: unknown): string[] {
  if (value === undefined)
    return []
  if (!Array.isArray(value))
    invalid('标签格式不正确')
  const tags = [...new Set(value.map(item => String(item).trim()).filter(Boolean))]
  if (tags.length > 10 || tags.some(tag => tag.length > 24))
    invalid('标签最多 10 个，且每个不超过 24 个字符')
  return tags
}

function requiredString(value: unknown, label: string, maxLength: number): string {
  const normalized = optionalString(value, label, maxLength)
  if (!normalized)
    invalid(`${label}必填`)
  return normalized
}

function optionalString(value: unknown, label: string, maxLength: number): string {
  if (value === undefined || value === null)
    return ''
  if (typeof value !== 'string')
    invalid(`${label}格式不正确`)
  const normalized = value.trim()
  if (normalized.length > maxLength)
    invalid(`${label}不能超过 ${maxLength} 个字符`)
  return normalized
}

function invalid(message: string): never {
  throw createError({ statusCode: 400, statusMessage: message })
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
