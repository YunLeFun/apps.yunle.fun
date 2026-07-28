import type {
  PersonalWorkshop,
  WorkshopJoinPolicy,
  WorkshopMembership,
  WorkshopStatus,
} from '../domain/catalog'
import type { CloudbaseTransaction } from './cloudbase-admin'
import type { ServerAuthUser } from './cloudbase-auth'
import { randomBytes, randomUUID } from 'node:crypto'
import { createError } from 'h3'
import {
  PERSONAL_WORKSHOPS_COLLECTION,
  WORKSHOP_EVENTS_COLLECTION,
  WORKSHOP_MEMBERSHIPS_COLLECTION,
} from '../domain/catalog/cloudbase'
import { useCloudbaseAdmin } from './cloudbase-admin'

const SHORT_ID_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
const MAX_ID_ATTEMPTS = 8

export interface WorkshopManagementView {
  workshop: PersonalWorkshop
  pending: WorkshopMembership[]
  guests: WorkshopMembership[]
  blocked: WorkshopMembership[]
}

export async function createPersonalWorkshop(
  user: ServerAuthUser,
  input: unknown,
): Promise<PersonalWorkshop> {
  const { db } = useCloudbaseAdmin()
  const existing = await findWorkshopByOwner(user.uid)
  if (existing) {
    throw createError({
      statusCode: 409,
      message: '每位用户只能创建一个个人工坊',
      data: { code: 'WORKSHOP_ALREADY_EXISTS', workshopId: existing._id },
    })
  }

  const value = isRecord(input) ? input : {}
  const now = Date.now()
  const workshop: PersonalWorkshop = {
    _id: await generateWorkshopId(),
    ownerUid: user.uid,
    ownerName: user.name || user.handle || '坊主',
    ...(user.picture ? { ownerAvatar: user.picture } : {}),
    name: limitedString(value.name, 40) || `${user.name || user.handle || '我的'}的个人工坊`,
    description: limitedString(value.description, 200),
    joinPolicy: 'approval',
    status: 'active',
    createdAt: now,
    updatedAt: now,
  }

  await db.runTransaction(async (transaction: CloudbaseTransaction) => {
    await transaction.collection(PERSONAL_WORKSHOPS_COLLECTION)
      .doc(workshop._id)
      .set(documentPayload(workshop))
    await transaction.collection(WORKSHOP_EVENTS_COLLECTION)
      .doc(eventId())
      .set({
        workshopId: workshop._id,
        action: 'workshop.created',
        actorUid: user.uid,
        createdAt: now,
      })
  })
  return workshop
}

export async function getOwnedWorkshopManagement(
  user: ServerAuthUser,
): Promise<WorkshopManagementView | null> {
  const workshop = await findWorkshopByOwner(user.uid)
  if (!workshop)
    return null
  const memberships = await listMemberships(workshop._id)
  return {
    workshop,
    pending: memberships.filter(item => item.status === 'pending'),
    guests: memberships.filter(item => item.status === 'active'),
    blocked: memberships.filter(item => item.status === 'blocked'),
  }
}

export async function updatePersonalWorkshop(
  user: ServerAuthUser,
  workshopId: string,
  input: unknown,
): Promise<PersonalWorkshop> {
  const { db } = useCloudbaseAdmin()
  const workshop = await requireOwnedWorkshop(user, workshopId)
  const value = isRecord(input) ? input : {}
  const joinPolicy = normalizeJoinPolicy(value.joinPolicy, workshop.joinPolicy)
  const status = normalizeStatus(value.status, workshop.status)
  const now = Date.now()
  const next: PersonalWorkshop = {
    ...workshop,
    name: limitedString(value.name, 40) || workshop.name,
    description: value.description === undefined
      ? workshop.description
      : limitedString(value.description, 200),
    joinPolicy,
    status,
    updatedAt: now,
  }
  const changed: string[] = []
  if (next.name !== workshop.name)
    changed.push('name')
  if (next.description !== workshop.description)
    changed.push('description')
  if (next.joinPolicy !== workshop.joinPolicy)
    changed.push('joinPolicy')
  if (next.status !== workshop.status)
    changed.push('status')

  await db.runTransaction(async (transaction: CloudbaseTransaction) => {
    await transaction.collection(PERSONAL_WORKSHOPS_COLLECTION)
      .doc(workshopId)
      .update({
        name: next.name,
        description: next.description || '',
        joinPolicy: next.joinPolicy,
        status: next.status,
        updatedAt: now,
      })
    await transaction.collection(WORKSHOP_EVENTS_COLLECTION)
      .doc(eventId())
      .set({
        workshopId,
        action: 'workshop.updated',
        actorUid: user.uid,
        metadata: { changed },
        createdAt: now,
      })
  })
  return next
}

