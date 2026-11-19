import type { WebBuildPage, WebBuildProject, WebBuildSummary } from '~~/server/utils/web-build-page'
import type { CloudbaseTransaction } from './cloudbase-admin'
import { createHash, randomUUID } from 'node:crypto'
import { createError } from 'h3'
import { parseWebBuildPage } from '~~/server/utils/web-build-page'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { moderateText } from './moderation'
import { storeWebBuildArtifact } from './web-build-artifacts'
import { webBuildIdPattern, webBuildShareUrl } from './web-build-config'

const collection = 'web_builds'
const dailyLimits = { generate: 8, publish: 12 } as const

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

async function owned(db: CloudbaseTransaction, id: string, uid: string) {
  if (id.length !== 32 || !webBuildIdPattern.test(id))
    missingWebBuild()
  const project = await read(db, id)
  if (project?.kind !== 'project' || project.ownerUid !== uid)
    missingWebBuild()
  return project
}

function summary(id: string, project: Project): WebBuildSummary {
  return {
    id,
    title: project.page.title,
    updatedAt: project.updatedAt,
    shareUrl: project.releaseId && !project.blockedAt ? webBuildShareUrl(id) : null,
  }
}

function serialize(id: string, project: Project): WebBuildProject {
  const { title: _title, ...item } = summary(id, project)
  return {
    ...item,
    revision: project.revision,
    page: storedPage(project.page),
    prompts: project.prompts,
    publishedRevision: item.shareUrl ? project.publishedRevision : null,
  }
}

export async function listWebBuilds(uid: string) {
  const db = useCloudbaseAdmin().db
  // Projects are the only document type with an ownerUid field.
  const { data } = await db.collection(collection).where({ ownerUid: uid }).orderBy('updatedAt', 'desc').limit(100).get()
  return ((data || []) as (Project & { _id: string })[])
    .filter(project => !project.blockedAt)
    .map(project => summary(project._id, project))
}

export async function getOwnedWebBuild(id: string, uid: string) {
  const project = await owned(useCloudbaseAdmin().db, id, uid)
  if (project.blockedAt)
    missingWebBuild()
  return serialize(id, project)
}

export async function reserveWebBuildAction(uid: string, action: keyof typeof dailyLimits) {
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', dateStyle: 'short' }).format()
  const key = `quota_${createHash('sha256').update(JSON.stringify([uid, day, action])).digest('hex')}`
  const db = useCloudbaseAdmin().db
  await db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const quota = await read(transaction, key)
    const count = quota?.kind === 'quota' ? quota.count : 0
    if (count >= dailyLimits[action])
      throw createError({ statusCode: 429, statusMessage: action === 'generate' ? '已达到今日网页生成次数上限' : '已达到今日网页发布次数上限' })
    await doc(transaction, key).set({ kind: 'quota', count: count + 1 })
    return true
  })
}

export async function saveWebBuildDraft(uid: string, page: WebBuildPage, prompt: string, prior?: Pick<WebBuildProject, 'id' | 'revision'>) {
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
    return serialize(id, project)
  }
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await owned(transaction, prior.id, uid)
    if (project.blockedAt)
      missingWebBuild()
    assertRevision(project, prior.revision)
    const updated: Project = {
      ...project,
      page,
      revision: project.revision + 1,
      prompts: [...project.prompts, prompt].slice(-8),
      updatedAt: Date.now(),
    }
    await doc(transaction, prior.id).update({
      page: updated.page,
      revision: updated.revision,
      prompts: updated.prompts,
      updatedAt: updated.updatedAt,
    })
    return serialize(prior.id, updated)
  })
}

export async function publishWebBuild(id: string, uid: string, revision: unknown) {
  const db = useCloudbaseAdmin().db
  const project = await owned(db, id, uid)
  if (project.blockedAt)
    missingWebBuild()
  assertRevision(project, revision)
  if (project.releaseId && project.publishedRevision === revision)
    return serialize(id, project)

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
      return serialize(id, current)
    const release: Release = { kind: 'release', projectId: id, revision: current.revision, page, artifactSha256: sha256 }
    const updated = { releaseId, publishedRevision: current.revision, updatedAt: Date.now() }
    await doc(transaction, releaseId).set(release)
    await doc(transaction, id).update(updated)
    return serialize(id, { ...current, ...updated })
  })
}

export async function withdrawWebBuild(id: string, uid: string, revision: unknown) {
  const db = useCloudbaseAdmin().db
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const project = await owned(transaction, id, uid)
    assertRevision(project, revision)
    const updated = { releaseId: null, publishedRevision: null, revision: project.revision + 1, updatedAt: Date.now() }
    await doc(transaction, id).update(updated)
    return serialize(id, { ...project, ...updated })
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
