export interface OriginRule {
  exactOrigin?: string
  wildcardHost?: string
  protocol?: string
  port?: string
}

function normalizeHost(host: string): string {
  return host.trim().toLowerCase().replace(/\.$/, '')
}

function isValidHostSuffix(host: string): boolean {
  const labels = host.split('.')
  return labels.length >= 2 && labels.every(label =>
    /^[a-z0-9-]+$/i.test(label) && !label.startsWith('-') && !label.endsWith('-'),
  )
}

function parseWildcardRule(value: string): OriginRule | null {
  const bare = value.match(/^\*\.([a-z0-9.-]+)$/i)
  if (bare) {
    const wildcardHost = normalizeHost(bare[1] || '')
    return wildcardHost && isValidHostSuffix(wildcardHost)
      ? { wildcardHost, protocol: 'https:', port: '' }
      : null
  }

  const withProtocol = value.match(/^([a-z][a-z0-9+.-]*):\/\/\*\.([^/?#]+)\/?$/i)
  if (!withProtocol)
    return null

  try {
    const probe = new URL(`${withProtocol[1]}://placeholder.${withProtocol[2]}`)
    if (probe.protocol !== 'http:' && probe.protocol !== 'https:')
      return null

    const wildcardHost = normalizeHost(probe.hostname.replace(/^placeholder\./, ''))
    return isValidHostSuffix(wildcardHost)
      ? { wildcardHost, protocol: probe.protocol, port: probe.port }
      : null
  }
  catch {
    return null
  }
}

function parseExactRule(value: string): OriginRule | null {
  try {
    const url = new URL(value)
    if (url.protocol !== 'http:' && url.protocol !== 'https:')
      return null
    return { exactOrigin: url.origin }
  }
  catch {
    return null
  }
}

export function parseOriginRule(value: string): OriginRule | null {
  const trimmed = value.trim()
  if (!trimmed)
    return null
  return parseWildcardRule(trimmed) ?? parseExactRule(trimmed)
}

export function readOriginRules(value: unknown): OriginRule[] {
  if (typeof value !== 'string')
    return []

  return value
    .split(',')
    .map(parseOriginRule)
    .filter((rule): rule is OriginRule => !!rule)
}

function hostMatchesWildcard(host: string, wildcardHost: string): boolean {
  const normalizedHost = normalizeHost(host)
  return normalizedHost !== wildcardHost && normalizedHost.endsWith(`.${wildcardHost}`)
}

export function isAllowedOrigin(origin: string, rules: readonly OriginRule[]): boolean {
  let url: URL
  try {
    url = new URL(origin)
  }
  catch {
    return false
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:')
    return false

  return rules.some((rule) => {
    if (rule.exactOrigin)
      return url.origin === rule.exactOrigin
    if (!rule.wildcardHost)
      return false
    if (rule.protocol && url.protocol !== rule.protocol)
      return false
    if ((rule.port ?? '') !== url.port)
      return false
    return hostMatchesWildcard(url.hostname, rule.wildcardHost)
  })
}
