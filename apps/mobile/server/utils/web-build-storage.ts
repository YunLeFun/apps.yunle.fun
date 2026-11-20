import type { WebBuildPage, WebBuildProject, WebBuildRoomMember, WebBuildRoomMessage, WebBuildSummary } from '~~/server/utils/web-build-page'
import type { CloudbaseTransaction } from './cloudbase-admin'
import type { ServerAuthUser } from './cloudbase-auth'
import { createHash, randomUUID } from 'node:crypto'
import { createError } from 'h3'
import { parseWebBuildPage } from '~~/server/utils/web-build-page'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { moderateText } from './moderation'
import { storeWebBuildArtifact } from './web-build-artifacts'
import { webBuildIdPattern, webBuildShareUrl } from './web-build-config'

const collection = 'web_builds'
const dailyLimits = { generate: 8, publish: 12, chat: 120, friendInvite: 32 } as const
const limitMessages = {
  generate: '已达到今日网页生成次数上限',
  publish: '已达到今日网页发布次数上限',
  chat: '已达到今日项目聊天发送次数上限',
  friendInvite: '已达到今日好友邀请次数上限',
}
const roomCapacity = 8
const roomMessageLimit = 50
const inviteDuration = 24 * 60 * 60 * 1000
const notificationCollection = 'user_notifications'
const friendInviteType = 'web_build_invite'

interface RoomMember extends WebBuildRoomMember {
  uid: string
}

interface Room {
  owner: WebBuildRoomMember
  members: RoomMember[]
  messages: WebBuildRoomMessage[]
  invite: { digest: string, expiresAt: number } | null
  friendInvites?: { epoch: string, expiresAt: number } | null
}

interface FriendInvite {
  type: typeof friendInviteType
  userId: string
  actorId: string
  webBuildInvite: { projectId: string, title: string, expiresAt: number, epoch: string }
  read: boolean
  createdAt: number
}

interface Project {
  kind: 'project'
  ownerUid: string
  revision: number
  page: WebBuildPage
  prompts: string[]
  releaseId: string | null
  publishedRevision: number | null
  blockedAt?: number
  updatedAt: number
  room?: Room
  collaboratorUids?: string[]
}

interface Release {
  kind: 'release'
  projectId: string
  revision: number
  page: WebBuildPage
  artifactSha256: string
}

type Stored = Project | Release | { kind: 'quota', count: number }

function newId() {
  return randomUUID().replaceAll('-', '')
}

function doc(db: CloudbaseTransaction, id: string) {
  return db.collection(collection).doc(id)
}

async function read(db: CloudbaseTransaction, id: string): Promise<Stored | undefined> {
  const result = await doc(db, id).get()
  if (result.code)
    throw createError({ statusCode: 503, statusMessage: '暂时无法读取网页' })
  return (Array.isArray(result.data) ? result.data[0] : result.data) as Stored | undefined
}

export function missingWebBuild(): never {
  throw createError({ statusCode: 404, statusMessage: '网页不存在或已停用' })
}

function assertRevision(project: Project, expected: unknown) {
  if (project.revision !== expected)
    throw createError({ statusCode: 409, statusMessage: '网页已有更新，请刷新后再试' })
}

function storedPage(page: unknown) {
  const parsed = parseWebBuildPage(page)
  if (!parsed)
    throw createError({ statusCode: 503, statusMessage: '网页内容暂不可用' })
  return parsed
}

async function readProject(db: CloudbaseTransaction, id: string) {
  if (id.length !== 32 || !webBuildIdPattern.test(id))
    missingWebBuild()
  const project = await read(db, id)
  if (project?.kind !== 'project')
    missingWebBuild()
  return project
}

async function owned(db: CloudbaseTransaction, id: string, uid: string) {
  const project = await readProject(db, id)
  if (project.ownerUid !== uid)
    missingWebBuild()
  return project
}

function roomActor(project: Project, uid: string): WebBuildRoomMember | undefined {
  if (!project.room)
    return
  if (project.ownerUid === uid)
    return project.room.owner
  const member = project.room.members.find(member => member.uid === uid)
  return member && { id: member.id, name: member.name }
}

async function editable(db: CloudbaseTransaction, id: string, uid: string) {
  const project = await readProject(db, id)
  if (project.blockedAt || (project.ownerUid !== uid && !roomActor(project, uid)))
    missingWebBuild()
  return project
}

