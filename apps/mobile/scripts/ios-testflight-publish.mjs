#!/usr/bin/env node

import { Buffer } from 'node:buffer'
import { createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { resolve } from 'node:path'
import process from 'node:process'
import { pathToFileURL } from 'node:url'

const API_BASE_URL = 'https://api.appstoreconnect.apple.com'
const INTERNAL_TESTER_ROLES = new Set([
  'ACCOUNT_HOLDER',
  'ADMIN',
  'APP_MANAGER',
  'DEVELOPER',
  'MARKETING',
])

const DEFAULTS = {
  bundleId: 'fun.yunle.apps',
  groupName: '云乐坊内测组',
  locale: 'zh-Hans',
  feedbackEmail: 'i@yunle.fun',
  marketingUrl: 'https://www.yunle.fun',
  privacyPolicyUrl: 'https://www.yunle.fun/docs/privacy-policy',
  betaDescription: '云乐坊是一个云应用聚合平台，可在工坊发现云应用，并将常用应用加入云居桌面随时使用。',
  whatsNew: '请重点验证登录与账号、云应用发现和启动、云居桌面与 Dock、扫码、工坊互动、AI 助手及会员/云币内购；如遇崩溃、卡顿或功能异常，请通过 TestFlight 截图反馈。',
}

export function parseArgs(argv) {
  const options = {
    buildNumber: undefined,
    dryRun: false,
    help: false,
    inviteAllInternalUsers: false,
    testerEmails: [],
    marketingVersion: undefined,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--') {
      continue
    }
    else if (arg === '--build') {
      options.buildNumber = requireValue(argv, ++index, arg)
    }
    else if (arg === '--version') {
      options.marketingVersion = requireValue(argv, ++index, arg)
    }
    else if (arg === '--tester-email') {
      options.testerEmails.push(requireValue(argv, ++index, arg))
    }
    else if (arg === '--invite-all-internal-users') {
      options.inviteAllInternalUsers = true
    }
    else if (arg === '--dry-run') {
      options.dryRun = true
    }
    else if (arg === '--help' || arg === '-h') {
      options.help = true
    }
    else {
      throw new Error(`未知参数：${arg}`)
    }
  }

  return options
}

function requireValue(argv, index, flag) {
  const value = argv[index]
  if (!value || value.startsWith('--'))
    throw new Error(`${flag} 需要一个值`)
  return value
}

export function maskEmail(email) {
  const [local = '', domain = ''] = String(email).split('@')
  if (!domain)
    return '***'
  return `${local.slice(0, 2)}***@${domain}`
}

export function maskSensitiveText(value) {
  return String(value).replace(
    /[\w.%+-]+(?:@|%40)[\w.-]+(?:\.|%2e)[a-z]{2,}/gi,
    (email) => {
      try {
        return maskEmail(decodeURIComponent(email))
      }
      catch {
        return '***'
      }
    },
  )
}

export function selectBuild(builds, requestedBuildNumber) {
  const requested = requestedBuildNumber
    ? builds.filter(build => build.attributes.version === requestedBuildNumber)
    : builds

  if (!requested.length)
    throw new Error(requestedBuildNumber ? `找不到构建 ${requestedBuildNumber}` : '没有可用构建')

  const eligible = requested
    .filter(build => build.attributes.processingState === 'VALID' && !build.attributes.expired)
    .sort((left, right) => Date.parse(right.attributes.uploadedDate) - Date.parse(left.attributes.uploadedDate))

  if (!eligible.length) {
    const states = requested.map(build => `${build.attributes.version}:${build.attributes.processingState}`).join(', ')
    throw new Error(`构建尚不可发布（${states}）`)
  }
  if (requestedBuildNumber && eligible.length > 1)
    throw new Error('同一构建号对应多个版本，请同时指定 --version')

  return eligible[0]
}

export function matchEligibleTesters({ betaTesters, eligibleUsers, requestedEmails, inviteAll }) {
  if (!inviteAll && requestedEmails.length === 0)
    return []

  const eligibleByEmail = new Map(
    eligibleUsers
      .filter(user => user.attributes.roles?.some(role => INTERNAL_TESTER_ROLES.has(role)))
      .map(user => [user.attributes.username.toLowerCase(), user]),
  )
  const testerByEmail = new Map(
    betaTesters.map(tester => [tester.attributes.email.toLowerCase(), tester]),
  )
  const targetEmails = inviteAll
    ? [...eligibleByEmail.keys()]
    : requestedEmails.map(email => email.toLowerCase())

  const missingUsers = targetEmails.filter(email => !eligibleByEmail.has(email))
  if (missingUsers.length)
    throw new Error(`以下邮箱不是当前 App 的内部用户：${missingUsers.map(maskEmail).join(', ')}`)

  return targetEmails.map(email => ({
    email,
    tester: testerByEmail.get(email) ?? null,
    user: eligibleByEmail.get(email),
  }))
}

