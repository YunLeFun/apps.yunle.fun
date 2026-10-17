import type { HomeSchemaVersion, HomeScreenDocument, RemoteHomeScreen } from '../domain/home-screen'
import type { CloudbaseAdminDb, CloudbaseTransaction } from './cloudbase-admin'
import { createError } from 'h3'
import { homeDocumentId, latestHome, planHomeWrite, readHomeDocument, remoteHome, validateHomeWrite } from '../domain/home-screen'
import { useCloudbaseAdmin } from './cloudbase-admin'

const COLLECTION = 'user_home_screens'
// CloudBase transactions allow at most 100 operations; reserve writes/headroom.
const MAX_DOCUMENTS = 90

async function ownerDocuments(uid: string, db: CloudbaseAdminDb): Promise<HomeScreenDocument[]> {
  const response: { data?: unknown, code?: string | number } = await db.collection(COLLECTION)
    .where({ _openid: uid })
    .limit(MAX_DOCUMENTS)
    .get()
  if (response.code || !Array.isArray(response.data))
    throw createError({ statusCode: 503, message: '暂时无法读取云居' })
  if (response.data.length >= MAX_DOCUMENTS)
    throw createError({ statusCode: 409, message: '云居历史记录需要检查', data: { code: 'HOME_HISTORY_LIMIT' } })
  return response.data.map(record => readHomeDocument(record, uid))
}

export async function getHomeScreen(uid: string, db: CloudbaseAdminDb = useCloudbaseAdmin().db, schemaVersion: HomeSchemaVersion = 1): Promise<RemoteHomeScreen> {
  return remoteHome(latestHome(await ownerDocuments(uid, db)), schemaVersion)
}

export async function putHomeScreen(uid: string, input: unknown, db: CloudbaseAdminDb = useCloudbaseAdmin().db): Promise<RemoteHomeScreen> {
  const write = validateHomeWrite(input)
  const known = await ownerDocuments(uid, db)
  const ids = [...new Set([...known.map(record => record._id), homeDocumentId(uid)])]
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const records: HomeScreenDocument[] = []
    for (const id of ids) {
      const response: { data?: unknown, code?: string | number } = await transaction.collection(COLLECTION).doc(id).get()
      if (response.code)
        throw createError({ statusCode: 503, message: '暂时无法读取云居' })
      const data = Array.isArray(response.data) ? response.data : response.data ? [response.data] : []
      for (const record of data)
        records.push(readHomeDocument(record, uid))
    }
    const planned = planHomeWrite(uid, records, write, Date.now())
    if (planned.document) {
      const { _id, ...payload } = planned.document
      const result: { code?: string | number, updated?: number, upserted?: unknown[] } = await transaction.collection(COLLECTION).doc(_id).set(payload)
      if (result.code || (result.updated !== 1 && !result.upserted?.length))
        throw createError({ statusCode: 503, message: '暂时无法保存云居' })
    }
    return planned.response
  }) as Promise<RemoteHomeScreen>
}
