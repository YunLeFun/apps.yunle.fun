import type { CloudbaseAdminDb } from '../../server/utils/cloudbase-admin'
import { describe, expect, it, vi } from 'vitest'
import {
  isDiagnosticAdminUid,
  parseDiagnosticAdminUids,
} from '../../server/utils/diagnostic-admin'
import {
  getActiveDiagnosticLogUpload,
  listActiveDiagnosticLogUploads,
} from '../../server/utils/diagnostic-log-admin-service'

const now = Date.UTC(2026, 6, 29, 8)

function storedUpload(overrides: Record<string, unknown> = {}) {
  return {
    _id: 'upload-1',
    schemaVersion: 1,
    supportCode: 'ABCDEF123456',
    ownerUid: 'uid-1',
    issueDescription: 'cloud sync failed',
    startTime: now - 60_000,
    endTime: now,
    logCount: 1,
    sizeBytes: 120,
    logs: [{ level: 'error', message: 'failed', timestamp: now - 1000 }],
    client: {},
    status: 'new',
    createdAt: now,
    updatedAt: now,
    expiresAt: now + 1000,
    ...overrides,
  }
}

function createDiagnosticDb(records: unknown[]) {
  const query = {
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    get: vi.fn().mockResolvedValue({ data: records }),
  }
  const collection = {
    where: vi.fn(() => query),
    doc: vi.fn(() => ({
      get: vi.fn().mockResolvedValue({ data: records }),
    })),
  }
  const db = {
    collection: vi.fn(() => collection),
  } as unknown as CloudbaseAdminDb
  return { collection, db, query }
}

describe('diagnostic admin allowlist', () => {
  it('parses comma-separated UIDs without accepting partial matches', () => {
    expect([...parseDiagnosticAdminUids(' uid-1,uid-2, uid-1 ')])
      .toEqual(['uid-1', 'uid-2'])
    expect(isDiagnosticAdminUid('uid-1', 'uid-1,uid-2')).toBe(true)
    expect(isDiagnosticAdminUid('uid', 'uid-1,uid-2')).toBe(false)
  })

  it('denies access when the server allowlist is absent', () => {
    expect(isDiagnosticAdminUid('uid-1', undefined)).toBe(false)
    expect(isDiagnosticAdminUid('', 'uid-1')).toBe(false)
  })
})

describe('diagnostic admin data service', () => {
  it('lists only active summaries for the requested UID', async () => {
    const { collection, db, query } = createDiagnosticDb([
      storedUpload(),
      storedUpload({
        _id: 'expired-upload',
        supportCode: 'EXPIRED123456',
        createdAt: now - 1000,
        expiresAt: now,
      }),
    ])

    const uploads = await listActiveDiagnosticLogUploads(db, {
      uid: 'uid-1',
      supportCode: '',
      limit: 20,
    }, now)

    expect(collection.where).toHaveBeenCalledWith({ ownerUid: 'uid-1' })
    expect(query.orderBy).toHaveBeenCalledWith('createdAt', 'desc')
    expect(uploads).toHaveLength(1)
    expect(uploads[0]).not.toHaveProperty('logs')
  })

  it('uses the supportCode index and applies an optional UID check in memory', async () => {
    const { collection, db, query } = createDiagnosticDb([
      storedUpload({ ownerUid: 'uid-2' }),
    ])
    const uploads = await listActiveDiagnosticLogUploads(db, {
      uid: 'uid-1',
      supportCode: 'ABCDEF123456',
      limit: 20,
    }, now)

    expect(collection.where).toHaveBeenCalledWith({ supportCode: 'ABCDEF123456' })
    expect(query.orderBy).not.toHaveBeenCalled()
    expect(uploads).toEqual([])
  })

  it('returns full logs by upload ID and hides expired records', async () => {
    const active = createDiagnosticDb([storedUpload()])
    await expect(
      getActiveDiagnosticLogUpload(active.db, 'upload-1', now),
    )
      .resolves
      .toMatchObject({
        _id: 'upload-1',
        logs: [{ level: 'error', message: 'failed', timestamp: now - 1000 }],
      })
    expect(active.collection.doc).toHaveBeenCalledWith('upload-1')

    const expired = createDiagnosticDb([storedUpload({ expiresAt: now })])
    await expect(
      getActiveDiagnosticLogUpload(expired.db, 'upload-1', now),
    )
      .resolves
      .toBeNull()
  })
})
