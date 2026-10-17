import { describe, expect, it } from 'vitest'
import { emptyHome, planHomeWrite, readHomeDocument, remoteHome, requestedHomeSchema, validateHomeWrite } from '../../server/domain/home-screen'

const uid = 'source-sync-test-owner'
const mutationId = '00000000-0000-4000-8000-000000000001'
const configuration = {
  installedApps: [{ appId: 'cook' }],
  dockApps: [],
  recentApps: [],
  folders: [],
  applicationSources: [{ appId: 'cook', ownerLogin: 'YunYouJun' }],
}
function stored(extra: Record<string, unknown> = {}) {
  return readHomeDocument({ _id: 'doc', _openid: uid, ...configuration, updatedAt: 100, createdAt: 1, ...extra }, uid)
}
function write(configuration: unknown, baseRevision: string | null = null, schemaVersion = 3) {
  return validateHomeWrite({ schemaVersion, baseRevision, mutationId, configuration })
}

describe('home application sources (schema 3)', () => {
  it('returns explicit selections to another schema 3 client without adding launch permissions', () => {
    expect(requestedHomeSchema('3')).toBe(3)
    expect(requestedHomeSchema(3)).toBe(3)
    expect(emptyHome(3).configuration).toEqual({ installedApps: [], dockApps: [], recentApps: [], folders: [], applicationSources: [], updatedAt: 0 })
    const saved = planHomeWrite(uid, [], write(configuration), 200)
    const reread = readHomeDocument(saved.document, uid)
    expect(remoteHome(reread, 3).configuration.applicationSources).toEqual(configuration.applicationSources)
    expect(remoteHome(reread, 2).configuration).not.toHaveProperty('applicationSources')
    expect(remoteHome(reread, 1).configuration).not.toHaveProperty('applicationSources')
    expect(saved.document?._openid).toBe(uid)
    expect(() => readHomeDocument(saved.document, 'other-user')).toThrow()
  })

  it('preserves selections across schema 1 and 2 writes, pruning only unreferenced apps', () => {
    const current = stored()
    for (const schema of [1, 2]) {
      const retained = planHomeWrite(uid, [current], write({ ...configuration, applicationSources: [] }, remoteHome(current).revision, schema), 200)
      expect(retained.document?.applicationSources).toEqual(configuration.applicationSources)
      const removed = planHomeWrite(uid, [current], write({ ...configuration, installedApps: [] }, remoteHome(current).revision, schema), 200)
      expect(removed.document?.applicationSources).toEqual([])
      const recentOnly = planHomeWrite(uid, [current], write({ ...configuration, installedApps: [], recentApps: [{ appId: 'cook', usedAt: 1 }] }, remoteHome(current).revision, schema), 200)
      expect(recentOnly.document?.applicationSources).toEqual(configuration.applicationSources)
    }
  })

  it('lets an explicit market selection clear the author source and retry a lost acknowledgement', () => {
    const current = stored()
    const request = write({ ...configuration, applicationSources: [] }, remoteHome(current).revision)
    const saved = planHomeWrite(uid, [current], request, 200)
    expect(saved.document?.applicationSources).toEqual([])
    const retry = planHomeWrite(uid, [saved.document!], request, 300)
    expect(retry.document).toBeUndefined()
    expect(retry.response).toEqual(saved.response)
    const changedPayload = { ...request, configuration }
    expect(() => planHomeWrite(uid, [saved.document!], changedPayload, 300)).toThrow(expect.objectContaining({ data: { code: 'HOME_MUTATION_REUSED' } }))
  })

  it('includes source-only changes in every schema revision and stale-writer conflict', () => {
    const before = stored({ applicationSources: [] })
    const after = stored()
    expect(remoteHome(after, 1).revision).toBe(remoteHome(after, 3).revision)
    expect(remoteHome(before, 2).revision).not.toBe(remoteHome(after, 2).revision)
    for (const schema of [1, 2, 3]) {
      expect(() => planHomeWrite(uid, [after], write(configuration, remoteHome(before).revision, schema), 200))
        .toThrow(expect.objectContaining({ data: { code: 'HOME_CONFLICT', current: remoteHome(after, schema as 1 | 2 | 3) } }))
    }
  })

  it('rejects malformed, ambiguous and dangling selections instead of silently switching versions', () => {
    for (const applicationSources of [
      undefined,
      null,
      {},
      [{ appId: 'cook', ownerLogin: '../other' }],
      [{ appId: 'cook', ownerLogin: '.' }],
      [{ appId: 'cook', ownerLogin: '..' }],
      [{ appId: 'cook', ownerLogin: ' owner' }],
      [{ appId: 'cook', ownerLogin: 'owner\n' }],
      [{ appId: 'cook', ownerLogin: 'a'.repeat(65) }],
      [{ appId: 'missing', ownerLogin: 'owner' }],
      [{ appId: 'cook', ownerLogin: 'one' }, { appId: 'cook', ownerLogin: 'two' }],
      [{ appId: 'cook', ownerLogin: 'owner', launchURL: 'https://untrusted.invalid' }],
    ]) {
      expect(() => write({ ...configuration, applicationSources })).toThrow(expect.objectContaining({ statusCode: 400 }))
    }
    expect(() => stored({ applicationSources: [{ appId: 'cook', ownerLogin: false }] })).toThrow(expect.objectContaining({ statusCode: 409 }))
    expect(() => stored({ applicationSources: null })).toThrow(expect.objectContaining({ statusCode: 409 }))
    expect(stored({ installedApps: [] }).applicationSources).toEqual([])
  })

  it('canonicalizes selection order for idempotency without changing existing revisions', () => {
    const plain = stored({ applicationSources: [] })
    const legacy = stored({ applicationSources: undefined })
    expect(remoteHome(plain).revision).toBe(remoteHome(legacy).revision)
    const content = { ...configuration, installedApps: [{ appId: 'a' }, { appId: 'b' }], applicationSources: [{ appId: 'b', ownerLogin: 'two' }, { appId: 'a', ownerLogin: 'one' }] }
    const first = planHomeWrite(uid, [], write(content), 200)
    const retry = planHomeWrite(uid, [first.document!], write({ ...content, applicationSources: [...content.applicationSources].reverse() }), 300)
    expect(retry.document).toBeUndefined()
    expect(retry.response).toEqual(first.response)
  })
})