export async function listJoinedWorkshops(
  user: ServerAuthUser,
): Promise<PersonalWorkshop[]> {
  const { db } = useCloudbaseAdmin()
  const { data } = await db.collection(WORKSHOP_MEMBERSHIPS_COLLECTION)
    .where({ userUid: user.uid, status: 'active' })
    .limit(100)
    .get()
  const memberships = asArray<WorkshopMembership>(data)
  const workshops = await Promise.all(memberships.map(async (membership) => {
    const { data: workshopData } = await db.collection(PERSONAL_WORKSHOPS_COLLECTION)
      .doc(membership.workshopId)
      .get()
    return first<PersonalWorkshop>(workshopData)
  }))
  return workshops
    .filter((workshop): workshop is PersonalWorkshop => Boolean(workshop))
    .sort((left, right) => right.updatedAt - left.updatedAt)
}

export async function requireOwnedWorkshop(
  user: ServerAuthUser,
  workshopId: string,
): Promise<PersonalWorkshop> {
  const { db } = useCloudbaseAdmin()
  const { data } = await db.collection(PERSONAL_WORKSHOPS_COLLECTION).doc(workshopId).get()
  const workshop = first<PersonalWorkshop>(data)
  if (!workshop)
    throw createError({ statusCode: 404, message: '个人工坊不存在' })
  if (workshop.ownerUid !== user.uid)
    throw createError({ statusCode: 403, message: '只有坊主可以管理此个人工坊' })
  return workshop
}

async function findWorkshopByOwner(ownerUid: string): Promise<PersonalWorkshop | null> {
  const { db } = useCloudbaseAdmin()
  const { data } = await db.collection(PERSONAL_WORKSHOPS_COLLECTION)
    .where({ ownerUid })
    .limit(1)
    .get()
  return first<PersonalWorkshop>(data)
}

async function listMemberships(workshopId: string): Promise<WorkshopMembership[]> {
  const { db } = useCloudbaseAdmin()
  const { data } = await db.collection(WORKSHOP_MEMBERSHIPS_COLLECTION)
    .where({ workshopId })
    .orderBy('updatedAt', 'desc')
    .limit(500)
    .get()
  return asArray<WorkshopMembership>(data)
}

async function generateWorkshopId(): Promise<string> {
  const { db } = useCloudbaseAdmin()
  for (let attempt = 0; attempt < MAX_ID_ATTEMPTS; attempt += 1) {
    const bytes = randomBytes(6)
    let id = ''
    for (const byte of bytes)
      id += SHORT_ID_ALPHABET[byte % SHORT_ID_ALPHABET.length]
    const { data } = await db.collection(PERSONAL_WORKSHOPS_COLLECTION).doc(id).get()
    if (!first<PersonalWorkshop>(data))
      return id
  }
  throw createError({ statusCode: 503, message: '暂时无法创建个人工坊，请稍后再试' })
}

function normalizeJoinPolicy(
  value: unknown,
  fallback: WorkshopJoinPolicy,
): WorkshopJoinPolicy {
  if (value === undefined)
    return fallback
  if (value === 'approval' || value === 'open' || value === 'closed')
    return value
  throw createError({ statusCode: 400, message: '加入方式无效' })
}

function normalizeStatus(value: unknown, fallback: WorkshopStatus): WorkshopStatus {
  if (value === undefined)
    return fallback
  if (value === 'active' || value === 'disabled')
    return value
  throw createError({ statusCode: 400, message: '个人工坊状态无效' })
}

function limitedString(value: unknown, maxLength: number): string {
  if (value === undefined || value === null)
    return ''
  if (typeof value !== 'string')
    throw createError({ statusCode: 400, message: '文本格式无效' })
  const result = value.trim()
  if (result.length > maxLength)
    throw createError({ statusCode: 400, message: `文本不能超过 ${maxLength} 个字符` })
  return result
}

function eventId(): string {
  return `workshop_event_${randomUUID().replace(/-/g, '')}`
}

function documentPayload<T extends { _id: string }>(document: T): Omit<T, '_id'> {
  const { _id: _documentId, ...payload } = document
  return payload
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function asArray<T>(value: unknown): T[] {
  if (Array.isArray(value))
    return value as T[]
  return value ? [value as T] : []
}

function first<T>(value: unknown): T | null {
  return asArray<T>(value)[0] || null
}
