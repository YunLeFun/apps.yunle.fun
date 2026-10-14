import type { ElectronApplication, TestInfo } from '@playwright/test'
import fs from 'node:fs/promises'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import { _electron as electron, expect, test } from '@playwright/test'
import { COOK_FEATURE_IMAGE_URL } from '../../shared/editorial-media'

async function nativeGuest(application: ElectronApplication, origin: string) {
  return application.evaluate(({ BaseWindow, WebContentsView }, targetOrigin) => {
    const owner = BaseWindow.getAllWindows()[0]
    const view = owner.contentView.children.find(child => child instanceof WebContentsView && child.webContents.getURL().startsWith(targetOrigin))
    if (!(view instanceof WebContentsView))
      return null
    return { id: view.webContents.id, visible: view.getVisible(), bounds: view.getBounds(), window: owner.getContentBounds() }
  }, origin)
}

async function finishElectronTrace(application: ElectronApplication | undefined, testInfo: TestInfo, failed: boolean) {
  if (!application)
    return
  try {
    if (failed || testInfo.status !== testInfo.expectedStatus) {
      const trace = testInfo.outputPath('electron-trace.zip')
      await application.context().tracing.stop({ path: trace })
      await testInfo.attach('Electron trace', { path: trace, contentType: 'application/zip' })
    }
    else {
      await application.context().tracing.stop()
    }
  }
  catch (error) {
    console.warn('Could not save Electron trace:', error)
  }
}

