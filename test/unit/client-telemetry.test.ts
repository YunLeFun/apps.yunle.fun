import { createHash } from 'node:crypto'
import consola from 'consola'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  anonymizeTelemetryIdentifier,
  reportClientEvent,
} from '../../app/utils/client-telemetry'

describe('client telemetry', () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('redacts resource URLs and bearer tokens before reporting', () => {
    const report = vi.fn()
    const reportEvent = vi.fn()
    vi.spyOn(consola, 'warn').mockImplementation(() => {})
    vi.stubGlobal('window', {
      location: { pathname: '/user/profile' },
      $rum: { report, reportEvent },
    })

    reportClientEvent('ui.avatar.load_failed', {
      error: 'GET https://example.com/private/user.jpg?sign=secret with Bearer abc.def failed',
      host: 'example.com',
      stage: 'load',
      surface: 'user.profile',
    })

    const message = String(report.mock.calls[0]?.[0]?.msg)
    expect(message).toContain('[redacted-url]')
    expect(message).toContain('Bearer [redacted]')
    expect(message).not.toContain('/private/user.jpg')
    expect(message).not.toContain('abc.def')
  })

  it('redacts sensitive fields by key even when their values do not look like tokens', () => {
    const report = vi.fn()
    vi.spyOn(consola, 'warn').mockImplementation(() => {})
    vi.stubGlobal('window', {
      location: { pathname: '/login' },
      $rum: { report, reportEvent: vi.fn() },
    })

    reportClientEvent('auth.native_sso.failed', {
      accessToken: 'camel-access-token',
      authorizationCode: 'camel-authorization-code',
      code: 'plain-looking-code',
      codeVerifier: 'camel-code-verifier',
      nonce: 'plain-looking-nonce',
      pkce: 'plain-looking-pkce',
      refresh_token: 'plain-looking-refresh-token',
      requestId: 'request-safe-to-correlate',
      surface: 'native_sso',
    })

    const message = String(report.mock.calls[0]?.[0]?.msg)
    expect(message).toContain('request-safe-to-correlate')
    expect(message).not.toContain('plain-looking-code')
    expect(message).not.toContain('plain-looking-nonce')
    expect(message).not.toContain('plain-looking-refresh-token')
    expect(message).not.toContain('camel-access-token')
    expect(message).not.toContain('camel-authorization-code')
    expect(message).not.toContain('camel-code-verifier')
    expect(message).not.toContain('plain-looking-pkce')
    expect(message.match(/\[redacted\]/g)).toHaveLength(7)
  })

  it('uses the same truncated SHA-256 flow identifier as server audit logs', async () => {
    const nonce = 'nonce_'.padEnd(43, 'n')
    await expect(anonymizeTelemetryIdentifier(nonce)).resolves.toBe(
      createHash('sha256').update(nonce).digest('hex').slice(0, 16),
    )
  })
})
