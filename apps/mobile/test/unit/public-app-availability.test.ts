import type { CloudbaseAdminDb } from '../../server/utils/cloudbase-admin'
import { describe, expect, it, vi } from 'vitest'
import { publicAppUnavailableReason } from '../../server/utils/public-app-availability'

function fixture(data: unknown) {
  const get = vi.fn(async () => ({ data }))
  const limit = vi.fn(() => ({ get }))
  const field = vi.fn(() => ({ limit }))
  const where = vi.fn(() => ({ field }))
  const or = vi.fn((queries: unknown[]) => ({ or: queries }))
  const collection = vi.fn(() => ({ where }))
  return { db: { collection, command: { or } } as unknown as CloudbaseAdminDb, or, where, field }
}

describe('public app unavailability reasons', () => {
  it.each([
    ['unlisted', 'not_listed'],
    ['delisted', 'delisted'],
    ['suspended', 'suspended'],
    ['listed', 'unavailable'],
    ['future-status', 'unavailable'],
  ])('reports approved public listing state %s without exposing operator notes', async (status, expected) => {
    const { db, field } = fixture([{ status, approvedRevisionId: 'approved', reason: 'private review notes' }])
    await expect(publicAppUnavailableReason('valaxy', db)).resolves.toBe(expected)
    expect(field).toHaveBeenCalledExactlyOnceWith({ appId: true, shortName: true, status: true, approvedRevisionId: true })
  })

  const hiddenRows = [
    [],
    undefined,
    [{}],
    [{ status: 'suspended' }],
    [{ status: 'unlisted', approvedRevisionId: '' }],
    [{ status: 'delisted', approvedRevisionId: 'one' }, { status: 'unlisted', approvedRevisionId: 'two' }],
  ]
  it.each(hiddenRows.map(rows => ({ rows })))(
    'does not reveal unapproved, missing, or ambiguous records: $rows',
    async ({ rows }) => {
      const { db } = fixture(rows)
      await expect(publicAppUnavailableReason('private-app', db)).resolves.toBe('unavailable')
    },
  )

  it('resolves a public short name or immutable app ID without looking up private slugs', async () => {
    const { db, or } = fixture([])
    await publicAppUnavailableReason('Public-Key', db)
    expect(or).toHaveBeenCalledExactlyOnceWith([{ appId: 'Public-Key' }, { shortName: 'public-key' }])
  })

  it('keeps database failure distinct from a confirmed unavailability reason', async () => {
    const { db } = fixture([])
    vi.spyOn(db, 'collection').mockImplementation(() => {
      throw new Error('database unavailable')
    })
    await expect(publicAppUnavailableReason('valaxy', db)).rejects.toThrow('database unavailable')
  })
})
