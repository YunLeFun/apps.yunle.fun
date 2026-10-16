import { createHash } from 'node:crypto'
import { createError } from 'h3'

export interface HomeAppReference { appId: string }
export interface HomeRecentReference extends HomeAppReference { usedAt: number }
export interface HomeContent {
  installedApps: HomeAppReference[]
  dockApps: HomeAppReference[]
  recentApps: HomeRecentReference[]
}
export interface HomeConfiguration extends HomeContent { updatedAt: number }
export interface HomeScreenDocument extends HomeConfiguration {
  _id: string
  _openid: string
  createdAt: number
  lastMutationId?: string
  lastMutationHash?: string
}
export interface RemoteHomeScreen {
  schemaVersion: 1
  revision: string | null
  configuration: HomeConfiguration
}
export interface HomeWrite {
  baseRevision: string | null
  mutationId: string
  configuration: HomeContent
}

export function emptyHome(): RemoteHomeScreen {
  return { schemaVersion: 1, revision: null, configuration: { installedApps: [], dockApps: [], recentApps: [], updatedAt: 0 } }
}

export function validateHomeWrite(input: unknown): HomeWrite {
  if (!isRecord(input)
    || !(input.baseRevision === null || (typeof input.baseRevision === 'string' && /^[a-f0-9]{64}$/.test(input.baseRevision)))
    || typeof input.mutationId !== 'string'
    || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(input.mutationId)) {
    throw invalidInput()
  }
  return {
    baseRevision: input.baseRevision,
    mutationId: input.mutationId.toLowerCase(),
    configuration: homeContent(input.configuration),
  }
}

export function readHomeDocument(input: unknown, uid: string): HomeScreenDocument {
  try {
    if (!isRecord(input) || input._openid !== uid || typeof input._id !== 'string' || !input._id)
      throw new Error('Invalid owner or document')
    // Missing arrays are supported for the earliest schema; malformed arrays
    // are an explicit failure, never an empty replacement for private data.
    const content = homeContent({
      installedApps: input.installedApps ?? [],
      dockApps: input.dockApps ?? [],
      recentApps: input.recentApps ?? [],
    })
    const updatedAt = timestamp(input.updatedAt ?? 0)
    const createdAt = timestamp(input.createdAt ?? 0)
    return {
      _id: input._id,
      _openid: uid,
      ...content,
      updatedAt,
      createdAt,
      ...(typeof input.lastMutationId === 'string' ? { lastMutationId: input.lastMutationId } : {}),
      ...(typeof input.lastMutationHash === 'string' ? { lastMutationHash: input.lastMutationHash } : {}),
    }
  }
  catch {
    throw createError({ statusCode: 409, message: '云居数据需要检查，原记录已保留', data: { code: 'HOME_DATA_INVALID' } })
  }
}

export function latestHome(records: HomeScreenDocument[]): HomeScreenDocument | undefined {
  return [...records].sort((a, b) => b.updatedAt - a.updatedAt || a._id.localeCompare(b._id))[0]
}

export function remoteHome(document?: HomeScreenDocument): RemoteHomeScreen {
  if (!document)
    return emptyHome()
  const configuration = {
    installedApps: document.installedApps,
    dockApps: document.dockApps,
    recentApps: document.recentApps,
    updatedAt: document.updatedAt,
  }
  return { schemaVersion: 1, revision: hash({ id: document._id, configuration }), configuration }
}

export function homeDocumentId(uid: string): string {
  return `native-home-${hash(uid)}`
}

/** Called only after all known owner documents have been re-read in a transaction. */
export function planHomeWrite(uid: string, records: HomeScreenDocument[], write: HomeWrite, now: number): {
  document?: HomeScreenDocument
  response: RemoteHomeScreen
} {
  const current = latestHome(records)
  const remote = remoteHome(current)
  const payloadHash = contentHash(write.configuration)
  if (current?.lastMutationId === write.mutationId
    && current.lastMutationHash === payloadHash
    && contentHash(current) === payloadHash) {
    return { response: remote }
  }
  if (current?.lastMutationId === write.mutationId && current.lastMutationHash !== payloadHash) {
    throw createError({ statusCode: 409, message: '同步请求标识已使用，请重试', data: { code: 'HOME_MUTATION_REUSED' } })
  }
  if (remote.revision !== write.baseRevision) {
    throw createError({
      statusCode: 409,
      message: '另一台设备更新了云居，请选择要保留的版本',
      data: { code: 'HOME_CONFLICT', current: remote },
    })
  }
  const document: HomeScreenDocument = {
    _id: homeDocumentId(uid),
    _openid: uid,
    ...write.configuration,
    createdAt: current?.createdAt || now,
    // Server time drives legacy LWW readers; client clocks cannot force a win.
    updatedAt: Math.max(now, (current?.updatedAt ?? 0) + 1),
    lastMutationId: write.mutationId,
    lastMutationHash: payloadHash,
  }
  if (!Number.isSafeInteger(document.updatedAt))
    throw createError({ statusCode: 409, message: '云居时间记录需要检查', data: { code: 'HOME_DATA_INVALID' } })
  return { document, response: remoteHome(document) }
}

function homeContent(input: unknown): HomeContent {
  if (!isRecord(input))
    throw invalidInput()
  return {
    installedApps: references(input.installedApps, 1000, false),
    dockApps: references(input.dockApps, 4, false),
    recentApps: references(input.recentApps, 100, true),
  }
}

function references(input: unknown, limit: number, recent: true): HomeRecentReference[]
function references(input: unknown, limit: number, recent: false): HomeAppReference[]
function references(input: unknown, limit: number, recent: boolean): HomeAppReference[] {
  if (!Array.isArray(input) || input.length > limit)
    throw invalidInput()
  const seen = new Set<string>()
  return input.map((entry) => {
    if (!isRecord(entry) || typeof entry.appId !== 'string' || !entry.appId
      || entry.appId !== entry.appId.trim() || entry.appId.length > 256
      || [...entry.appId].some(char => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127) || seen.has(entry.appId)) {
      throw invalidInput()
    }
    seen.add(entry.appId)
    return recent ? { appId: entry.appId, usedAt: timestamp(entry.usedAt) } : { appId: entry.appId }
  })
}

function timestamp(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0)
    throw invalidInput()
  return value
}
function contentHash(content: HomeContent): string {
  return hash({ installedApps: content.installedApps, dockApps: content.dockApps, recentApps: content.recentApps })
}
function hash(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex')
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
function invalidInput() {
  return createError({ statusCode: 400, message: '云居同步参数不正确', data: { code: 'HOME_INPUT_INVALID' } })
}
