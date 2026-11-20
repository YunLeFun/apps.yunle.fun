export const DEFAULT_PUBLIC_APP_BASE_URL = 'https://apps.yunle.fun'
export const WORKSHOP_ID_PATTERN = /^[2-9A-HJKMNP-Z]{6}$/

// Also recognized by the native router when an in-app browser keeps the HTTPS link.
export function boardAppUrl(path: string): string | null {
  const boardId = /^\/boards\/([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/.exec(path)?.[1]
  return boardId && path.length === '/boards/'.length + boardId.length ? `yunlefun://board/${boardId}` : null
}

export function conversationCardAppUrl(path: string): string | null {
  const match = /^\/cards\/([a-z][a-z0-9-]{0,31}\.[a-z][a-z0-9-]{0,31})\/([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/.exec(path)
  return match?.[0] === path ? `yunlefun://card/${match[1]}/${match[2]}` : null
}

function resolvePublicAppBaseUrl(configuredBaseUrl?: string): string {
  try {
    const url = new URL(configuredBaseUrl || DEFAULT_PUBLIC_APP_BASE_URL)
    if (url.protocol === 'https:')
      return url.origin
  }
  catch {
    // Fall back to the production origin below.
  }

  return DEFAULT_PUBLIC_APP_BASE_URL
}

/**
 * Build a stable public URL for sharing a personal workshop.
 *
 * Native Capacitor pages run under `capacitor://localhost`; that origin is
 * intentionally ignored because it cannot be opened outside the app.
 */
export function buildPublicWorkshopUrl(
  workshopId: string,
  configuredBaseUrl?: string,
): string {
  const normalizedId = workshopId.trim().toUpperCase()
  if (!normalizedId)
    return ''

  return new URL(
    `/w/${encodeURIComponent(normalizedId)}`,
    resolvePublicAppBaseUrl(configuredBaseUrl),
  ).href
}

export function normalizeWorkshopId(value: string): string {
  const workshopId = value.trim().toUpperCase()
  if (!WORKSHOP_ID_PATTERN.test(workshopId))
    throw new Error('个人工坊链接格式无效')
  return workshopId
}

export function parseWorkshopLink(
  content: string,
  extraAllowedHosts: readonly string[] = [],
): string {
  const allowedHosts = new Set([
    new URL(DEFAULT_PUBLIC_APP_BASE_URL).hostname,
    ...extraAllowedHosts,
  ])
  let url: URL
  try {
    url = new URL(content.trim())
  }
  catch {
    throw new Error('二维码不是有效的个人工坊链接')
  }
  if (url.protocol !== 'https:' || !allowedHosts.has(url.hostname))
    throw new Error('二维码不是云乐坊个人工坊链接')

  const match = url.pathname.match(/^\/w\/([^/]+)\/?$/)
  if (!match?.[1])
    throw new Error('个人工坊链接格式无效')

  try {
    return normalizeWorkshopId(decodeURIComponent(match[1]))
  }
  catch {
    throw new Error('个人工坊链接格式无效')
  }
}