export class AppStoreConnectClient {
  constructor({ fetchImpl = globalThis.fetch, token }) {
    this.fetchImpl = fetchImpl
    this.token = token
  }

  async request(path, { method = 'GET', body } = {}) {
    const url = path.startsWith('http') ? path : `${API_BASE_URL}${path}`
    const response = await this.fetchImpl(url, {
      method,
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    })
    const text = await response.text()
    let payload = null
    if (text) {
      try {
        payload = JSON.parse(text)
      }
      catch {
        payload = text
      }
    }

    if (!response.ok) {
      const details = payload?.errors?.map(error => `${error.code}: ${error.detail}`).join('; ')
        ?? String(payload)
      throw new Error(maskSensitiveText(`${method} ${path} -> ${response.status}: ${details}`))
    }

    return payload
  }

  async requestAll(path) {
    const resources = []
    let next = path
    while (next) {
      const payload = await this.request(next)
      resources.push(...payload.data)
      next = payload.links?.next ?? null
    }
    return resources
  }
}

export function createAppStoreConnectToken({ issuerId, keyId, keyPath, now = Math.floor(Date.now() / 1000) }) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url')
  const unsigned = [
    encode({ alg: 'ES256', kid: keyId, typ: 'JWT' }),
    encode({ iss: issuerId, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }),
  ].join('.')
  const signer = createSign('SHA256')
  signer.update(unsigned)
  signer.end()
  const signature = signer.sign({
    key: readFileSync(keyPath, 'utf8'),
    dsaEncoding: 'ieee-p1363',
  })
  return `${unsigned}.${signature.toString('base64url')}`
}

export function loadConfig(env, options) {
  const keyId = requireEnv(env, 'ASC_KEY_ID')
  const issuerId = requireEnv(env, 'ASC_ISSUER_ID')
  const keyPath = expandPath(requireEnv(env, 'ASC_KEY_P8'))
  const testerEmails = [
    ...options.testerEmails,
    ...splitEmails(env.ASC_INTERNAL_TESTER_EMAILS),
  ]

  return {
    betaDescription: env.ASC_BETA_DESCRIPTION ?? DEFAULTS.betaDescription,
    buildNumber: options.buildNumber ?? env.ASC_BUILD_NUMBER,
    bundleId: env.ASC_BUNDLE_ID ?? DEFAULTS.bundleId,
    dryRun: options.dryRun,
    feedbackEmail: env.ASC_FEEDBACK_EMAIL ?? DEFAULTS.feedbackEmail,
    groupName: env.ASC_INTERNAL_GROUP ?? DEFAULTS.groupName,
    inviteAllInternalUsers: options.inviteAllInternalUsers,
    issuerId,
    keyId,
    keyPath,
    locale: env.ASC_BETA_LOCALE ?? DEFAULTS.locale,
    marketingUrl: env.ASC_MARKETING_URL ?? DEFAULTS.marketingUrl,
    marketingVersion: options.marketingVersion ?? env.ASC_MARKETING_VERSION,
    privacyPolicyUrl: env.ASC_PRIVACY_POLICY_URL ?? DEFAULTS.privacyPolicyUrl,
    testerEmails: [...new Set(testerEmails.map(email => email.toLowerCase()))],
    whatsNew: env.ASC_WHATS_NEW ?? DEFAULTS.whatsNew,
  }
}

function requireEnv(env, name) {
  const value = env[name]
  if (!value)
    throw new Error(`需要设置 ${name}`)
  return value
}

function expandPath(path) {
  if (path === '~')
    return homedir()
  if (path.startsWith('~/'))
    return resolve(homedir(), path.slice(2))
  return resolve(path)
}

function splitEmails(value) {
  if (!value)
    return []
  return value.split(',').map(email => email.trim()).filter(Boolean)
}

function query(params) {
  return new URLSearchParams(params).toString()
}