type ListedProject = Pick<Project, 'kind' | 'ownerUid' | 'releaseId' | 'blockedAt' | 'updatedAt' | 'collaboratorUids'> & {
  page: Pick<WebBuildPage, 'title'>
}

function summary(id: string, project: ListedProject, uid: string): WebBuildSummary {
  return {
    id,
    title: project.page.title,
    updatedAt: project.updatedAt,
    role: project.ownerUid === uid ? 'owner' : 'member',
    shareUrl: project.releaseId && !project.blockedAt ? webBuildShareUrl(id) : null,
  }
}

function serialize(id: string, project: Project, uid: string): WebBuildProject {
  const { title: _title, ...item } = summary(id, project, uid)
  const actor = roomActor(project, uid)
  const room = actor && project.room
  return {
    ...item,
    revision: project.revision,
    page: storedPage(project.page),
    prompts: item.role === 'owner' ? project.prompts : room?.messages.filter(message => message.kind === 'edit').slice(-8).map(message => message.text) ?? [],
    publishedRevision: item.shareUrl ? project.publishedRevision : null,
    ...(room && actor && { room: {
      members: [room.owner, ...room.members.map(({ id, name }) => ({ id, name }))],
      viewerId: actor.id,
      messages: room.messages,
      inviteExpiresAt: item.role === 'owner' && room.invite && room.invite.expiresAt > Date.now() ? room.invite.expiresAt : null,
      ...(item.role === 'owner' && room.friendInvites && room.friendInvites.expiresAt > Date.now()
        && { friendInvitesExpireAt: room.friendInvites.expiresAt }),
    } }),
  }
}

export async function listWebBuilds(uid: string, includeShared = false) {
  const db = useCloudbaseAdmin().db
  const fields = { _id: true, kind: true, ownerUid: true, page: true, releaseId: true, blockedAt: true, updatedAt: true, collaboratorUids: true }
  const [owned, shared] = await Promise.all([
    db.collection(collection).where({ ownerUid: uid }).field(fields).orderBy('updatedAt', 'desc').limit(100).get(),
    includeShared ? db.collection(collection).where({ collaboratorUids: db.command.in([uid]) }).field(fields).orderBy('updatedAt', 'desc').limit(100).get() : undefined,
  ])
  if (!Array.isArray(owned.data) || (shared && !Array.isArray(shared.data)))
    throw createError({ statusCode: 503, statusMessage: '暂时无法读取网页' })
  return ([...owned.data, ...(shared?.data || [])] as (ListedProject & { _id: string })[])
    .filter(project => project.kind === 'project' && !project.blockedAt && (project.ownerUid === uid || project.collaboratorUids?.includes(uid)))
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, 100)
    .map(project => summary(project._id, project, uid))
}

export async function getOwnedWebBuild(id: string, uid: string) {
  const project = await owned(useCloudbaseAdmin().db, id, uid)
  if (project.blockedAt)
    missingWebBuild()
  return serialize(id, project, uid)
}

export async function getEditableWebBuild(id: string, uid: string) {
  return serialize(id, await editable(useCloudbaseAdmin().db, id, uid), uid)
}

export async function reserveWebBuildAction(uid: string, action: keyof typeof dailyLimits) {
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', dateStyle: 'short' }).format()
  const key = `quota_${createHash('sha256').update(JSON.stringify([uid, day, action])).digest('hex')}`
  const db = useCloudbaseAdmin().db
  await db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const quota = await read(transaction, key)
    const count = quota?.kind === 'quota' ? quota.count : 0
    if (count >= dailyLimits[action])
      throw createError({ statusCode: 429, statusMessage: limitMessages[action] })
    await doc(transaction, key).set({ kind: 'quota', count: count + 1 })
    return true
  })
}