// eslint-disable-next-line no-empty-pattern -- Playwright requires destructured fixture arguments.
test('shared product catalog, static routes, restricted bridges, application isolation and cleanup', async ({}, testInfo) => {
  let published = true
  let firstDocumentId = 'first'
  let origin = ''
  const server = http.createServer((request, response) => {
    if (request.url === '/api/apps/public') {
      response.setHeader('Content-Type', 'application/json')
      response.end(JSON.stringify({ items: published
        ? [
            { _id: firstDocumentId, slug: 'first', name: '云应用一', category: '生活', websiteUrl: `${origin}/first`, emoji: '🌤️', isPublic: true, audience: 'public', status: 'approved', publicationStatus: 'published' },
            { _id: 'second', slug: 'second', name: '云应用二', category: '工具', websiteUrl: `${origin}/second`, emoji: '🌙', isPublic: true, audience: 'public', status: 'approved', publicationStatus: 'published' },
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
  let failed = false
  try {
    const env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === 'string'))
    env.YUNLE_DESKTOP_TEST_ORIGIN = origin
    env.YUNLE_DESKTOP_E2E = '1'
    delete env.ELECTRON_RUN_AS_NODE
    delete env.YUNLE_DESKTOP_DEV_ORIGIN
    application = await electron.launch({ args: [path.resolve('.'), `--user-data-dir=${userData}`], env })
    await application.context().route(COOK_FEATURE_IMAGE_URL, route => route.abort())
    await application.context().tracing.start({ screenshots: true, snapshots: true, sources: true })
    const shell = await application.firstWindow()
    const errors: string[] = []
    shell.on('pageerror', error => errors.push(error.message))
    await expect(shell.getByRole('heading', { name: '云乐坊', exact: true })).toBeVisible()
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    expect(shell.url()).toBe('app://shell/')
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toBeEnabled()
    await expect(shell.getByRole('button', { name: '打开付费应用' })).toBeDisabled()
    await expect(shell.getByRole('button', { name: '打开私有应用' })).toHaveCount(0)
    await expect(shell.getByRole('button', { name: '打开今天来做菜' })).toHaveCount(0)
    await expect(shell.getByRole('button', { name: '体验今天来做菜', exact: true })).toHaveCount(0)
    expect(await shell.evaluate(() => ({ node: typeof (window as any).require, ipc: typeof (window as any).ipcRenderer, bridge: window.desktop?.version })))
      .toEqual({ node: 'undefined', ipc: 'undefined', bridge: 1 })
    await shell.getByRole('combobox', { name: '外观', exact: true }).selectOption('dark')
    await expect.poll(() => application!.evaluate(({ nativeTheme }) => ({ source: nativeTheme.themeSource, dark: nativeTheme.shouldUseDarkColors })))
      .toEqual({ source: 'dark', dark: true })
    await expect(shell.locator('html')).toHaveClass(/dark/)
    await shell.getByRole('combobox', { name: '外观', exact: true }).selectOption('light')
    await expect.poll(() => application!.evaluate(({ nativeTheme }) => ({ source: nativeTheme.themeSource, dark: nativeTheme.shouldUseDarkColors })))
      .toEqual({ source: 'light', dark: false })
    await expect(shell.locator('html')).not.toHaveClass(/dark/)
    await shell.getByRole('combobox', { name: '外观', exact: true }).selectOption('system')
    await expect.poll(() => application!.evaluate(({ nativeTheme }) => nativeTheme.themeSource)).toBe('system')
    const categoryNavigation = shell.getByRole('navigation', { name: '应用分类' })
    const categoryCounts = await categoryNavigation.locator('.category-count').allTextContents()
    expect(categoryCounts).toEqual(['1', '1', '1'])
    await shell.getByRole('searchbox', { name: '搜索应用' }).fill('second')
    await expect(shell.getByRole('heading', { name: '搜索结果', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开云应用二', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toHaveCount(0)
    expect(await categoryNavigation.locator('.category-count').allTextContents()).toEqual(categoryCounts)
    await categoryNavigation.getByRole('button', { name: '生活方式', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '生活方式', exact: true })).toBeVisible()
    await expect(shell.getByRole('searchbox', { name: '搜索应用' })).toHaveValue('')
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开云应用二', exact: true })).toHaveCount(0)
    expect(await categoryNavigation.locator('.category-count').allTextContents()).toEqual(categoryCounts)
    await shell.getByRole('button', { name: '最近打开', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '还没有最近打开的应用', exact: true })).toBeVisible()
    await shell.getByRole('button', { name: '探索', exact: true }).click()
    await shell.getByRole('link', { name: '关于云乐坊桌面端' }).click()
    await expect(shell.getByRole('heading', { name: '关于云乐坊桌面端' })).toBeVisible()
    await shell.reload()
    await expect(shell.getByRole('heading', { name: '关于云乐坊桌面端' })).toBeVisible()
    await shell.getByRole('link', { name: '返回应用目录' }).click()
    const guestPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用一', exact: true }).click()
    const guest = await guestPage
    await expect(guest.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ visible: true })
    const firstViewId = (await nativeGuest(application, origin))!.id
    expect(await guest.evaluate(() => ({ node: typeof (window as any).require, desktop: typeof (window as any).desktop })))
      .toEqual({ node: 'undefined', desktop: 'undefined' })
    expect(await guest.evaluate(() => (window as any).yunleHost.getEnvironment())).toMatchObject({ appId: 'first', version: 1 })
    await expect(guest.frameLocator('iframe').getByText('Child frame', { exact: true })).toBeVisible()
    const childFrame = guest.frames().find(frame => frame.url().endsWith('/child'))!
    expect(await childFrame.evaluate(() => typeof (window as any).yunleHost)).toBe('undefined')
    await guest.evaluate(() => localStorage.setItem('isolation', 'electron-only'))
    await guest.getByRole('link', { name: 'Next page' }).click()
    await expect(guest).toHaveURL(`${origin}/next`)
    await expect(shell.getByRole('button', { name: '后退' })).toBeEnabled()
    await guest.evaluate(() => {
      ;(window as any).__sessionMarker = 'same-live-document'
    })
    await shell.getByRole('button', { name: '返回目录', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: false })
    expect(guest.isClosed()).toBe(false)
    await expect(guest).toHaveURL(`${origin}/next`)
    await shell.getByRole('button', { name: '最近打开', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '最近打开', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toBeEnabled()
    await expect(shell.getByRole('button', { name: '打开云应用二', exact: true })).toHaveCount(0)
    // A refreshed document ID for the same application must preserve the real
    // browsing page, history and session while updating both host surfaces.
    firstDocumentId = 'first-online-document'
    await shell.getByRole('button', { name: '刷新目录' }).click()
    await expect.poll(() => shell.evaluate(async () => (await window.desktop!.getState()).guest.appId))
      .toBe(firstDocumentId)
    expect(guest.isClosed()).toBe(false)
    expect(application.context().pages()).toHaveLength(2)
    await expect(guest).toHaveURL(`${origin}/next`)
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toBeEnabled()
    await shell.getByRole('button', { name: '打开云应用一', exact: true }).click()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: true })
    await expect(shell.getByRole('button', { name: '继续使用云应用一', exact: true })).toHaveClass(/selected/)
    expect(await guest.evaluate(() => (window as any).__sessionMarker)).toBe('same-live-document')
    expect(await guest.evaluate(() => localStorage.getItem('isolation'))).toBe('electron-only')
    expect(await guest.evaluate(() => (window as any).yunleHost.getEnvironment())).toMatchObject({ appId: firstDocumentId })
    await shell.getByRole('link', { name: '关于云乐坊桌面端' }).click()
    await expect(shell.getByRole('heading', { name: '关于云乐坊桌面端' })).toBeVisible()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: false })
    await shell.reload()
    await expect(shell.getByRole('heading', { name: '关于云乐坊桌面端' })).toBeVisible()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: false })
    await shell.getByRole('link', { name: '返回应用目录' }).click()
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    await shell.getByRole('button', { name: '继续使用云应用一', exact: true }).click()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: true })
    // A document reload does not call Vue unmount hooks. Main must hide its
    // retained guest before the reloaded renderer defaults to exploration.
    for (let reload = 0; reload < 3; reload++) {
      await shell.reload()
      await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
      await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: false })
      if (reload < 2) {
        await shell.getByRole('button', { name: '继续使用云应用一', exact: true }).click()
        await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: true })
      }
    }
    await shell.getByRole('button', { name: '最近打开', exact: true }).click()
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toBeEnabled()
    await shell.getByRole('button', { name: '继续使用云应用一', exact: true }).click()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: true })
    await expect(guest).toHaveURL(`${origin}/next`)
    expect(await guest.evaluate(() => (window as any).__sessionMarker)).toBe('same-live-document')
    expect(await guest.evaluate(() => localStorage.getItem('isolation'))).toBe('electron-only')
    await expect(shell.getByRole('button', { name: '后退' })).toBeEnabled()
    for (const zoom of [0.75, 1.5, 1]) {
      await application.evaluate(({ BaseWindow, webContents }, zoomFactor) => {
        BaseWindow.getAllWindows()[0].setContentSize(960, 640)
        webContents.getAllWebContents().find(contents => contents.getURL().startsWith('app://shell'))!.setZoomFactor(zoomFactor)
      }, zoom)
      await expect.poll(async () => {
        const native = await nativeGuest(application!, origin)
        const toolbar = await shell.locator('.guest-toolbar').boundingBox()
        return !!native?.visible && native.id === firstViewId && !!toolbar
          && native.bounds.y >= 52 && native.bounds.y >= Math.round((toolbar.y + toolbar.height) * zoom)
          && native.bounds.x >= 0 && native.bounds.width > 0 && native.bounds.height > 0
          && native.bounds.x + native.bounds.width <= native.window.width
          && native.bounds.y + native.bounds.height <= native.window.height
      }).toBe(true)
    }
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
    await shell.getByRole('button', { name: '返回目录', exact: true }).click()
    await expect.poll(() => nativeGuest(application!, origin)).toMatchObject({ id: firstViewId, visible: false })
    const nextGuestPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用二', exact: true }).click()
    const nextGuest = await nextGuestPage
    await expect(nextGuest.getByRole('heading', { name: 'Second fixture' })).toBeVisible()
    expect(await nextGuest.evaluate(() => localStorage.getItem('isolation'))).toBeNull()
    expect(guest.isClosed()).toBe(true)
    const secondViewId = (await nativeGuest(application, origin))!.id
    await shell.getByRole('button', { name: '关闭应用', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    await expect.poll(() => application!.context().pages().length).toBe(1)
    expect(await nativeGuest(application, origin)).toBeNull()
    expect(nextGuest.isClosed()).toBe(true)
    const restoredPage = application.context().waitForEvent('page')
    await shell.getByRole('button', { name: '打开云应用一', exact: true }).click()
    const restored = await restoredPage
    await expect(restored).toHaveURL(`${origin}/first`)
    await expect(restored.getByRole('heading', { name: 'First fixture' })).toBeVisible()
    expect(await restored.evaluate(() => localStorage.getItem('isolation'))).toBe('electron-only')
    expect(await restored.evaluate(() => (window as any).__sessionMarker)).toBeUndefined()
    const restoredId = (await nativeGuest(application, origin))!.id
    expect(restoredId).not.toBe(firstViewId)
    expect(restoredId).not.toBe(secondViewId)
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
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    await expect(shell.getByRole('heading', { name: '没有找到应用', exact: true })).toBeVisible()
    await expect.poll(() => application!.context().pages().length).toBe(1)
    expect(await nativeGuest(application, origin)).toBeNull()
    await shell.getByRole('button', { name: '最近打开', exact: true }).click()
    await expect(shell.getByRole('button', { name: '打开云应用一', exact: true })).toHaveCount(0)
    await expect(shell.getByRole('button', { name: '打开云应用二', exact: true })).toHaveCount(0)
    const cache = JSON.parse(await fs.readFile(path.join(userData, 'public-catalog.json'), 'utf8'))
    expect(cache.items).toEqual([])
    expect(errors).toEqual([])
  }
  catch (error) {
    failed = true
    throw error
  }
  finally {
    await finishElectronTrace(application, testInfo, failed)
    await application?.close()
    await new Promise<void>(resolve => server.close(() => resolve()))
    await fs.rm(userData, { recursive: true, force: true })
  }
})

