import { describe, expect, it } from 'vitest'
import { claimAppIdentifier, identifierKey, normalizeMarketShortName } from '../../server/domain/app-identifiers'

function registry() {
  const rows = new Map<string, Record<string, unknown>>()
  return {
    rows,
    collection: () => ({ doc: (key: string) => ({
      get: async () => ({ data: rows.has(key) ? [rows.get(key)] : [] }),
      set: async (value: Record<string, unknown>) => { rows.set(key, value) },
    }) }),
  }
}

describe('app identity ownership', () => {
  it('normalizes a market short name and rejects reserved or unsafe names', () => {
    expect(normalizeMarketShortName(' My-App ')).toBe('my-app')
    for (const name of ['admin', 'API', '../foo', '', 'a', '-app', '应用', 'a'.repeat(51)])
      expect(() => normalizeMarketShortName(name)).toThrow()
  })

  it('permits the same slug under different owners, but never reassigns an owner slug', async () => {
    const tx = registry()
    await claimAppIdentifier(tx, 'namespace', 'sponsors', 'app-a', 'alice')
    await claimAppIdentifier(tx, 'namespace', 'sponsors', 'app-b', 'bob')
    await expect(claimAppIdentifier(tx, 'namespace', 'sponsors', 'app-c', 'alice')).rejects.toMatchObject({ statusCode: 409 })
    expect(tx.rows.size).toBe(2)
  })

  it('is idempotent for an app and retains market ownership after delisting', async () => {
    const tx = registry()
    await claimAppIdentifier(tx, 'market', 'sponsors', 'app-a')
    await claimAppIdentifier(tx, 'market', 'SPONSORS', 'app-a')
    // Registry is independent of listing status; delisting cannot release this claim.
    await expect(claimAppIdentifier(tx, 'market', 'sponsors', 'app-b')).rejects.toMatchObject({ data: { code: 'MARKET_SHORT_NAME_TAKEN' } })
    expect(tx.rows.get(identifierKey('market', 'sponsors'))?.appId).toBe('app-a')
  })
})