async function getApp(client, bundleId) {
  const payload = await client.request(`/v1/apps?${query({
    'filter[bundleId]': bundleId,
    'fields[apps]': 'name,bundleId',
    'limit': '10',
  })}`)
  if (!payload.data[0])
    throw new Error(`App Store Connect 中找不到 ${bundleId}`)
  return payload.data[0]
}

async function getBuild(client, appId, buildNumber, marketingVersion) {
  const params = {
    'filter[app]': appId,
    'fields[builds]': 'version,uploadedDate,expirationDate,expired,processingState,usesNonExemptEncryption,buildAudienceType',
    'limit': '200',
  }
  if (buildNumber)
    params['filter[version]'] = buildNumber
  if (marketingVersion) {
    params.include = 'preReleaseVersion'
    params['fields[builds]'] += ',preReleaseVersion'
    params['fields[preReleaseVersions]'] = 'version,platform'
  }
  const payload = await client.request(`/v1/builds?${query(params)}`)
  const versions = new Set((payload.included ?? [])
    .filter(item => item.type === 'preReleaseVersions'
      && item.attributes.version === marketingVersion && item.attributes.platform === 'IOS')
    .map(item => item.id))
  const builds = marketingVersion
    ? payload.data.filter(item => versions.has(item.relationships?.preReleaseVersion?.data?.id))
    : payload.data
  return selectBuild(builds, buildNumber)
}

async function ensureEncryptionDeclaration(client, build, dryRun, log) {
  if (build.attributes.usesNonExemptEncryption === false)
    return
  if (dryRun) {
    log('将把出口合规设置为“不使用非豁免加密”')
    return
  }
  await client.request(`/v1/builds/${build.id}`, {
    method: 'PATCH',
    body: {
      data: {
        type: 'builds',
        id: build.id,
        attributes: { usesNonExemptEncryption: false },
      },
    },
  })
  log('已完成出口合规设置')
}

async function ensureInternalGroup(client, appId, config, log) {
  const payload = await client.request(`/v1/apps/${appId}/betaGroups?${query({
    'fields[betaGroups]': 'name,isInternalGroup,hasAccessToAllBuilds,feedbackEnabled',
    'limit': '200',
  })}`)
  const sameName = payload.data.find(group => group.attributes.name === config.groupName)
  if (sameName && !sameName.attributes.isInternalGroup)
    throw new Error(`“${config.groupName}”已被外部测试组占用`)

  let group = sameName
  if (!group) {
    if (config.dryRun) {
      log(`将创建内部测试组“${config.groupName}”`)
      return null
    }
    group = (await client.request('/v1/betaGroups', {
      method: 'POST',
      body: {
        data: {
          type: 'betaGroups',
          attributes: {
            name: config.groupName,
            isInternalGroup: true,
            hasAccessToAllBuilds: true,
            feedbackEnabled: true,
          },
          relationships: {
            app: { data: { type: 'apps', id: appId } },
          },
        },
      },
    })).data
    log(`已创建内部测试组“${config.groupName}”`)
  }

  if (!group.attributes.hasAccessToAllBuilds || !group.attributes.feedbackEnabled) {
    if (config.dryRun) {
      log(`将为“${config.groupName}”开启自动分发和反馈`)
    }
    else {
      group = (await client.request(`/v1/betaGroups/${group.id}`, {
        method: 'PATCH',
        body: {
          data: {
            type: 'betaGroups',
            id: group.id,
            attributes: {
              hasAccessToAllBuilds: true,
              feedbackEnabled: true,
            },
          },
        },
      })).data
      log(`已为“${config.groupName}”开启自动分发和反馈`)
    }
  }

  return group
}

async function ensureBuildAccess(client, group, build, config, log) {
  if (!group)
    return
  const payload = await client.request(`/v1/betaGroups/${group.id}/relationships/builds?limit=200`)
  if (payload.data.some(item => item.id === build.id)) {
    log(`构建 ${build.attributes.version} 已关联内测组`)
    return
  }
  if (config.dryRun) {
    log(`将把构建 ${build.attributes.version} 关联到内测组`)
    return
  }
  await client.request(`/v1/betaGroups/${group.id}/relationships/builds`, {
    method: 'POST',
    body: { data: [{ type: 'builds', id: build.id }] },
  })
  log(`已关联构建 ${build.attributes.version}`)
}

