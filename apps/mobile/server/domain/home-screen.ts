import { createHash } from 'node:crypto'
import { createError } from 'h3'

export interface HomeAppReference { appId: string }
export interface HomeRecentReference extends HomeAppReference { usedAt: number }
/**
 * A Home Screen folder (schema 2). Members stay in `installedApps`; the folder
 * sits where its first member is. Clients that predate folders therefore keep
 * showing every app, just not grouped.
 */
export interface HomeFolder { id: string, name: string, appIds: string[] }
export interface HomeContent {
  installedApps: HomeAppReference[]
  dockApps: HomeAppReference[]
  recentApps: HomeRecentReference[]
  /** Present for schema 2. Schema 1 writes omit it and keep the stored folders. */
  folders?: HomeFolder[]
}
export interface HomeConfiguration extends HomeContent { updatedAt: number }
export interface HomeScreenDocument extends HomeConfiguration {
  _id: string
  _openid: string
  createdAt: number
  folders: HomeFolder[]
  lastMutationId?: string
  lastMutationHash?: string
}
/** 1: apps, dock and recents. 2: adds `configuration.folders`. */
export type HomeSchemaVersion = 1 | 2
export interface RemoteHomeScreen {
  schemaVersion: HomeSchemaVersion
  revision: string | null
  configuration: HomeConfiguration
}
export interface HomeWrite {
  schemaVersion: HomeSchemaVersion
  baseRevision: string | null
  mutationId: string
  configuration: HomeContent
}

export const HOME_FOLDER_LIMIT = 200
export const HOME_FOLDER_NAME_LIMIT = 40

/** Reads understand schema 2 only when asked (`?schema=2`); everyone else gets schema 1. */
export function requestedHomeSchema(value: unknown): HomeSchemaVersion {
  return value === '2' || value === 2 ? 2 : 1
}

export function emptyHome(schemaVersion: HomeSchemaVersion = 1): RemoteHomeScreen {
  const configuration: HomeConfiguration = { installedApps: [], dockApps: [], recentApps: [], updatedAt: 0 }
  return { schemaVersion, revision: null, configuration: schemaVersion === 2 ? { ...configuration, folders: [] } : configuration }
}

