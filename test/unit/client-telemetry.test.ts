import consola from 'consola'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { reportClientEvent } from '../../app/utils/client-telemetry'

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
})
