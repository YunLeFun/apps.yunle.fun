import { describe, expect, it } from 'vitest'
import { emptyHome, homeDocumentId, latestHome, planHomeWrite, readHomeDocument, remoteHome, validateHomeWrite } from '../../server/domain/home-screen'

const uid = 'test-owner'
const mutationId = '00000000-0000-4000-8000-000000000001'
const configuration = {
  installedApps: [{ appId: 'legacy-cook' }, { appId: 'stable-record-id' }, { appId: 'temporarily-unavailable' }],
  dockApps: [{ appId: 'legacy-cook' }],
  recentApps: [{ appId: 'stable-record-id', usedAt: 123 }],
}
const original = readHomeDocument({ _id: 'legacy-document', _openid: uid, ...configuration, updatedAt: 100, createdAt: 1 }, uid)

describe('home screen protocol', () => {
  it('preserves legacy identifiers, order, dock and unresolved references', () => {
    const state = remoteHome(original)
    expect(state.configuration).toEqual({ ...configuration, updatedAt: 100 })
    expect(state.revision).toMatch(/^[a-f0-9]{64}$/)
    expect(state).not.toHaveProperty('_openid')
    expect(state).not.toHaveProperty('documentId')
  })

  it('uses a deterministic owner-specific document for simultaneous first writes', () => {
    const write = validateHomeWrite({ baseRevision: null, mutationId, configuration, _openid: 'victim' })
    const first = planHomeWrite(uid, [], write, 200)
    expect(first.document?._id).toBe(homeDocumentId(uid))
    expect(first.document?._openid).toBe(uid)
    expect(homeDocumentId('other-owner')).not.toBe(homeDocumentId(uid))
    expect(() => planHomeWrite(uid, [first.document!], { ...write, mutationId: '00000000-0000-4000-8000-000000000002' }, 201))
      .toThrow(expect.objectContaining({ statusCode: 409 }))
  })

  it('retries a lost acknowledgement idempotently without advancing time', () => {
    const write = validateHomeWrite({ baseRevision: remoteHome(original).revision, mutationId, configuration })
    const first = planHomeWrite(uid, [original], write, 200)
    const retry = planHomeWrite(uid, [original, first.document!], write, 300)
    expect(retry.document).toBeUndefined()
    expect(retry.response).toEqual(first.response)
  })

  it('rejects stale revisions and never treats legacy writes as a successful retry', () => {
    const write = validateHomeWrite({ baseRevision: remoteHome(original).revision, mutationId, configuration })
    const first = planHomeWrite(uid, [original], write, 200).document!
    const changed = { ...first, installedApps: [], updatedAt: 201 }
    expect(() => planHomeWrite(uid, [original, changed], write, 300))
      .toThrow(expect.objectContaining({ statusCode: 409, data: { code: 'HOME_CONFLICT', current: remoteHome(changed) } }))
    expect(() => planHomeWrite(uid, [original], { ...write, baseRevision: null }, 300)).toThrow()
  })

  it('selects the latest legacy document and protects malformed or foreign records', () => {
    const newer = { ...original, _id: 'newer-document', updatedAt: 101 }
    expect(latestHome([newer, original])).toBe(newer)
    expect(() => readHomeDocument({ ...original, _openid: 'another-owner' }, uid)).toThrow()
    expect(() => readHomeDocument({ ...original, installedApps: 'broken' }, uid)).toThrow()
    expect(emptyHome().revision).toBeNull()
  })

  it('validates bounds without granting visibility or silently discarding references', () => {
    for (const value of [
      { ...configuration, dockApps: Array.from({ length: 5 }, (_, i) => ({ appId: String(i) })) },
      { ...configuration, installedApps: [{ appId: 'duplicate' }, { appId: 'duplicate' }] },
      { ...configuration, installedApps: [{ appId: '' }] },
      { ...configuration, recentApps: [{ appId: 'a', usedAt: Number.NaN }] },
    ]) {
      expect(() => validateHomeWrite({ baseRevision: null, mutationId, configuration: value })).toThrow()
    }
    const written = planHomeWrite(uid, [original], validateHomeWrite({
      baseRevision: remoteHome(original).revision,
      mutationId,
      configuration: { ...configuration, updatedAt: 9999999999999 },
    }), 1)
    expect(written.document?.updatedAt).toBe(101)
  })
})
