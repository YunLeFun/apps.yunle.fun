import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { planHomeWrite, readHomeDocument, remoteHome, requestedHomeSchema, validateHomeWrite } from '../../server/domain/home-screen'

const uid = 'test-owner'
const mutationId = '00000000-0000-4000-8000-000000000001'
const apps = { installedApps: [{ appId: 'a' }, { appId: 'b' }, { appId: 'c' }, { appId: 'd' }], dockApps: [{ appId: 'a' }], recentApps: [] }
const games = { id: 'games', name: '游戏', appIds: ['b', 'c'] }
function stored(folders: unknown[] = [games], extra: Record<string, unknown> = {}) {
  return readHomeDocument({ _id: 'doc', _openid: uid, ...apps, folders, updatedAt: 100, createdAt: 1, ...extra }, uid)
}
const sha = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex')

describe('home screen folders (schema 2)', () => {
  it('negotiates the schema: only an explicit request gets folders', () => {
    expect(requestedHomeSchema('2')).toBe(2)
    expect([requestedHomeSchema(undefined), requestedHomeSchema('1'), requestedHomeSchema('4')]).toEqual([1, 1, 1])
    expect(remoteHome(stored(), 1).configuration).not.toHaveProperty('folders')
    expect(remoteHome(stored(), 2)).toMatchObject({ schemaVersion: 2, configuration: { folders: [games] } })
  })

  it('shares one revision across schemas and keeps pre-folder revisions unchanged', () => {
    const plain = stored([])
    const configuration = { ...apps, updatedAt: 100 }
    // Exactly what schema 1 produced before folders existed: no spurious conflicts after deploy.
    expect(remoteHome(plain, 1).revision).toBe(sha({ id: 'doc', configuration }))
    expect(remoteHome(stored(), 1).revision).toBe(remoteHome(stored(), 2).revision)
    expect(remoteHome(stored(), 1).revision).not.toBe(remoteHome(plain, 1).revision)
  })

  it('keeps folders when a schema 1 client writes, minus members it removed', () => {
    const current = stored([games, { id: 'solo', name: '工具', appIds: ['d'] }])
    const write = validateHomeWrite({
      baseRevision: remoteHome(current).revision,
      mutationId,
      configuration: { ...apps, installedApps: [{ appId: 'a' }, { appId: 'c' }, { appId: 'b' }], folders: [] },
    })
    expect(write.configuration.folders).toBeUndefined()
    const planned = planHomeWrite(uid, [current], write, 200)
    expect(planned.document?.folders).toEqual([{ ...games, appIds: ['b', 'c'] }])
    expect(planned.response.schemaVersion).toBe(1)
    expect(remoteHome(planned.document!, 2).configuration.folders).toEqual([games])
  })

  it('replaces folders on a schema 2 write and retries it idempotently', () => {
    const current = stored([])
    const write = validateHomeWrite({
      schemaVersion: 2,
      baseRevision: remoteHome(current).revision,
      mutationId,
      configuration: { ...apps, folders: [{ id: 'new', name: '新文件夹', appIds: ['d', 'b'] }] },
    })
    const first = planHomeWrite(uid, [current], write, 200)
    expect(first.response).toMatchObject({ schemaVersion: 2, configuration: { folders: [{ id: 'new', appIds: ['d', 'b'] }] } })
    const retry = planHomeWrite(uid, [current, first.document!], write, 300)
    expect(retry.document).toBeUndefined()
    expect(retry.response).toEqual(first.response)
  })

  it('treats a folder-only change as a conflict for a stale schema 1 writer', () => {
    const before = stored([])
    const after = stored([games], { updatedAt: 100 })
    const write = validateHomeWrite({ baseRevision: remoteHome(before).revision, mutationId, configuration: apps })
    expect(() => planHomeWrite(uid, [after], write, 200)).toThrow(expect.objectContaining({ statusCode: 409 }))
  })

  it('rejects malformed schema 2 folders instead of silently fixing them', () => {
    const base = { schemaVersion: 2, baseRevision: null, mutationId }
    for (const folders of [
      undefined,
      [{ id: 'x', name: '游戏', appIds: ['missing'] }],
      [{ id: 'x', name: '游戏', appIds: [] }],
      [{ id: 'x', name: '游戏', appIds: ['b'] }, { id: 'y', name: '其他', appIds: ['b'] }],
      [{ id: 'x', name: '游戏', appIds: ['b'] }, { id: 'x', name: '其他', appIds: ['c'] }],
      [{ id: 'x', name: ' 空格', appIds: ['b'] }],
      [{ id: 'x', name: '名'.repeat(41), appIds: ['b'] }],
      [{ id: 'bad id!', name: '游戏', appIds: ['b'] }],
    ]) {
      expect(() => validateHomeWrite({ ...base, configuration: { ...apps, folders } })).toThrow()
    }
    expect(() => validateHomeWrite({ ...base, schemaVersion: 4, configuration: apps })).toThrow()
  })

  it('reads data edited by clients without folder support', () => {
    // The web client updates only the app arrays, so a member can go missing.
    const document = stored([{ id: 'g', name: '游戏', appIds: ['gone', 'c'] }, { id: 'e', name: '空', appIds: ['gone'] }])
    expect(document.folders).toEqual([{ id: 'g', name: '游戏', appIds: ['c'] }])
    expect(() => stored([{ id: 'g', name: 42, appIds: ['c'] }])).toThrow(expect.objectContaining({ statusCode: 409 }))
    expect(readHomeDocument({ _id: 'doc', _openid: uid, ...apps, updatedAt: 1 }, uid).folders).toEqual([])
  })
})