export async function saveWebBuildDraft(uid: string, page: WebBuildPage, prompt: string, prior?: Pick<WebBuildProject, 'id' | 'revision' | 'room'>) {
  const db = useCloudbaseAdmin().db
  if (!prior) {
    const id = newId()
    const project: Project = {
      kind: 'project',
      ownerUid: uid,
      revision: 1,
      page,
      prompts: [prompt],
      releaseId: null,
      publishedRevision: null,
      updatedAt: Date.now(),
    }
    await doc(db, id).set(project)
    return serialize(id, project, uid)
  }
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await editable(transaction, prior.id, uid)
    assertRevision(project, prior.revision)
    const updated: Project = {
      ...project,
      page,
      revision: project.revision + 1,
      prompts: [...project.prompts, prompt].slice(-8),
      updatedAt: Date.now(),
    }
    const actor = roomActor(project, uid)
    if (prior.room && actor && project.room)
      updated.room = appendRoomMessage(project.room, actor, 'edit', prompt)
    await doc(transaction, prior.id).update({
      page: updated.page,
      revision: updated.revision,
      prompts: updated.prompts,
      updatedAt: updated.updatedAt,
      ...(updated.room && { room: updated.room }),
    })
    return serialize(prior.id, updated, uid)
  })
}

function appendRoomMessage(room: Room, author: WebBuildRoomMember, kind: WebBuildRoomMessage['kind'], text: string): Room {
  const message = { id: newId(), author, kind, text, createdAt: Date.now() }
  return { ...room, messages: [...room.messages, message].slice(-roomMessageLimit) }
}

function actorName(user: ServerAuthUser, fallback: string) {
  const name = user.name?.trim()
  return name && name.length <= 40 ? name : fallback
}

function inviteDigest(code: string) {
  return createHash('sha256').update(code).digest('hex')
}

function roomForInviting(project: Project, user: ServerAuthUser): Room {
  if (project.blockedAt)
    missingWebBuild()
  const room = project.room ?? { owner: { id: 'owner', name: actorName(user, '项目所有者') }, members: [], messages: [], invite: null }
  requireRoomSeat(room)
  return room
}

function requireRoomSeat(room: Room) {
  if (room.members.length >= roomCapacity - 1)
    throw createError({ statusCode: 409, statusMessage: '项目已满（最多 8 人）', data: { code: 'WEB_BUILD_ROOM_FULL' } })
}

export async function createWebBuildRoomInvite(id: string, user: ServerAuthUser) {
  const db = useCloudbaseAdmin().db
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await owned(transaction, id, user.uid)
    const current = roomForInviting(project, user)
    const inviteCode = `${id}.${newId()}`
    const room = { ...current, invite: { digest: inviteDigest(inviteCode), expiresAt: Date.now() + inviteDuration } }
    await doc(transaction, id).update({ room })
    return { project: serialize(id, { ...project, room }, user.uid), inviteCode }
  })
}

export async function revokeWebBuildRoomInvite(id: string, uid: string) {
  const db = useCloudbaseAdmin().db
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await owned(transaction, id, uid)
    if (project.blockedAt || !project.room)
      missingWebBuild()
    const room = { ...project.room, invite: null, friendInvites: null }
    await doc(transaction, id).update({ room })
    return { project: serialize(id, { ...project, room }, uid) }
  })
}

export async function joinWebBuildRoom(code: string, user: ServerAuthUser) {
  if (code.length !== 65 || !/^[a-f0-9]{32}\.[a-f0-9]{32}$/.test(code))
    throw createError({ statusCode: 400, statusMessage: '请输入完整的项目邀请码' })
  const id = code.slice(0, 32)
  const db = useCloudbaseAdmin().db
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await readProject(transaction, id)
    const current = project.room
    if (project.blockedAt || !current)
      missingWebBuild()
    if (roomActor(project, user.uid))
      return { project: serialize(id, project, user.uid) }
    if (!current.invite || current.invite.expiresAt <= Date.now() || current.invite.digest !== inviteDigest(code))
      missingWebBuild()
    return addRoomMember(transaction, id, project, current, user)
  })
}

async function addRoomMember(db: CloudbaseTransaction, id: string, project: Project, current: Room, user: ServerAuthUser) {
  requireRoomSeat(current)
  const member = { uid: user.uid, id: newId(), name: actorName(user, '成员') }
  const room = { ...current, members: [...current.members, member] }
  const collaboratorUids = room.members.map(member => member.uid)
  await doc(db, id).update({ room, collaboratorUids })
  return { project: serialize(id, { ...project, room, collaboratorUids }, user.uid) }
}

async function readFriendInvite(db: CloudbaseTransaction, noticeId: string, userId: string) {
  const { data, code } = await db.collection(notificationCollection).doc(noticeId).get()
  if (code)
    throw createError({ statusCode: 503, statusMessage: '暂时无法读取邀约' })
  const notice = (Array.isArray(data) ? data[0] : data) as FriendInvite | undefined
  if (notice?.type !== friendInviteType || notice.userId !== userId || !notice.webBuildInvite)
    return
  return notice
}

