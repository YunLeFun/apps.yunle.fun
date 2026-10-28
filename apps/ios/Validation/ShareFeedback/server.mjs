// Loopback-only acceptance server. Uses Support's real services, adapters and web build;
// replaces only its CloudBase database with the existing offline contract fixture.
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import https from 'node:https'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const [supportRoot, directory] = process.argv.slice(2)
if (!supportRoot || !directory) throw new Error('Usage: server.mjs SUPPORT_ROOT TASK_DIRECTORY')
const require = createRequire(resolve(supportRoot, 'package.json'))
const { createServer } = await import(pathToFileURL(require.resolve('vite')))
const loader = await createServer({ root: supportRoot, configFile: false, appType: 'custom', server: { middlewareMode: true } })
const load = path => loader.ssrLoadModule(resolve(supportRoot, path))
const { feedbackDatabaseFixture } = await load('apps/web/test/feedback-database-fixture.ts')
const { FeedbackDocumentStore } = await load('apps/web/server/adapters/feedback-store.ts')
const { CloudBasePrivateFeedback } = await load('apps/web/server/adapters/feedback-persistence.ts')
const { CloudBaseTicketWorkflow } = await load('apps/web/server/adapters/ticket-persistence.ts')
const { FeedbackGuestIdentityAdapter } = await load('apps/web/server/adapters/feedback-identity.ts')
const { TicketAccess } = await load('apps/web/server/adapters/ticket-access.ts')
const { PrivateFeedbackService, TicketWorkflowService, StaticAuthorizationAdapter } = await import(pathToFileURL(resolve(supportRoot, 'packages/server-core/dist/index.mjs')))
const fixture = feedbackDatabaseFixture()
const store = new FeedbackDocumentStore(fixture.database)
const tickets = new CloudBaseTicketWorkflow(store)
const secret = () => randomBytes(32).toString('hex')
const guest = new FeedbackGuestIdentityAdapter(secret(), secret(), secret())
const access = new TicketAccess(secret(), id => tickets.run(tx => tx.find(id)))
const ids = { nextId: () => `qa_${randomUUID()}`, nextTicketNumber: () => `YLS-QA-${randomUUID().slice(0, 8)}`, nextTrustSafetyReportNumber: () => `YLG-QA-${randomUUID()}` }
const clock = { now: () => new Date().toISOString() }
const service = new PrivateFeedbackService({ unitOfWork: new CloudBasePrivateFeedback(store), clock, ids, authorization: new StaticAuthorizationAdapter(), rateLimit: { consume: async () => true }, screenshotDigest: data => createHash('sha256').update(data).digest('hex') })
const workflow = new TicketWorkflowService({ unitOfWork: tickets, clock, ids, fingerprint: data => createHash('sha256').update(data).digest('hex') })
const origin = 'https://127.0.0.1:18473'
const controlKey = secret()
let failAfterCommit = false
const events = []
const cookieName = '__Host-ylf-support-guest'
const cookie = (request, name) => (request.headers.cookie ?? '').split(';').map(part => part.trim()).find(part => part.startsWith(`${name}=`))?.slice(name.length + 1)
const fail = (status, message) => { throw Object.assign(new Error(message), { status }) }
const body = async request => {
  const chunks = []; let size = 0
  for await (const part of request) { size += part.length; if (size > 4_300_000) fail(413, 'Body too large'); chunks.push(part) }
  return JSON.parse(Buffer.concat(chunks).toString() || '{}')
}
const json = (response, status, value, headers = {}) => { response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'private, no-store', ...headers }); response.end(JSON.stringify(value)) }
const persistReport = () => writeFileSync(resolve(directory, 'server-report.json'), JSON.stringify({ events, tickets: [...fixture.rows].filter(([key]) => key.startsWith('support_private_feedback/')).map(([, value]) => ({ id: value.id, category: value.category, context: value.context, description: value.description, screenshots: value.screenshots?.map(({ digest: _digest, ...metadata }) => metadata) ?? [] })), maximumTransactionOperations: fixture.maximumOperations() }, null, 2))
const server = https.createServer({ key: readFileSync(resolve(directory, 'local-key.pem')), cert: readFileSync(resolve(directory, 'local-cert.pem')) }, async (request, response) => {
  const url = new URL(request.url, origin); const path = url.pathname
  try {
    if (path.startsWith('/_validation/')) {
      if (request.headers['x-validation-key'] !== controlKey) fail(403, 'Validation key required')
      if (path.endsWith('/reset')) { events.length = 0; fixture.rows.clear(); failAfterCommit = false }
      if (path.endsWith('/fail-after-commit')) failAfterCommit = true
      persistReport(); return json(response, 200, { events, records: [...fixture.rows].filter(([key]) => key.startsWith('support_private_feedback/')).length })
    }
    if (path.startsWith('/api/')) {
      if (request.method === 'POST' && request.headers.origin !== origin) fail(403, 'Origin required')
      if (path === '/api/v1/feedback/guest' && request.method === 'POST') {
        const token = guest.issue(); events.push({ kind: 'guest' }); persistReport()
        return json(response, 200, { kind: 'guest', csrfToken: guest.csrfToken(token) }, { 'Set-Cookie': `${cookieName}=${token}; Path=/; Secure; HttpOnly; SameSite=Lax` })
      }
      if (path === '/api/v1/private-feedback' && request.method === 'POST') {
        const requester = guest.assertCsrf(cookie(request, cookieName) ?? '', request.headers['x-csrf-token'])
        const input = await body(request); const key = request.headers['idempotency-key'] ?? ''
        const receipt = await service.submit({ requester, clientId: 'support-web', productIds: ['www', 'cook', 'play', 'yunbox', 'drive', 'cms', 'advjs'] }, input, key)
        const ticket = await tickets.run(tx => tx.find(receipt.ticketId))
        events.push({ kind: 'submit', key, id: receipt.id, screenshots: input.screenshots?.length ?? 0 }); persistReport()
        if (failAfterCommit) { failAfterCommit = false; return json(response, 503, { code: 'DEPENDENCY_UNAVAILABLE' }) }
        return json(response, 200, { receipt: { ...receipt, ticketUrl: `${origin}/tickets/${ticket.id}#access=${access.issue(ticket)}` } })
      }
      const match = /^\/api\/v1\/tickets\/([\w-]+)(?:\/(.*))?$/.exec(path)
      if (match) {
        const [, id, action = ''] = match; const name = `__Host-ylf-ticket-${id}`
        if (action === 'access' && request.method === 'POST') {
          const input = await body(request); await access.verify(input.token, id)
          events.push({ kind: 'ticket-access', id }); persistReport()
          return json(response, 200, { ticketCsrf: access.csrf(input.token) }, { 'Set-Cookie': `${name}=${input.token}; Path=/; Secure; HttpOnly; SameSite=Lax` })
        }
        const token = cookie(request, name) ?? ''; const requester = await access.verify(token, id)
        const view = await workflow.requester(requester, id)
        if (!action) { events.push({ kind: 'ticket-read', id }); persistReport(); return json(response, 200, { ...view, ticketCsrf: access.csrf(token), wechat: { available: false, bound: false } }) }
        if (action.startsWith('screenshots')) {
          const item = fixture.rows.get(`support_private_feedback/${id}`); const screenshots = item?.screenshots ?? []
          const imageID = action.split('/')[1]
          if (!imageID) return json(response, 200, { items: screenshots.map(({ digest: _digest, ...metadata }) => metadata) })
          const shot = screenshots.find(image => image.id === imageID); if (!shot) fail(404, 'Image not found')
          let encoded = ''
          for (let i = 0; encoded.length < Math.ceil(shot.sizeBytes / 3) * 4; i++) encoded += fixture.rows.get(`support_feedback_screenshots/${imageID}_${i}`)?.data ?? fail(503, 'Missing chunk')
          if (createHash('sha256').update(encoded).digest('hex') !== shot.digest) fail(503, 'Invalid image digest')
          events.push({ kind: 'image-read', id, imageID }); persistReport()
          response.writeHead(200, { 'Content-Type': 'image/jpeg', 'Cache-Control': 'private, no-store' }); return response.end(Buffer.from(encoded, 'base64'))
        }
      }
      return json(response, 401, { code: 'UNAUTHENTICATED' })
    }
    // Serve the unchanged Support Nuxt build, including the real private-ticket UI.
    const upstream = http.request({ hostname: '127.0.0.1', port: 18474, path: request.url, method: request.method, headers: { ...request.headers, host: '127.0.0.1:18473', 'x-forwarded-proto': 'https' } }, proxy => { response.writeHead(proxy.statusCode, proxy.headers); proxy.pipe(response) })
    upstream.on('error', () => { if (!response.headersSent) json(response, 503, { code: 'WEB_UNAVAILABLE' }) }); request.pipe(upstream)
  } catch (error) { json(response, error.status ?? ({ UNAUTHENTICATED: 401, FORBIDDEN: 403, INVALID_INPUT: 400, NOT_FOUND: 404 }[error.code] ?? 500), { code: error.code ?? 'FIXTURE_ERROR', message: error.message }) }
})
server.listen(18473, '127.0.0.1', () => { writeFileSync(resolve(directory, 'server-control.json'), JSON.stringify({ origin, controlKey })); persistReport(); process.stdout.write('Local Share acceptance server ready\n') })
async function close() { persistReport(); server.close(); await loader.close(); process.exit(0) }
process.on('SIGTERM', close); process.on('SIGINT', close)
