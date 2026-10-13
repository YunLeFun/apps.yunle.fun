import type { ElectronApplication } from '@playwright/test'
import fs from 'node:fs/promises'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import { _electron as electron, expect, test } from '@playwright/test'

test('shared product catalog, static routes, restricted bridges, application isolation and cleanup', async () => {
  let published = true
  let firstDocumentId = 'first'
  let origin = ''
  const server = http.createServer((request, response) => {
    if (request.url === '/api/apps/public') {
      response.setHeader('Content-Type', 'application/json')
      response.end(JSON.stringify({ items: published
        ? [
            { _id: firstDocumentId, slug: 'first', name: '云应用一', websiteUrl: `${origin}/first`, emoji: '🌤️', isPublic: true, audience: 'public', status: 'approved', publicationStatus: 'published' },
            { _id: 'second', slug: 'second', name: '云应用二', websiteUrl: `${origin}/second`, emoji: '🌙', isPublic: true, audience: 'public', status: 'approved', publicationStatus: 'published' },
            { _id: 'paid', slug: 'paid', name: '付费应用', websiteUrl: `${origin}/paid`, coinCost: 10, isPublic: true, audience: 'public', status: 'approved', publicationStatus: 'published' },
            { _id: 'private', slug: 'private', name: '私有应用', websiteUrl: `${origin}/private`, isPublic: false, audience: 'owner', status: 'approved', publicationStatus: 'published' },
          ]
        : [] }))
      return
    }
    response.setHeader('Content-Type', 'text/html')
    if (request.url === '/child') {
      response.end('<!doctype html><title>Child frame</title><p>Child frame</p>')
      return
    }
    const label = request.url?.startsWith('/second') ? 'Second fixture' : 'First fixture'
    response.end(`<!doctype html><html><head><title>${label}</title></head><body><h1>${label}</h1><a href="/next">Next page</a><a href="https://nuxt.com/">Outside origin</a><button onclick="window.open('/popup')">Popup</button><iframe src="/child"></iframe></body></html>`)
  })
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const address = server.address() as { port: number }
  origin = `http://127.0.0.1:${address.port}`
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-electron-test-'))
  let application: ElectronApplication | undefined
  try {
    const env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === 'string'))
    env.YUNLE_DESKTOP_TEST_ORIGIN = origin
    env.YUNLE_DESKTOP_E2E = '1'
    delete env.ELECTRON_RUN_AS_NODE
    delete env.YUNLE_DESKTOP_DEV_ORIGIN
    application = await electron.launch({ args: [path.resolve('.'), `--user-data-dir=${userData}`], env })
    const shell = await application.firstWindow()
    const errors: string[] = []
    shell.on('pageerror', error => errors.push(error.message))
    await expect(shell.getByRole('heading', { name: '云乐坊', exact: true })).toBeVisible()
    expect(shell.url()).toBe('app://shell/')
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toBeEnabled()
    await expect(shell.getByRole('button', { name: '打开付费应用' })).toBeDisabled()
    await expect(shell.getByRole('button', { name: '打开私有应用' })).toHaveCount(0)
    await expect(shell.getByRole('button', { name: '打开今天来做菜' })).toHaveCount(0)
    expect(await shell.evaluate(() => ({ node: typeof (window as any).require, ipc: typeof (window as any).ipcRenderer, bridge: window.desktop?.version })))
      .toEqual({ node: 'undefined', ipc: 'undefined', bridge: 1 })
    await shell.getByRole('link', { name: '关于云乐坊桌面端' }).click()
    await expect(shell.getByRole('heading', { name: '关于云乐坊桌面端' })).toBeVisible()
    await shell.reload()
    await expect(shell.getByRole('heading', { name: '关于云乐坊桌面端' })).toBeVisible()
    await shell.getByRole('link', { name: '返回应用目录' }).click()
    const guestPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用一', exact: true }).click()
    const guest = await guestPage
    await expect(guest.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    expect(await guest.evaluate(() => ({ node: typeof (window as any).require, desktop: typeof (window as any).desktop })))
      .toEqual({ node: 'undefined', desktop: 'undefined' })
    expect(await guest.evaluate(() => (window as any).yunleHost.getEnvironment())).toMatchObject({ appId: 'first', version: 1 })
    await expect(guest.frameLocator('iframe').getByText('Child frame', { exact: true })).toBeVisible()
    const childFrame = guest.frames().find(frame => frame.url().endsWith('/child'))!
    expect(await childFrame.evaluate(() => typeof (window as any).yunleHost)).toBe('undefined')
    await guest.evaluate(() => localStorage.setItem('isolation', 'electron-only'))
    await guest.getByRole('link', { name: 'Next page' }).click()
    await expect(shell.getByRole('button', { name: '后退' })).toBeEnabled()
    // A refreshed document ID for the same application must preserve the real
    // browsing page, history and session while updating both host surfaces.
    firstDocumentId = 'first-online-document'
    await shell.getByRole('button', { name: '刷新目录' }).click()
    await expect.poll(() => shell.evaluate(async () => (await window.desktop!.getState()).guest.appId))
      .toBe(firstDocumentId)
    expect(guest.isClosed()).toBe(false)
    expect(application.context().pages()).toHaveLength(2)
    await expect(guest).toHaveURL(`${origin}/next`)
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toHaveClass(/selected/)
    expect(await guest.evaluate(() => localStorage.getItem('isolation'))).toBe('electron-only')
    expect(await guest.evaluate(() => (window as any).yunleHost.getEnvironment())).toMatchObject({ appId: firstDocumentId })
    await shell.getByRole('button', { name: '后退' }).click()
    await expect(guest.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    await shell.getByRole('button', { name: '前进' }).click()
    await expect(guest).toHaveURL(`${origin}/next`)
    await shell.getByRole('button', { name: '后退' }).click()
    await expect(guest).toHaveURL(`${origin}/first`)
    await shell.getByRole('button', { name: '重新加载', exact: true }).click()
    await expect(guest.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    // Observe the real native navigation decision; blocked navigation has no commit.
    await application.evaluate(({ webContents }, targetOrigin) => {
      const contents = webContents.getAllWebContents().find(value => value.getURL().startsWith(targetOrigin))!
      ;(globalThis as any).__blockedNavigation = false
      contents.once('will-navigate', (event) => {
        ;(globalThis as any).__blockedNavigation = event.defaultPrevented
      })
    }, origin)
    await guest.evaluate(() => {
      location.assign('https://nuxt.com/')
    })
    await expect.poll(() => application!.evaluate(() => (globalThis as any).__blockedNavigation)).toBe(true)
    expect(guest.url()).toBe(`${origin}/first`)
    const pageCount = application.context().pages().length
    await guest.evaluate(() => {
      window.open('/popup')
    })
    expect(application.context().pages()).toHaveLength(pageCount)
    const nextGuestPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用二', exact: true }).click()
    const nextGuest = await nextGuestPage
    await expect(nextGuest.getByRole('heading', { name: 'Second fixture' })).toBeVisible()
    expect(await nextGuest.evaluate(() => localStorage.getItem('isolation'))).toBeNull()
    await shell.getByRole('button', { name: '关闭应用', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '打开你的下一个云应用' })).toBeVisible()
    await expect.poll(() => application!.context().pages().length).toBe(1)
    const restoredPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用一', exact: true }).click()
    const restored = await restoredPage
    await expect(restored).toHaveURL(`${origin}/first`)
    await expect(restored.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    expect(await restored.evaluate(() => localStorage.getItem('isolation'))).toBe('electron-only')
    await shell.getByRole('button', { name: '关闭应用', exact: true }).click()
    expect(await shell.evaluate(async () => {
      try {
        await window.desktop!.openApp('https://arbitrary.example/')
        return false
      }
      catch { return true }
    })).toBe(true)
    expect(await shell.evaluate(async () => {
      try {
        await window.desktop!.openApp('paid')
        return false
      }
      catch { return true }
    })).toBe(true)
    // A published empty list removes cached and bundled apps, closes the guest,
    // and remains empty in the main-process cache.
    const withdrawnPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用一', exact: true }).click()
    const withdrawn = await withdrawnPage
    await expect(withdrawn.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    published = false
    await shell.getByRole('button', { name: '刷新目录' }).click()
    await expect(shell.getByText('没有匹配的应用')).toBeVisible()
    await expect.poll(() => application!.context().pages().length).toBe(1)
    const cache = JSON.parse(await fs.readFile(path.join(userData, 'public-catalog.json'), 'utf8'))
    expect(cache.items).toEqual([])
    expect(errors).toEqual([])
  }
  finally {
    await application?.close()
    await new Promise<void>(resolve => server.close(() => resolve()))
    await fs.rm(userData, { recursive: true, force: true })
  }
})

test('real shared offline snapshot and catalog search remain usable when the API is unavailable', async () => {
  const server = http.createServer((_request, response) => {
    response.writeHead(503)
    response.end('Unavailable')
  })
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-offline-test-'))
  let application: ElectronApplication | undefined
  try {
    const env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === 'string'))
    env.YUNLE_DESKTOP_TEST_ORIGIN = origin
    env.YUNLE_DESKTOP_E2E = '1'
    delete env.ELECTRON_RUN_AS_NODE
    delete env.YUNLE_DESKTOP_DEV_ORIGIN
    application = await electron.launch({ args: [path.resolve('.'), `--user-data-dir=${userData}`], env })
    const shell = await application.firstWindow()
    await expect(shell.getByRole('heading', { name: '云乐坊', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开今天来做菜' })).toBeEnabled()
    await expect(shell.getByText('暂时无法刷新目录，正在使用本地快照或缓存')).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开Everything Generator' })).toHaveCount(0)
    await shell.getByRole('searchbox', { name: '搜索应用' }).fill('空调')
    await expect(shell.getByRole('button', { name: '打开云空调' })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开今天来做菜' })).toHaveCount(0)
    await shell.getByRole('searchbox', { name: '搜索应用' }).fill('')
    await shell.screenshot({ path: '/tmp/yunlefun-desktop.png' })
  }
  finally {
    await application?.close()
    await new Promise<void>(resolve => server.close(() => resolve()))
    await fs.rm(userData, { recursive: true, force: true })
  }
})