// eslint-disable-next-line no-empty-pattern -- Playwright requires destructured fixture arguments.
test('real shared offline snapshot and catalog search remain usable when the API is unavailable', async ({}, testInfo) => {
  const server = http.createServer((_request, response) => {
    response.writeHead(503)
    response.end('Unavailable')
  })
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-offline-test-'))
  let application: ElectronApplication | undefined
  let failed = false
  try {
    const env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === 'string'))
    env.YUNLE_DESKTOP_TEST_ORIGIN = origin
    env.YUNLE_DESKTOP_E2E = '1'
    delete env.ELECTRON_RUN_AS_NODE
    delete env.YUNLE_DESKTOP_DEV_ORIGIN
    application = await electron.launch({ args: [path.resolve('.'), `--user-data-dir=${userData}`], env })
    await application.context().tracing.start({ screenshots: true, snapshots: true, sources: true })
    // Block decorative media before opening the page so offline behavior never
    // depends on the public bucket responding successfully.
    await application.context().route(COOK_FEATURE_IMAGE_URL, route => route.abort())
    const shell = await application.firstWindow()
    const errors: string[] = []
    shell.on('pageerror', error => errors.push(error.message))
    let bannerFailures = 0
    await shell.route(COOK_FEATURE_IMAGE_URL, (route) => {
      bannerFailures++
      return route.abort()
    })
    await shell.reload()
    await expect(shell.getByRole('heading', { name: '云乐坊', exact: true })).toBeVisible()
    await expect(shell.getByRole('heading', { name: '探索', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '体验今天来做菜', exact: true })).toBeEnabled()
    await expect.poll(() => bannerFailures).toBeGreaterThan(0)
    await expect(shell.getByRole('heading', { name: '今天，吃点什么？', exact: true })).toBeVisible()
    await expect(shell.locator('.feature-art')).toHaveCount(0)
    await expect(shell.getByText('暂时无法刷新目录，正在使用本地快照或缓存')).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开Everything Generator' })).toHaveCount(0)
    await shell.getByRole('button', { name: '全部应用', exact: true }).click()
    await expect(shell.getByRole('heading', { name: '全部应用', exact: true })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开今天来做菜', exact: true })).toBeEnabled()
    await shell.getByRole('searchbox', { name: '搜索应用' }).fill('空调')
    await expect(shell.getByRole('button', { name: '打开云空调' })).toBeVisible()
    await expect(shell.getByRole('button', { name: '打开今天来做菜' })).toHaveCount(0)
    await shell.getByRole('searchbox', { name: '搜索应用' }).fill('')
    const categoryNavigation = shell.getByRole('navigation', { name: '应用分类' })
    for (const name of ['生活', '工具', '设计', '整活', '插件', '应用'])
      await expect(categoryNavigation.getByRole('button', { name, exact: true })).toHaveCount(0)
    await categoryNavigation.getByRole('button', { name: '创意设计', exact: true }).click()
    await expect(shell.getByRole('button', { name: '打开Char Dust', exact: true })).toBeEnabled()
    await expect(shell.getByRole('button', { name: '打开今天来做菜', exact: true })).toHaveCount(0)
    await categoryNavigation.getByRole('button', { name: '游戏', exact: true }).click()
    await expect(shell.getByRole('button', { name: '打开FC 红白机', exact: true })).toBeEnabled()
    await expect(shell.getByRole('button', { name: '打开Char Dust', exact: true })).toHaveCount(0)
    await categoryNavigation.getByRole('button', { name: '生活方式', exact: true }).click()
    await expect(shell.getByRole('button', { name: '打开今天来做菜', exact: true })).toBeEnabled()
    await shell.getByRole('button', { name: '全部应用', exact: true }).click()

    for (const { appearance, width, height } of [
      { appearance: 'dark', width: 1280, height: 840 },
      { appearance: 'light', width: 1280, height: 840 },
      { appearance: 'dark', width: 800, height: 600 },
      { appearance: 'light', width: 800, height: 600 },
    ] as const) {
      await application.evaluate(({ BaseWindow }, size) => {
        BaseWindow.getAllWindows()[0].setContentSize(size.width, size.height)
      }, { width, height })
      await shell.getByRole('combobox', { name: '外观', exact: true }).selectOption(appearance)
      await expect.poll(() => application!.evaluate(({ nativeTheme }) => ({ source: nativeTheme.themeSource, dark: nativeTheme.shouldUseDarkColors })))
        .toEqual({ source: appearance, dark: appearance === 'dark' })
      await expect.poll(() => shell.evaluate(() => document.documentElement.classList.contains('dark')))
        .toBe(appearance === 'dark')
      // Theme classes and native colors update before the control transition
      // finishes. Capture the settled palette rather than an intermediate gray.
      await expect(shell.locator('.open-button').first()).toHaveCSS('background-color', appearance === 'dark' ? 'rgb(48, 48, 50)' : 'rgb(232, 232, 237)')
      await expect.poll(() => shell.evaluate(() => ({ width: window.innerWidth, height: window.innerHeight })))
        .toEqual({ width, height })
      await expect.poll(() => shell.evaluate(() => {
        const elements = [document.documentElement, document.body, ...Array.from(document.querySelectorAll<HTMLElement>('.desktop, .workspace, .discovery-content, .discovery-inner'))]
        return elements.every(element => element.scrollWidth <= element.clientWidth + 1)
      })).toBe(true)
      await expect(shell.getByRole('combobox', { name: '外观', exact: true })).toBeInViewport()
      await expect(shell.getByRole('link', { name: '关于云乐坊桌面端' })).toBeInViewport()
      const screenshot = testInfo.outputPath(`catalog-${appearance}-${width}x${height}.png`)
      await shell.screenshot({ path: screenshot })
      await testInfo.attach(`Catalog ${appearance} ${width}×${height}`, { path: screenshot, contentType: 'image/png' })
    }
    expect(errors).toEqual([])
  }
  catch (error) {
    failed = true
    throw error
  }
  finally {
    await finishElectronTrace(application, testInfo, failed)
    await application?.close()
    await new Promise<void>(resolve => server.close(() => resolve()))
    await fs.rm(userData, { recursive: true, force: true })
  }
})
