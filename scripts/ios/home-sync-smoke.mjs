import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'
import { previewHeaders, readPreviewTarget } from './live-target.mjs'

const args = process.argv.slice(2)
const schemaVersion = args.includes('--schema=3') ? 3 : 1
const targetFile = args.find(value => value.startsWith('--target='))?.slice('--target='.length)
const localTarget = args.includes('--origin=http://127.0.0.1:18746')
if (
  args.length !== (schemaVersion === 3 ? 4 : 3)
  || !args.includes('--write')
  || !args.includes('--confirm-account=production-zero-balance')
  || !!targetFile === localTarget
) {
  console.log(
    'Usage: node scripts/ios/home-sync-smoke.mjs (--origin=http://127.0.0.1:18746 | --target=/private/preview-receipt.json) --write --confirm-account=production-zero-balance [--schema=3]',
  )
  process.exit(0)
}
const previewTarget = targetFile ? await readPreviewTarget(targetFile) : undefined
const origin = previewTarget?.origin ?? 'http://127.0.0.1:18746'
const homeEndpoint = `${origin}/api/home-screen${schemaVersion === 3 ? '?schema=3' : ''}`
const root = join(homedir(), '.config/yunlefun')
const path = join(root, 'test-accounts.json')
assert.equal((await stat(path)).mode & 0o077, 0)
const account = JSON.parse(await readFile(path, 'utf8')).accounts.find(
  a => a.id === 'production-zero-balance',
)
assert.equal(account?.username, 'ylf_prod_zero')
assert.equal(account.environment, 'production')
const authOrigin = 'https://yunlefun-8g7ybcxc7345c490.api.tcloudbasegateway.com'
const device = randomUUID()
async function request(url, { token, method = 'GET', fields } = {}) {
  const response = await fetch(url, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(25000),
    headers: {
      'Accept': 'application/json',
      'x-device-id': device,
      ...(previewTarget && new URL(url).origin === origin ? previewHeaders(previewTarget) : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(fields ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(fields ? { body: JSON.stringify(fields) } : {}),
  })
  const type = response.headers.get('content-type') || ''
  if (!type.includes('application/json'))
    throw new Error('Non-JSON response')
  return {
    status: response.status,
    cache: response.headers.get('cache-control'),
    body: await response.json(),
  }
}
const login = await request(`${authOrigin}/auth/v1/signin`, {
  method: 'POST',
  fields: { username: account.username, password: account.password },
})
if (login.status !== 200)
  throw new Error(`Managed login failed: ${login.body.error}`)
const token = login.body.access_token
let baseline
let original
let last
let cleanupNeeded = false
const report = { origin, account: account.id, schemaVersion, checks: [] }
function configuration(x) {
  const { installedApps, dockApps, recentApps } = x.configuration
  const content = structuredClone({ installedApps, dockApps, recentApps, ...(schemaVersion === 3 ? { folders: x.configuration.folders, applicationSources: x.configuration.applicationSources } : {}) })
  if (schemaVersion === 3) {
    assert.ok(Array.isArray(content.folders))
    assert.ok(Array.isArray(content.applicationSources))
    content.applicationSources.sort((a, b) => a.appId < b.appId ? -1 : a.appId > b.appId ? 1 : 0)
  }
  return content
}
async function put(base, content, mutationId = randomUUID()) {
  return request(`${origin}/api/home-screen`, {
    method: 'PUT',
    token,
    fields: { schemaVersion, baseRevision: base.revision, mutationId, configuration: content },
  })
}
try {
  const profile = await request(`${authOrigin}/auth/v1/user/me`, { token })
  assert.equal(profile.status, 200)
  assert.equal(profile.body.username, account.username)
  const read = await request(homeEndpoint, { token })
  assert.equal(read.status, 200)
  assert.equal(read.cache, 'private, no-store')
  assert.equal(read.body.schemaVersion, schemaVersion)
  baseline = structuredClone(read.body)
  original = JSON.stringify(baseline)
  const backupDir = join(root, 'ios-native-validation')
  await mkdir(backupDir, { recursive: true, mode: 0o700 })
  report.backupFile = join(backupDir, `home-sync-zero-${device}.json`)
  await writeFile(report.backupFile, JSON.stringify(baseline, null, 2), { mode: 0o600, flag: 'wx' })
  report.checks.push('authenticated read and no-store')
  const catalog = await request('https://apps.yunle.fun/api/apps/public')
  const app
    = catalog.body.items.find(a => a.marketShortName === 'air-conditioner')
      || catalog.body.items.find(a => a.slug === 'air-conditioner')
  assert.ok(app?._id)
  const content = configuration(baseline)
  if (!content.installedApps.some(a => a.appId === app._id))
    content.installedApps.push({ appId: app._id })
  const mutation = randomUUID()
  cleanupNeeded = true
  const saved = await put(baseline, content, mutation)
  assert.equal(saved.status, 200)
  assert.equal(typeof saved.body.revision, 'string')
  last = saved.body
  assert.deepEqual(configuration(last), content)
  report.checks.push('real transactional write')
  const replay = await put(baseline, content, mutation)
  assert.equal(replay.status, 200)
  assert.deepEqual(replay.body, last)
  report.checks.push('lost-ack idempotent replay')
  if (schemaVersion === 3) {
    const profile = await request('https://apps.yunle.fun/api/markets/personal/YunYouJun')
    assert.equal(profile.status, 200)
    assert.equal(profile.body.ownerLogin, 'YunYouJun')
    assert.ok(profile.body.items.some(item => item._id === app._id && item.audience === 'public' && item.isPublic === true))
    const author = configuration(last)
    author.applicationSources = author.applicationSources.filter(source => source.appId !== app._id)
    author.applicationSources.push({ appId: app._id, ownerLogin: 'YunYouJun' })
    author.applicationSources.sort((a, b) => a.appId < b.appId ? -1 : a.appId > b.appId ? 1 : 0)
    const authorWrite = await put(last, author)
    assert.equal(authorWrite.status, 200)
    last = authorWrite.body
    assert.deepEqual(configuration(last), author)
    assert.deepEqual(configuration((await request(homeEndpoint, { token })).body), author)
    report.checks.push('schema 3 author source survives committed reread')

    // An older client must preserve the source it cannot represent.
    const legacy = await request(`${origin}/api/home-screen?schema=2`, { token })
    assert.equal(legacy.status, 200)
    assert.equal(legacy.body.schemaVersion, 2)
    const { updatedAt: _updatedAt, ...oldContent } = legacy.body.configuration
    assert.equal(Object.hasOwn(oldContent, 'applicationSources'), false)
    const oldWrite = await request(`${origin}/api/home-screen`, { token, method: 'PUT', fields: { schemaVersion: 2, baseRevision: legacy.body.revision, mutationId: randomUUID(), configuration: oldContent } })
    assert.equal(oldWrite.status, 200)
    last = { ...last, revision: oldWrite.body.revision }
    const preserved = await request(homeEndpoint, { token })
    assert.equal(preserved.status, 200)
    last = preserved.body
    assert.deepEqual(configuration(last), author)
    report.checks.push('schema 2 write preserves author sources and folders')

    const market = configuration(last)
    market.applicationSources = market.applicationSources.filter(source => source.appId !== app._id)
    const sourceBase = last
    const marketWrite = await put(sourceBase, market)
    assert.equal(marketWrite.status, 200)
    last = marketWrite.body
    assert.notEqual(last.revision, sourceBase.revision)
    assert.deepEqual(configuration(last), market)
    assert.deepEqual(configuration((await request(homeEndpoint, { token })).body), market)
    const staleSource = await put(sourceBase, author)
    assert.equal(staleSource.status, 409)
    assert.equal(staleSource.body.data?.code, 'HOME_CONFLICT')
    report.checks.push('explicit market source clears selection and stale author revision conflicts')
  }
  const concurrentBase = configuration(last)
  const contenders = [
    { ...concurrentBase, dockApps: [{ appId: app._id }] },
    { ...concurrentBase, dockApps: [] },
  ]
  if (JSON.stringify(contenders[0]) === JSON.stringify(contenders[1]))
    throw new Error('Invalid concurrent fixture')
  const outcomes = await Promise.all(contenders.map(c => put(last, c)))
  assert.deepEqual(outcomes.map(r => r.status).sort(), [200, 409])
  last = outcomes.find(r => r.status === 200).body
  assert.equal(outcomes.find(r => r.status === 409).body.data?.code, 'HOME_CONFLICT')
  report.checks.push('concurrent one-winner conflict')
  const reread = await request(homeEndpoint, { token })
  assert.equal(reread.status, 200)
  assert.deepEqual(reread.body, last)
  report.checks.push('read after committed write')
  const stale = await put(baseline, content)
  assert.equal(stale.status, 409)
  report.checks.push('stale revision rejected')
  assert.equal(JSON.stringify(baseline), original)
}
finally {
  try {
    if (cleanupNeeded && baseline) {
      const current = await request(homeEndpoint, { token })
      if (last && current.status === 200 && current.body.revision === last.revision) {
        const restored = await put(last, configuration(baseline))
        assert.equal(restored.status, 200)
        assert.deepEqual(configuration(restored.body), configuration(baseline))
        const verified = await request(homeEndpoint, { token })
        assert.equal(verified.status, 200)
        assert.deepEqual(configuration(verified.body), configuration(baseline))
        report.restoredCloudContent = true
      }
      else if (
        current.status === 200
        && JSON.stringify(configuration(current.body)) === JSON.stringify(configuration(baseline))
      ) {
        report.restoredCloudContent = true
      }
      else {
        report.restoredCloudContent = false
        report.cleanup = 'Concurrent state changed; retained backup without overwriting it'
      }
      assert.equal(report.restoredCloudContent, true, 'Keep the recovery baseline when cleanup cannot be verified')
    }
  }
  finally {
    const signout = await request(`${authOrigin}/auth/v1/user/signout`, { token, method: 'POST', fields: {} })
    report.signOut = signout.status === 200
    const reportPath = schemaVersion === 3 ? '/tmp/yunlefun-home-sync-live-schema3-report.json' : '/tmp/yunlefun-home-sync-live-report.json'
    await writeFile(reportPath, JSON.stringify(report, null, 2), {
      mode: 0o600,
    })
    console.log(JSON.stringify(report))
    assert.equal(report.signOut, true, 'The validation session must be revoked')
  }
}