export function validateHomeWrite(input: unknown): HomeWrite {
  if (!isRecord(input) || !(input.schemaVersion === undefined || input.schemaVersion === 1 || input.schemaVersion === 2))
    throw invalidInput()
  const schemaVersion: HomeSchemaVersion = input.schemaVersion === 2 ? 2 : 1
  if (!isRecord(input)
    || !(input.baseRevision === null || (typeof input.baseRevision === 'string' && /^[a-f0-9]{64}$/.test(input.baseRevision)))
    || typeof input.mutationId !== 'string'
    || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(input.mutationId)) {
    throw invalidInput()
  }
  const content = homeContent(input.configuration)
  if (schemaVersion === 2) {
    if (!isRecord(input.configuration))
      throw invalidInput()
    content.folders = folders(input.configuration.folders, content.installedApps, true)
  }
  return {
    schemaVersion,
    baseRevision: input.baseRevision,
    mutationId: input.mutationId.toLowerCase(),
    configuration: content,
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
    // Clients without folder support may have removed members since; their
    // references are dropped here, never the folder data that is still valid.
    const storedFolders = folders(input.folders ?? [], content.installedApps, false)
    const updatedAt = timestamp(input.updatedAt ?? 0)
    const createdAt = timestamp(input.createdAt ?? 0)
    return {
      _id: input._id,
      _openid: uid,
      ...content,
      folders: storedFolders,
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

export function remoteHome(document?: HomeScreenDocument, schemaVersion: HomeSchemaVersion = 1): RemoteHomeScreen {
  if (!document)
    return emptyHome(schemaVersion)
  const configuration: HomeConfiguration = {
    installedApps: document.installedApps,
    dockApps: document.dockApps,
    recentApps: document.recentApps,
    updatedAt: document.updatedAt,
  }
  // One revision for every schema, so a folder change made by a schema 2
  // client is still a conflict for a schema 1 writer. Documents without
  // folders keep the exact revision they had before folders existed.
  const folders = document.folders ?? []
  const revision = hash({ id: document._id, configuration: folders.length ? { ...configuration, folders } : configuration })
  return {
    schemaVersion,
    revision,
    configuration: schemaVersion === 2 ? { ...configuration, folders } : configuration,
  }
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
  const remote = remoteHome(current, write.schemaVersion)
  const withFolders = write.schemaVersion === 2
  const payloadHash = contentHash(write.configuration, withFolders)
  if (current?.lastMutationId === write.mutationId
    && current.lastMutationHash === payloadHash
    && contentHash(current, withFolders) === payloadHash) {
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
  // Schema 1 writers don't know folders: keep the stored ones, minus members
  // that writer removed from the Home Screen.
  const nextFolders = withFolders
    ? write.configuration.folders ?? []
    : folders(current?.folders ?? [], write.configuration.installedApps, false)
  const document: HomeScreenDocument = {
    _id: homeDocumentId(uid),
    _openid: uid,
    installedApps: write.configuration.installedApps,
    dockApps: write.configuration.dockApps,
    recentApps: write.configuration.recentApps,
    folders: nextFolders,
    createdAt: current?.createdAt || now,
    // Server time drives legacy LWW readers; client clocks cannot force a win.
    updatedAt: Math.max(now, (current?.updatedAt ?? 0) + 1),
    lastMutationId: write.mutationId,
    lastMutationHash: payloadHash,
  }
  if (!Number.isSafeInteger(document.updatedAt))
    throw createError({ statusCode: 409, message: '云居时间记录需要检查', data: { code: 'HOME_DATA_INVALID' } })
  return { document, response: remoteHome(document, write.schemaVersion) }
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

/**
 * `strict` (schema 2 writes): any malformed or dangling entry is rejected.
 * Lenient (stored data): structure must still be valid, but members that are
 * no longer installed or already in an earlier folder are dropped, and
 * folders left empty disappear.
 */
function folders(input: unknown, installed: HomeAppReference[], strict: boolean): HomeFolder[] {
  if (!Array.isArray(input) || input.length > HOME_FOLDER_LIMIT)
    throw invalidInput()
  const installedIds = new Set(installed.map(app => app.appId))
  const folderIds = new Set<string>()
  const members = new Set<string>()
  const result: HomeFolder[] = []
  for (const entry of input) {
    if (!isRecord(entry) || typeof entry.id !== 'string' || !/^[\w-]{1,64}$/.test(entry.id) || folderIds.has(entry.id)
      || typeof entry.name !== 'string' || !validName(entry.name) || !Array.isArray(entry.appIds)) {
      throw invalidInput()
    }
    folderIds.add(entry.id)
    const appIds: string[] = []
    for (const appId of references(entry.appIds.map(id => ({ appId: id })), 1000, false).map(ref => ref.appId)) {
      if (!installedIds.has(appId) || members.has(appId)) {
        if (strict)
          throw invalidInput()
        continue
      }
      members.add(appId)
      appIds.push(appId)
    }
    if (appIds.length === 0) {
      if (strict)
        throw invalidInput()
      continue
    }
    result.push({ id: entry.id, name: entry.name, appIds })
  }
  return result
}

function validName(name: string): boolean {
  return name.length > 0 && name === name.trim() && [...name].length <= HOME_FOLDER_NAME_LIMIT
    && ![...name].some(char => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127)
}

function timestamp(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0)
    throw invalidInput()
  return value
}
function contentHash(content: HomeContent, withFolders: boolean): string {
  const base = { installedApps: content.installedApps, dockApps: content.dockApps, recentApps: content.recentApps }
  const stored = content.folders ?? []
  // Without folders the hash matches what schema 1 always produced, so
  // acknowledgements recorded before folders existed still retry cleanly.
  return hash(withFolders && stored.length ? { ...base, folders: stored } : base)
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