export async function sendWebBuildFriendInvite(id: string, user: ServerAuthUser, targetId: string, checkPeer: (target: string) => Promise<void>) {
  const db = useCloudbaseAdmin().db
  const initial = await owned(db, id, user.uid)
  roomForInviting(initial, user)
  await checkPeer(targetId)
  await reserveWebBuildAction(user.uid, 'friendInvite')
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await owned(transaction, id, user.uid)
    const current = roomForInviting(project, user)
    if (roomActor(project, targetId))
      throw createError({ statusCode: 409, statusMessage: '对方已加入项目', data: { code: 'WEB_BUILD_ALREADY_JOINED' } })
    const now = Date.now()
    const epoch = current.friendInvites && current.friendInvites.expiresAt > now ? current.friendInvites.epoch : newId()
    const noticeId = inviteDigest(JSON.stringify([friendInviteType, id, targetId, epoch])).slice(0, 24)
    const previous = await readFriendInvite(transaction, noticeId, targetId)
    if (previous && previous.webBuildInvite.expiresAt > now)
      return { project: serialize(id, project, user.uid) }

    const expiresAt = now + inviteDuration
    const room = { ...current, friendInvites: { epoch, expiresAt } }
    const notice: FriendInvite = {
      userId: targetId,
      actorId: user.uid,
      type: friendInviteType,
      webBuildInvite: { projectId: id, title: storedPage(project.page).title, expiresAt, epoch },
      read: false,
      createdAt: now,
    }
    await doc(transaction, id).update({ room })
    await transaction.collection(notificationCollection).doc(noticeId).set(notice)
    return { project: serialize(id, { ...project, room }, user.uid) }
  })
}

export async function acceptWebBuildFriendInvite(noticeId: string, user: ServerAuthUser, checkPeer: (target: string) => Promise<void>) {
  const db = useCloudbaseAdmin().db
  const notice = await readFriendInvite(db, noticeId, user.uid)
  if (!notice)
    missingWebBuild()
  const id = notice.webBuildInvite.projectId
  const initial = await readProject(db, id)
  if (initial.blockedAt || initial.ownerUid !== notice.actorId)
    missingWebBuild()
  if (roomActor(initial, user.uid))
    return { project: serialize(id, initial, user.uid) }
  if (notice.webBuildInvite.expiresAt <= Date.now() || initial.room?.friendInvites?.epoch !== notice.webBuildInvite.epoch)
    missingWebBuild()
  await checkPeer(notice.actorId)

  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const current = await readFriendInvite(transaction, noticeId, user.uid)
    const project = await readProject(transaction, id)
    if (!current || current.webBuildInvite.projectId !== id || current.actorId !== notice.actorId
      || project.ownerUid !== current.actorId || project.blockedAt || !project.room) {
      missingWebBuild()
    }
    if (roomActor(project, user.uid))
      return { project: serialize(id, project, user.uid) }
    if (current.webBuildInvite.expiresAt <= Date.now() || project.room.friendInvites?.epoch !== current.webBuildInvite.epoch)
      missingWebBuild()
    return addRoomMember(transaction, id, project, project.room, user)
  })
}

export async function changeWebBuildRoomMembers(id: string, uid: string, removeMemberId?: string) {
  const db = useCloudbaseAdmin().db
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await editable(transaction, id, uid)
    const current = project.room
    const isOwner = project.ownerUid === uid
    if (!current || (removeMemberId !== undefined) !== isOwner)
      missingWebBuild()
    const members = current.members.filter(member => isOwner ? member.id !== removeMemberId : member.uid !== uid)
    const room = {
      ...current,
      members,
      ...(isOwner && current.members.length !== members.length && { invite: null, friendInvites: null }),
    }
    await doc(transaction, id).update({ room, collaboratorUids: members.map(member => member.uid) })
    return isOwner ? { project: serialize(id, { ...project, room }, uid) } : {}
  })
}

