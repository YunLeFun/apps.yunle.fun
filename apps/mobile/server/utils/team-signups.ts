import type { CloudbaseAdminDb, CloudbaseTransaction } from './cloudbase-admin'
import { createHash } from 'node:crypto'
import { createError } from 'h3'
import { useCloudbaseAdmin } from './cloudbase-admin'

const collection = 'conversation_team_signups'
const signupId = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const memberKey = /^[0-9a-f]{64}$/

interface Signup {
  title: string
  capacity: number
  owner: string
  members: string[]
  revision: number
}

function fields(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function validTitle(title: unknown): title is string {
  return typeof title === 'string' && title.trim() === title && title.length > 0
    && title.length <= 60 && !/[\r\n\t]/.test(title)
}

function validCapacity(capacity: unknown): capacity is number {
  return typeof capacity === 'number' && Number.isInteger(capacity) && capacity >= 2 && capacity <= 16
}

export function validateSignupId(id: string | undefined): string {
  if (!id || id.length !== 36 || !signupId.test(id))
    throw createError({ statusCode: 400, message: '无效的组队报名编号' })
  return id
}

function identityKey(uid: string, id: string): string {
  return createHash('sha256').update(JSON.stringify([uid, id])).digest('hex')
}

function readSignup(response: { data?: unknown, code?: unknown }): Signup | undefined {
  if (response.code)
    throw createError({ statusCode: 503, message: '暂时无法读取组队报名' })
  const value = Array.isArray(response.data) ? response.data[0] : response.data
  if (value == null)
    return undefined
  const { title, capacity, owner, members, revision } = fields(value)
  if (!validTitle(title) || !validCapacity(capacity) || typeof owner !== 'string' || !memberKey.test(owner)
    || !Array.isArray(members) || members.length > capacity || new Set(members).size !== members.length
    || !members.every(member => typeof member === 'string' && memberKey.test(member))
    || typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision < 1) {
    throw createError({ statusCode: 503, message: '组队报名数据暂时不可用' })
  }
  return { title, capacity, owner, members, revision }
}

function snapshot(id: string, signup: Signup, viewer: string) {
  return {
    schemaVersion: 1,
    signupId: id,
    title: signup.title,
    capacity: signup.capacity,
    memberCount: signup.members.length,
    joined: signup.members.includes(viewer),
    revision: signup.revision,
  }
}

function requireSignup(value: Signup | undefined): Signup {
  if (!value)
    throw createError({ statusCode: 404, message: '找不到这张组队报名卡' })
  return value
}

function verifyWrite(id: string, result: { code?: unknown, updated?: number, upserted?: unknown[] }) {
  if (result.code || (result.updated !== 1 && !result.upserted?.some(value => fields(value)._id === id)))
    throw createError({ statusCode: 503, message: '暂时无法保存组队报名' })
}

export async function getTeamSignup(id: string, uid: string, db = useCloudbaseAdmin().db) {
  const current = requireSignup(readSignup(await db.collection(collection).doc(id).get()))
  return snapshot(id, current, identityKey(uid, id))
}

export async function createTeamSignup(id: string, uid: string, input: unknown, db: CloudbaseAdminDb = useCloudbaseAdmin().db): Promise<ReturnType<typeof snapshot>> {
  const { title, capacity } = fields(input)
  if (!validTitle(title) || !validCapacity(capacity))
    throw createError({ statusCode: 400, message: '请填写标题和 2–16 人的队伍容量' })
  const owner = identityKey(uid, id)
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const doc = transaction.collection(collection).doc(id)
    const existing = readSignup(await doc.get())
    if (existing) {
      if (existing.owner !== owner || existing.title !== title || existing.capacity !== capacity)
        throw createError({ statusCode: 409, message: '这张报名卡的创建内容已变化', data: { code: 'SIGNUP_EXISTS' } })
      return snapshot(id, existing, owner)
    }
    const created: Signup = { title, capacity, owner, members: [], revision: 1 }
    verifyWrite(id, await doc.set(created))
    return snapshot(id, created, owner)
  })
}

export async function setTeamSignupParticipation(id: string, uid: string, input: unknown, db: CloudbaseAdminDb = useCloudbaseAdmin().db, expectedRevision?: number): Promise<ReturnType<typeof snapshot>> {
  const { joined } = fields(input)
  if (typeof joined !== 'boolean')
    throw createError({ statusCode: 400, message: '无效的报名状态' })
  const viewer = identityKey(uid, id)
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const doc = transaction.collection(collection).doc(id)
    const current = requireSignup(readSignup(await doc.get()))
    if (current.members.includes(viewer) === joined)
      return snapshot(id, current, viewer)
    if (expectedRevision !== undefined && expectedRevision !== current.revision)
      throw createError({ statusCode: 409, message: '报名状态已变化，请重试', data: { code: 'SIGNUP_CONFLICT' } })
    if (joined && current.members.length >= current.capacity)
      throw createError({ statusCode: 409, message: '报名已满', data: { code: 'SIGNUP_FULL' } })
    const members = joined ? [...current.members, viewer] : current.members.filter(member => member !== viewer)
    const next = { ...current, members, revision: current.revision + 1 }
    verifyWrite(id, await doc.set(next))
    return snapshot(id, next, viewer)
  })
}
