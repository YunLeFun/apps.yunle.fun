import { describe, expect, it } from 'vitest'
import {
  DIAGNOSTIC_LOG_STORAGE_KEY,
  loadDiagnosticLogs,
  MAX_DIAGNOSTIC_LOGS,
  pruneDiagnosticLogs,
  redactDiagnosticText,
  saveDiagnosticLogs,
  selectDiagnosticLogs,
  serializeDiagnosticLogArgument,
} from '../../app/utils/diagnostic-logs'

function createMemoryStorage(initial?: string) {
  const values = new Map<string, string>()
  if (initial !== undefined)
    values.set(DIAGNOSTIC_LOG_STORAGE_KEY, initial)
  return {
    getItem: (key: string) => values.get(key) ?? null,
    removeItem: (key: string) => values.delete(key),
    setItem: (key: string, value: string) => values.set(key, value),
    values,
  }
}

describe('diagnostic log utilities', () => {
  it('redacts credentials, signed URLs, contact details and long identifiers', () => {
    const message = redactDiagnosticText(
      'GET https://api.yunle.fun/private?sign=secret '
      + 'Authorization: Bearer abc.def '
      + 'access_token="token-value" '
      + 'email=user@example.com phone=13800138000 uid=1978032370372050944',
    )

    expect(message).toContain('[redacted-url:api.yunle.fun]')
    expect(message).toContain('Bearer [redacted]')
    expect(message).toContain('[redacted-email]')
    expect(message).toContain('[redacted-phone]')
    expect(message).toContain('[redacted-id]')
    expect(message).not.toContain('secret')
    expect(message).not.toContain('token-value')
    expect(message).not.toContain('user@example.com')
  })

  it('keeps a seven-day, 500-entry chronological ring buffer', () => {
    const now = Date.UTC(2026, 6, 29, 8)
    const entries = Array.from({ length: MAX_DIAGNOSTIC_LOGS + 10 }, (_, index) => ({
      level: 'info',
      message: `entry-${index}`,
      timestamp: now - (MAX_DIAGNOSTIC_LOGS + 10 - index) * 1000,
    }))
    entries.unshift({
      level: 'info',
      message: 'expired',
      timestamp: now - 8 * 24 * 60 * 60 * 1000,
    })

    const pruned = pruneDiagnosticLogs(entries, now)
    expect(pruned).toHaveLength(MAX_DIAGNOSTIC_LOGS)
    expect(pruned[0].message).toBe('entry-10')
    expect(pruned.at(-1)?.message).toBe(`entry-${MAX_DIAGNOSTIC_LOGS + 9}`)
  })

  it('selects only logs inside the user-defined time range', () => {
    const logs = [
      { level: 'warn', message: 'before', timestamp: 999 },
      { level: 'error', message: 'inside-a', timestamp: 1000 },
      { level: 'info', message: 'inside-b', timestamp: 2000 },
      { level: 'debug', message: 'after', timestamp: 2001 },
    ]
    expect(selectDiagnosticLogs(logs, 1000, 2000).map(entry => entry.message))
      .toEqual(['inside-a', 'inside-b'])
  })

  it('loads valid persisted logs and tolerates malformed local storage', () => {
    const now = Date.now()
    const storage = createMemoryStorage()
    const saved = saveDiagnosticLogs(storage, [
      { level: 'error', message: 'failed', timestamp: now },
    ], now)
    expect(saved).toHaveLength(1)
    expect(loadDiagnosticLogs(storage, now)).toEqual(saved)

    const malformed = createMemoryStorage('{broken')
    expect(loadDiagnosticLogs(malformed, now)).toEqual([])
  })

  it('serializes Error details, BigInt and circular values for diagnostics', () => {
    const error = new Error('cloud sync failed')
    const circular: Record<string, unknown> = { error, orderId: 10n }
    circular.self = circular

    const serialized = serializeDiagnosticLogArgument(circular)
    expect(serialized).toContain('cloud sync failed')
    expect(serialized).toContain('"stack"')
    expect(serialized).toContain('10n')
    expect(serialized).toContain('[Circular]')
  })
})