async function getEligibleInternalUsers(client, appId) {
  const users = await client.requestAll(`/v1/users?${query({
    'fields[users]': 'firstName,lastName,username,allAppsVisible,roles',
    'limit': '200',
  })}`)
  const eligible = []
  for (const user of users) {
    if (user.attributes.allAppsVisible) {
      eligible.push(user)
      continue
    }
    const visibleApps = await client.requestAll(`/v1/users/${user.id}/visibleApps?limit=200`)
    if (visibleApps.some(app => app.id === appId))
      eligible.push(user)
  }
  return eligible
}

async function ensureInternalTesters(client, group, appId, config, log) {
  if (!group || (!config.inviteAllInternalUsers && config.testerEmails.length === 0))
    return

  const [eligibleUsers, betaTesters, current] = await Promise.all([
    getEligibleInternalUsers(client, appId),
    client.requestAll(`/v1/betaTesters?${query({
      'fields[betaTesters]': 'firstName,lastName,email',
      'limit': '200',
    })}`),
    client.requestAll(`/v1/betaGroups/${group.id}/relationships/betaTesters?limit=200`),
  ])
  const targets = matchEligibleTesters({
    betaTesters,
    eligibleUsers,
    requestedEmails: config.testerEmails,
    inviteAll: config.inviteAllInternalUsers,
  })
  const currentIds = new Set(current.map(tester => tester.id))
  const existingToAdd = targets
    .map(target => target.tester)
    .filter(tester => tester && !currentIds.has(tester.id))
  const usersToCreate = targets.filter(target => !target.tester)
  if (!existingToAdd.length && !usersToCreate.length) {
    log(`内测组已有 ${targets.length} 名目标测试员`)
    return
  }
  if (config.dryRun) {
    log(`将邀请 ${existingToAdd.length + usersToCreate.length} 名内部测试员`)
    return
  }

  for (const target of usersToCreate) {
    await client.request('/v1/betaTesters', {
      method: 'POST',
      body: {
        data: {
          type: 'betaTesters',
          attributes: {
            email: target.email,
            firstName: target.user.attributes.firstName,
            lastName: target.user.attributes.lastName,
          },
          relationships: {
            betaGroups: {
              data: [{ type: 'betaGroups', id: group.id }],
            },
          },
        },
      },
    })
  }

  if (existingToAdd.length) {
    await client.request(`/v1/betaGroups/${group.id}/relationships/betaTesters`, {
      method: 'POST',
      body: {
        data: existingToAdd.map(tester => ({ type: 'betaTesters', id: tester.id })),
      },
    })
  }
  log(`已邀请 ${existingToAdd.length + usersToCreate.length} 名内部测试员`)
}

async function ensureLocalization(client, {
  createPath,
  currentPath,
  locale,
  relationId,
  relationType,
  resourceType,
  attributes,
  dryRun,
  log,
  label,
}) {
  const payload = await client.request(currentPath)
  const current = payload.data.find(localization => localization.attributes.locale === locale)
  const isCurrent = current && Object.entries(attributes)
    .every(([key, value]) => current.attributes[key] === value)
  if (isCurrent) {
    log(`${label}（${locale}）已是最新内容`)
    return
  }
  if (dryRun) {
    log(`${current ? '将更新' : '将创建'} ${label}（${locale}）`)
    return
  }
  if (current) {
    await client.request(`/v1/${resourceType}/${current.id}`, {
      method: 'PATCH',
      body: {
        data: {
          type: resourceType,
          id: current.id,
          attributes,
        },
      },
    })
  }
  else {
    await client.request(createPath, {
      method: 'POST',
      body: {
        data: {
          type: resourceType,
          attributes: { locale, ...attributes },
          relationships: {
            [relationType]: {
              data: { type: `${relationType}s`, id: relationId },
            },
          },
        },
      },
    })
  }
  log(`已${current ? '更新' : '创建'} ${label}（${locale}）`)
}

async function verifyPublication(client, group, build) {
  if (!group)
    return { buildAttached: false, internalBuildState: 'DRY_RUN', testerCount: 0 }
  const [builds, testers, betaDetail] = await Promise.all([
    client.requestAll(`/v1/betaGroups/${group.id}/relationships/builds?limit=200`),
    client.requestAll(`/v1/betaGroups/${group.id}/relationships/betaTesters?limit=200`),
    client.request(`/v1/builds/${build.id}/buildBetaDetail`),
  ])
  return {
    buildAttached: builds.some(item => item.id === build.id),
    internalBuildState: betaDetail.data.attributes.internalBuildState,
    externalBuildState: betaDetail.data.attributes.externalBuildState,
    testerCount: testers.length,
  }
}

