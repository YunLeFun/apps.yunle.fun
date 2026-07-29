import { describe, expect, it } from 'vitest'
import {
  MAX_DIAGNOSTIC_UPLOAD_RANGE_MS,
  normalizeDiagnosticLogUploadDetail,
  normalizeDiagnosticLogUploadSummary,
  validateDiagnosticLogAdminQuery,
  validateDiagnosticLogUpload,
} from '../../server/utils/diagnostic-logs'

const now = Date.UTC(2026, 6, 29, 8)

function validBody() {
  return {
    startTime: now - 60_000,
    endTime: now,
    issueDescription: '点击 https://api.yunle.fun/private?token=secret 后失败',
    logs: [
      {
        level: 'error',
        message: 'sync failed Bearer abc.def user@example.com',
        timestamp: now - 1000,
      },
    ],
    client: {
      appVersion: '1.0.0',
      buildNumber: '100',
      platform: 'ios',
      route: '/feedback',
      timezone: 'Asia/Shanghai',
      userAgent: 'Mobile/15',
    },
  }
}

describe('diagnostic log upload validation', () => {
  it('normalizes and redacts a valid upload again on the server', () => {
    const result = validateDiagnosticLogUpload(validBody(), now)
    expect(result.logs).toHaveLength(1)
    expect(result.logs[0].message).toContain('Bearer [redacted]')
    expect(result.logs[0].message).toContain('[redacted-email]')
    expect(result.issueDescription).toContain('[redacted-url:api.yunle.fun]')
    expect(result.issueDescription).not.toContain('secret')
    expect(result.sizeBytes).toBeGreaterThan(0)
  })

  it('rejects invalid ranges and out-of-range log timestamps', () => {
    expect(() => validateDiagnosticLogUpload({
      ...validBody(),
      startTime: now - MAX_DIAGNOSTIC_UPLOAD_RANGE_MS - 1,
    }, now)).toThrow(/24 小时/)

    expect(() => validateDiagnosticLogUpload({
      ...validBody(),
      logs: [{ level: 'error', message: 'late', timestamp: now + 1 }],
    }, now)).toThrow(/超出所选时间范围/)
  })

  it('rejects oversized diagnostic bundles', () => {
    const body = validBody()
    body.logs = Array.from({ length: 200 }, (_, index) => ({
      level: 'error',
      message: `${index}-${'x'.repeat(2000)}`,
      timestamp: now - index,
    }))
    expect(() => validateDiagnosticLogUpload(body, now)).toThrow(/256 KB/)
  })

  it('requires at least one structurally valid log entry', () => {
    expect(() => validateDiagnosticLogUpload({ ...validBody(), logs: [] }, now))
      .toThrow(/没有可上传的日志/)
    expect(() => validateDiagnosticLogUpload({
      ...validBody(),
      logs: [{ level: 'verbose', message: 'x', timestamp: now }],
    }, now)).toThrow(/格式错误/)
  })
})

describe('diagnostic admin query and record projection', () => {
  const storedUpload = {
    _id: 'upload-1',
    schemaVersion: 1,
    supportCode: 'ABCDEF123456',
    ownerUid: 'uid-1',
    issueDescription: 'failed token=secret',
    startTime: now - 60_000,
    endTime: now,
    logCount: 1,
    sizeBytes: 120,
    logs: [{
      level: 'error',
      message: 'Bearer secret user@example.com',
      timestamp: now - 1000,
    }],
    client: {
      appVersion: '1.0.0',
      buildNumber: '1',
      platform: 'ios',
      route: '/feedback',
      timezone: 'Asia/Shanghai',
      userAgent: 'Mobile',
    },
    status: 'new',
    createdAt: now,
    updatedAt: now,
    expiresAt: now + 1000,
    internalSecret: 'must-not-leak',
  }

  it('requires uid or supportCode and caps the result count', () => {
    expect(validateDiagnosticLogAdminQuery({ uid: 'uid-1', limit: '10' }))
      .toEqual({ uid: 'uid-1', supportCode: '', limit: 10 })
    expect(validateDiagnosticLogAdminQuery({ supportCode: 'abcdef123456' }))
      .toEqual({ uid: '', supportCode: 'ABCDEF123456', limit: 20 })
    expect(() => validateDiagnosticLogAdminQuery({})).toThrow(/uid 或 supportCode/)
    expect(() => validateDiagnosticLogAdminQuery({ uid: 'uid-1', limit: '51' }))
      .toThrow(/最多查询/)
  })

  it('returns an allowlisted summary and redacts a full detail again', () => {
    const summary = normalizeDiagnosticLogUploadSummary(storedUpload)
    expect(summary).not.toHaveProperty('logs')
    expect(summary).not.toHaveProperty('internalSecret')
    expect(summary?.issueDescription).toContain('token=[redacted]')

    const detail = normalizeDiagnosticLogUploadDetail(storedUpload)
    expect(detail?.logs).toHaveLength(1)
    expect(detail?.logs[0]?.message).toContain('Bearer [redacted]')
    expect(detail?.logs[0]?.message).toContain('[redacted-email]')
  })
})
