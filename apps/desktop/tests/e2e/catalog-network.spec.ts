import type { ElectronApplication } from '@playwright/test'
import fs from 'node:fs/promises'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { _electron as electron, expect, test } from '@playwright/test'
import { CATALOG_NETWORK_PARTITION } from '../../electron/catalog'
import { cleanupElectronTest } from './electron-cleanup'

// eslint-disable-next-line no-empty-pattern -- Playwright requires destructured fixture arguments.
test('catalog uses Chromium proxy routing while omitting cookies and refusing redirects', async ({}, testInfo) => {
  let origin = ''
  let redirect = false
  let proxyHits = 0
  let redirectHits = 0
  const requestCookies: (string | undefined)[] = []
  const server = http.createServer((request, response) => {
    if (request.url?.endsWith('/redirect-target')) {
      redirectHits++
      response.end('Unexpected redirect')
      return
    }
    // Direct requests cannot obtain a catalog. The HTTP proxy receives an absolute URL.
    if (request.url !== `${origin}/api/apps/public`) {
      response.writeHead(503)
      response.end('Direct transport unavailable')
      return
    }
    proxyHits++
    requestCookies.push(request.headers.cookie)
    if (redirect) {
      response.writeHead(302, { Location: `${origin}/redirect-target` })
      response.end()
      return
    }
    response.writeHead(200, { 'Content-Type': 'application/json', 'Set-Cookie': 'response-cookie=fixture; Path=/' })
    response.end(JSON.stringify({ items: [{
      _id: 'proxy-app',
      slug: 'proxy-app',
      name: '代理目录应用',
      websiteUrl: `${origin}/guest`,
      isPublic: true,
      audience: 'public',
      status: 'approved',
      publicationStatus: 'published',
    }] }))
  })
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-catalog-network-'))
  let application: ElectronApplication | undefined
  let failed = false
  try {
    const env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === 'string'))
    for (const key of ['ELECTRON_RUN_AS_NODE', 'YUNLE_DESKTOP_DEV_ORIGIN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy', 'NODE_OPTIONS', 'NODE_USE_ENV_PROXY'])
      delete env[key]
    env.YUNLE_DESKTOP_E2E = '1'
    env.YUNLE_DESKTOP_TEST_ORIGIN = origin
    application = await electron.launch({ args: [path.resolve('.'), `--user-data-dir=${userData}`], env })
    await application.context().route('https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/**', route => route.abort())
    await application.context().tracing.start({ screenshots: true, snapshots: true, sources: true })
    const shell = await application.firstWindow()
    await shell.waitForLoadState('domcontentloaded', { timeout: 15000 })
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    await expect.poll(() => shell.evaluate(async () => (await window.desktop!.getState()).catalog.loading)).toBe(false)
    expect(await shell.evaluate(async () => (await window.desktop!.getState()).catalog.source)).toBe('snapshot')
    expect(proxyHits).toBe(0)

    // This changes only the disposable app's catalog session, never OS/shell/guest proxies.
    await application.evaluate(async ({ session }, config) => {
      const transport = session.fromPartition(config.partition)
      await transport.cookies.set({ url: config.origin, name: 'session-cookie', value: 'fixture' })
      await transport.setProxy({ mode: 'fixed_servers', proxyRules: config.origin, proxyBypassRules: '<-loopback>' })
    }, { partition: CATALOG_NETWORK_PARTITION, origin })
    const online = await shell.evaluate(async () => (await window.desktop!.refreshCatalog()).catalog)
    expect(online.source).toBe('online')
    expect(online.error).toBe('')
    expect(online.apps.map(app => app.slug)).toEqual(['proxy-app'])
    expect(proxyHits).toBeGreaterThan(0)
    expect(requestCookies.every(cookie => cookie === undefined)).toBe(true)
    const cookies = await application.evaluate(async ({ session }, config) => {
      const values = await session.fromPartition(config.partition).cookies.get({ url: config.origin })
      return values.map(cookie => cookie.name)
    }, { partition: CATALOG_NETWORK_PARTITION, origin })
    expect(cookies).toEqual(['session-cookie'])

    redirect = true
    const refused = await shell.evaluate(async () => (await window.desktop!.refreshCatalog()).catalog)
    expect(refused.error).toBeTruthy()
    expect(refused.apps.map(app => app.slug)).toEqual(['proxy-app'])
    expect(redirectHits).toBe(0)
  }
  catch (error) {
    failed = true
    throw error
  }
  finally {
    await cleanupElectronTest({ application, testInfo, server, userData, failed })
  }
})