export async function publishTestFlight({ client, config, log = console.log }) {
  const app = await getApp(client, config.bundleId)
  const build = await getBuild(client, app.id, config.buildNumber, config.marketingVersion)
  if (build.attributes.buildAudienceType !== 'INTERNAL_ONLY')
    throw new Error('目标构建不是 INTERNAL_ONLY，请用仅内部测试配置重新导出和上传')
  log(`目标：${app.attributes.name} ${config.bundleId}，版本 ${config.marketingVersion ?? '未指定'}，构建 ${build.attributes.version}，Build ID ${build.id}`)

  await ensureEncryptionDeclaration(client, build, config.dryRun, log)
  const group = await ensureInternalGroup(client, app.id, config, log)
  await ensureBuildAccess(client, group, build, config, log)
  await ensureInternalTesters(client, group, app.id, config, log)

  await ensureLocalization(client, {
    createPath: '/v1/betaAppLocalizations',
    currentPath: `/v1/apps/${app.id}/betaAppLocalizations?${query({
      'fields[betaAppLocalizations]': 'locale,description,feedbackEmail,marketingUrl,privacyPolicyUrl',
      'limit': '200',
    })}`,
    locale: config.locale,
    relationId: app.id,
    relationType: 'app',
    resourceType: 'betaAppLocalizations',
    attributes: {
      description: config.betaDescription,
      feedbackEmail: config.feedbackEmail,
      marketingUrl: config.marketingUrl,
      privacyPolicyUrl: config.privacyPolicyUrl,
    },
    dryRun: config.dryRun,
    log,
    label: 'TestFlight App 信息',
  })
  await ensureLocalization(client, {
    createPath: '/v1/betaBuildLocalizations',
    currentPath: `/v1/builds/${build.id}/betaBuildLocalizations?${query({
      'fields[betaBuildLocalizations]': 'locale,whatsNew',
      'limit': '200',
    })}`,
    locale: config.locale,
    relationId: build.id,
    relationType: 'build',
    resourceType: 'betaBuildLocalizations',
    attributes: { whatsNew: config.whatsNew },
    dryRun: config.dryRun,
    log,
    label: '测试重点',
  })

  const result = config.dryRun
    ? { buildAttached: Boolean(group), internalBuildState: 'DRY_RUN', testerCount: 0 }
    : await verifyPublication(client, group, build)
  if (!config.dryRun && (!result.buildAttached || result.internalBuildState !== 'IN_BETA_TESTING'
    || result.externalBuildState !== 'NOT_APPLICABLE' || result.testerCount === 0)) {
    throw new Error(`发布验收失败：${JSON.stringify(result)}`)
  }

  log(config.dryRun
    ? 'Dry run 完成，未修改 App Store Connect'
    : `发布完成：${result.internalBuildState}，内测组 ${result.testerCount} 人`)
  return { app, build, group, ...result }
}

function printHelp() {
  console.log(`用法：
  pnpm publish:ios:testflight -- [选项]

选项：
  --build <number>                 发布指定 build；默认选择最新 VALID build
  --version <version>              同时限定 iOS 营销版本，例如 0.2.0
  --tester-email <email>           邀请指定的现有内部用户，可重复
  --invite-all-internal-users      邀请所有有当前 App 权限的 ASC 用户
  --dry-run                        只检查并显示计划，不修改 ASC
  -h, --help                       显示帮助

必需环境变量：
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_KEY_P8

可选环境变量：
  ASC_BUILD_NUMBER, ASC_MARKETING_VERSION, ASC_INTERNAL_GROUP, ASC_INTERNAL_TESTER_EMAILS,
  ASC_WHATS_NEW, ASC_BETA_DESCRIPTION, ASC_FEEDBACK_EMAIL,
  ASC_MARKETING_URL, ASC_PRIVACY_POLICY_URL, ASC_BETA_LOCALE`)
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2))
    if (options.help) {
      printHelp()
      return
    }
    const config = loadConfig(process.env, options)
    const token = createAppStoreConnectToken(config)
    const client = new AppStoreConnectClient({ token })
    await publishTestFlight({ client, config })
  }
  catch (error) {
    console.error(`❌ ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  }
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : ''
if (import.meta.url === invokedPath)
  await main()