export async function moderateWebBuildRoomMessage(id: string, uid: string, text: string) {
  const result = await moderateText({ content: text, userId: uid, dataId: `web-build-chat-${id}-${newId()}`, scene: 'web_build_chat' })
  if (result.error)
    throw createError({ statusCode: 503, statusMessage: '项目聊天审核暂不可用' })
  if (result.suggestion !== 'Pass')
    throw createError({ statusCode: 422, statusMessage: '消息未通过审核，请修改后重试' })
}

export async function sendWebBuildRoomMessage(id: string, uid: string, text: string) {
  const db = useCloudbaseAdmin().db
  const initial = await editable(db, id, uid)
  if (!initial.room)
    missingWebBuild()
  await reserveWebBuildAction(uid, 'chat')
  await moderateWebBuildRoomMessage(id, uid, text)

  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await editable(transaction, id, uid)
    const actor = roomActor(project, uid)
    if (!project.room || !actor)
      missingWebBuild()
    const room = appendRoomMessage(project.room, actor, 'chat', text)
    await doc(transaction, id).update({ room })
    return { project: serialize(id, { ...project, room }, uid) }
  })
}

export async function publishWebBuild(id: string, uid: string, revision: unknown) {
  const db = useCloudbaseAdmin().db
  const project = await owned(db, id, uid)
  if (project.blockedAt)
    missingWebBuild()
  assertRevision(project, revision)
  if (project.releaseId && project.publishedRevision === revision)
    return serialize(id, project, uid)

  const page = storedPage(project.page)
  await reserveWebBuildAction(uid, 'publish')
  const result = await moderateText({
    content: [page.title, page.description, ...page.sections.flatMap(section => [section.title, section.text])].join('\n'),
    userId: uid,
    dataId: `web-build-${id}-${project.revision}`,
    scene: 'web_build',
  })
  if (result.error)
    throw createError({ statusCode: 503, statusMessage: '网页内容审核暂不可用' })
  if (result.suggestion !== 'Pass')
    throw createError({ statusCode: 422, statusMessage: '网页未通过发布审核，请修改内容后重试' })

  const { releaseId, sha256 } = await storeWebBuildArtifact(id, project.revision, page)
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const current = await owned(transaction, id, uid)
    if (current.blockedAt)
      missingWebBuild()
    assertRevision(current, revision)
    if (current.releaseId && current.publishedRevision === revision)
      return serialize(id, current, uid)
    const release: Release = { kind: 'release', projectId: id, revision: current.revision, page, artifactSha256: sha256 }
    const updated = { releaseId, publishedRevision: current.revision, updatedAt: Date.now() }
    await doc(transaction, releaseId).set(release)
    await doc(transaction, id).update(updated)
    return serialize(id, { ...current, ...updated }, uid)
  })
}

export async function withdrawWebBuild(id: string, uid: string, revision: unknown) {
  const db = useCloudbaseAdmin().db
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await owned(transaction, id, uid)
    assertRevision(project, revision)
    const updated = { releaseId: null, publishedRevision: null, revision: project.revision + 1, updatedAt: Date.now() }
    await doc(transaction, id).update(updated)
    return serialize(id, { ...project, ...updated }, uid)
  })
}

export async function getWebBuildForSubmission(id: string, uid: string, revision: unknown, db: CloudbaseTransaction = useCloudbaseAdmin().db) {
  const project = await owned(db, id, uid)
  if (project.blockedAt)
    missingWebBuild()
  assertRevision(project, revision)
  if (!project.releaseId || project.publishedRevision !== revision)
    throw createError({ statusCode: 409, statusMessage: '请先发布当前版本再投稿' })
  const release = await read(db, project.releaseId)
  if (!isStaticRelease(release, id) || release.revision !== revision)
    missingWebBuild()
  return { releaseId: project.releaseId, page: storedPage(release.page) }
}

function isStaticRelease(release: Stored | undefined, projectId: string): release is Release {
  return release?.kind === 'release' && release.projectId === projectId
    && typeof release.artifactSha256 === 'string' && /^[a-f0-9]{64}$/.test(release.artifactSha256)
}

export async function getPublicWebBuild(id: string, version?: string) {
  const db = useCloudbaseAdmin().db
  const project = await read(db, id)
  if (project?.kind !== 'project' || project.blockedAt || !project.releaseId)
    missingWebBuild()
  const releaseId = version ?? project.releaseId
  const release = await read(db, releaseId)
  if (!isStaticRelease(release, id))
    missingWebBuild()
  return { releaseId, sha256: release.artifactSha256 }
}
