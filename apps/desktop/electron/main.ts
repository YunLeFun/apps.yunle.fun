import type { IpcMainInvokeEvent, WebContents } from 'electron'
import type { CatalogEntry, DesktopState, ViewportBounds } from '../shared/desktop'
import { createHash } from 'node:crypto'
import path from 'node:path'
import process from 'node:process'
import { app, BaseWindow, ipcMain, nativeTheme, session, WebContentsView } from 'electron'
import squirrelStartup from 'electron-squirrel-startup'
import { GUEST_ENVIRONMENT, SHELL_ORIGIN, SHELL_REQUEST, SHELL_STATE } from '../shared/desktop'
import { PublicCatalog } from './catalog'
import { clampViewport, isAllowedPage, isLoopbackOrigin, parseRequest } from './policies'
import { registerScheme, serveShell } from './protocol'
import { initializeUpdates } from './updates'

const securePreferences = {
  contextIsolation: true,
  sandbox: true,
  nodeIntegration: false,
  nodeIntegrationInWorker: false,
  nodeIntegrationInSubFrames: false,
  webSecurity: true,
}
let window: BaseWindow | undefined
let shellView: WebContentsView | undefined
let guest: WebContentsView | undefined
let viewport: ViewportBounds | null = null
let shellNavigating = true
let currentApp: CatalogEntry | undefined
let catalog: PublicCatalog
let updatesReady = false
let state: DesktopState
const devOrigin = !app.isPackaged ? process.env.YUNLE_DESKTOP_DEV_ORIGIN : undefined
if (devOrigin && !isLoopbackOrigin(devOrigin))
  throw new Error('The development origin must be an HTTP loopback origin')
// Test origins are explicitly opt-in and are never honored in packaged apps.
const testOrigin = !app.isPackaged && process.env.YUNLE_DESKTOP_E2E === '1'
  ? process.env.YUNLE_DESKTOP_TEST_ORIGIN
  : undefined
if (testOrigin && !isLoopbackOrigin(testOrigin))
  throw new Error('The test origin must be an HTTP loopback origin')

function sendState() {
  if (shellView && !shellView.webContents.isDestroyed())
    shellView.webContents.send(SHELL_STATE, state)
}
function isCurrentFrame(event: IpcMainInvokeEvent, contents: WebContents, origin: string) {
  return !contents.isDestroyed() && event.sender === contents
    && event.senderFrame === contents.mainFrame && event.senderFrame.origin === origin
}
function requireShell(event: IpcMainInvokeEvent) {
  if (!shellView || !isCurrentFrame(event, shellView.webContents, devOrigin || SHELL_ORIGIN))
    throw new Error('Forbidden: trusted shell main frame required')
}
function closeGuest() {
  if (guest) {
    if (window && !window.isDestroyed())
      window.contentView.removeChildView(guest)
    guest.webContents.close()
    guest = undefined
  }
  currentApp = undefined
  state.guest = { open: false, appId: '', title: '', url: '', loading: false, canGoBack: false, canGoForward: false, error: '' }
  sendState()
}
function layout() {
  if (!window || window.isDestroyed() || !shellView || shellView.webContents.isDestroyed())
    return
  const size = window.getContentBounds()
  shellView.setBounds({ x: 0, y: 0, width: size.width, height: size.height })
  if (guest && viewport) {
    const bounds = clampViewport(viewport, size, shellView.webContents.getZoomFactor())
    guest.setBounds(bounds)
    guest.setVisible(bounds.width > 0 && bounds.height > 0)
  }
  else { guest?.setVisible(false) }
}
function clearViewport() {
  viewport = null
  guest?.setVisible(false)
}
function updateNativeAppearance() {
  const background = nativeTheme.shouldUseDarkColors ? '#242426' : '#f5f5f7'
  if (window && !window.isDestroyed())
    window.setBackgroundColor(background)
  if (shellView && !shellView.webContents.isDestroyed())
    shellView.setBackgroundColor(process.platform === 'darwin' ? '#00000000' : background)
}
function refreshGuest() {
  if (!guest || guest.webContents.isDestroyed())
    return
  const contents = guest.webContents
  state.guest = {
    open: true,
    appId: currentApp?.id || '',
    title: contents.getTitle(),
    url: contents.getURL(),
    loading: contents.isLoading(),
    canGoBack: contents.navigationHistory.canGoBack(),
    canGoForward: contents.navigationHistory.canGoForward(),
    error: state.guest.error,
  }
  sendState()
}
async function openApp(id: string) {
  const entry = catalog.get(id)
  if (guest && currentApp?.id === entry.id) {
    guest.webContents.focus()
    return
  }
  closeGuest()
  const origin = new URL(entry.websiteUrl).origin
  const key = createHash('sha256').update(`${entry.slug}:${origin}`).digest('hex').slice(0, 32)
  const appSession = session.fromPartition(`persist:yunle-app-${key}`)
  appSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false))
  appSession.setPermissionCheckHandler(() => false)
  appSession.setDevicePermissionHandler(() => false)
  if (!appSession.listenerCount('will-download'))
    appSession.on('will-download', event => event.preventDefault())
  guest = new WebContentsView({ webPreferences: {
    ...securePreferences,
    session: appSession,
    preload: path.join(__dirname, 'preload.guest.cjs'),
  } })
  currentApp = entry
  state.guest.open = true
  state.guest.error = ''
  const view = guest
  const contents = view.webContents
  // An ordinary page never inherits the shell protocol or the shell bridge.
  contents.on('will-navigate', (event, url) => {
    if (!isAllowedPage(url, [origin]))
      event.preventDefault()
  })
  contents.on('will-redirect', (event, url) => {
    if (!isAllowedPage(url, [origin]))
      event.preventDefault()
  })
  contents.setWindowOpenHandler(() => ({ action: 'deny' }))
  const refreshCurrent = () => {
    if (guest === view)
      refreshGuest()
  }
  contents.on('did-start-loading', refreshCurrent)
  contents.on('did-stop-loading', refreshCurrent)
  contents.on('did-navigate', refreshCurrent)
  contents.on('did-navigate-in-page', refreshCurrent)
  contents.on('page-title-updated', refreshCurrent)
  contents.on('render-process-gone', () => {
    if (guest !== view)
      return
    state.guest.error = '页面已停止，请重新加载'
    sendState()
  })
  contents.on('did-fail-load', (_event, code, _description, _url, isMainFrame) => {
    if (guest === view && isMainFrame && code !== -3) {
      state.guest.error = '页面加载失败，请检查网络后重试'
      sendState()
    }
  })
  window!.contentView.addChildView(view)
  layout()
  await contents.loadURL(entry.websiteUrl).catch(() => undefined)
  if (guest === view)
    refreshGuest()
}

async function createWindow() {
  viewport = null
  shellNavigating = true
  window = new BaseWindow({
    width: 1280,
    height: 840,
    minWidth: 800,
    minHeight: 600,
    title: '云乐坊',
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#242426' : '#f5f5f7',
    ...(process.platform === 'darwin'
      ? { titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 18, y: 20 }, vibrancy: 'sidebar', visualEffectState: 'followWindow' }
      : {}),
    ...(process.platform === 'linux'
      ? { icon: path.join(app.getAppPath(), app.isPackaged ? '.output/public' : 'public', 'pwa-512x512.png') }
      : {}),
  })
  const shellSession = session.fromPartition('persist:yunle-shell')
  shellSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false))
  shellSession.setPermissionCheckHandler(() => false)
  shellSession.setDevicePermissionHandler(() => false)
  shellSession.on('will-download', event => event.preventDefault())
  if (!devOrigin)
    await serveShell(shellSession, path.join(app.getAppPath(), '.output/public'))
  shellView = new WebContentsView({ webPreferences: {
    ...securePreferences,
    session: shellSession,
    preload: path.join(__dirname, 'preload.shell.cjs'),
  } })
  updateNativeAppearance()
  window.contentView.addChildView(shellView)
  layout()
  window.on('resize', layout)
  shellView.webContents.on('zoom-changed', layout)
  const shellContents = shellView.webContents
  shellContents.on('did-start-navigation', (details) => {
    if (shellView?.webContents === shellContents && details.isMainFrame && !details.isSameDocument) {
      shellNavigating = true
      clearViewport()
    }
  })
  shellContents.on('render-process-gone', () => {
    if (shellView?.webContents === shellContents) {
      shellNavigating = true
      clearViewport()
    }
  })
  shellContents.on('did-finish-load', () => {
    if (shellView?.webContents === shellContents) {
      clearViewport()
      shellNavigating = false
    }
  })
  shellView.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  shellView.webContents.on('will-navigate', (event, url) => {
    try {
      const target = new URL(url)
      const origin = target.protocol === 'app:' ? `${target.protocol}//${target.host}` : target.origin
      if (origin !== (devOrigin || SHELL_ORIGIN))
        event.preventDefault()
    }
    catch { event.preventDefault() }
  })
  window.on('closed', () => {
    viewport = null
    closeGuest()
    shellView?.webContents.close()
    shellView = undefined
    window = undefined
  })
  await shellView.webContents.loadURL(`${devOrigin || SHELL_ORIGIN}/`)
  // eslint-disable-next-line no-console
  console.info(`[desktop] ready: ${devOrigin || SHELL_ORIGIN}`)
}

registerScheme()
nativeTheme.on('updated', updateNativeAppearance)
if (squirrelStartup) {
  app.quit()
}
else if (!app.requestSingleInstanceLock()) {
  app.quit()
}
else {
  app.on('second-instance', () => {
    if (window?.isMinimized())
      window.restore()
    window?.focus()
  })
  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin')
      app.quit()
  })
  app.on('activate', () => {
    if (!window)
      void createWindow()
  })
  app.whenReady().then(async () => {
    state = {
      version: app.getVersion(),
      platform: process.platform,
      electron: process.versions.electron,
      chromium: process.versions.chrome,
      catalog: { apps: [], source: 'snapshot', loading: false, error: '', updatedAt: null },
      guest: { open: false, appId: '', title: '', url: '', loading: false, canGoBack: false, canGoForward: false, error: '' },
      updates: { status: 'disabled', message: '桌面端自动更新将在正式发布后启用' },
    }
    catalog = new PublicCatalog({
      cacheFile: path.join(app.getPath('userData'), 'public-catalog.json'),
      endpoint: testOrigin ? `${testOrigin}/api/apps/public` : undefined,
      testOrigin,
      onChange(value) {
        state.catalog = value
        if (currentApp) {
          const entry = value.apps.find(item => item.slug === currentApp?.slug)
          if (!entry?.available || entry.websiteUrl !== currentApp.websiteUrl) {
            closeGuest()
          }
          else {
            // Snapshot IDs use the slug; online IDs use the database document.
            // Updating metadata must not discard the current page or session.
            currentApp = entry
            state.guest.appId = entry.id
          }
        }
        sendState()
      },
    })
    state.catalog = catalog.state
    await catalog.restore()
    ipcMain.handle(SHELL_REQUEST, async (event, input: unknown) => {
      requireShell(event)
      const request = parseRequest(input)
      switch (request.type) {
        case 'refresh-catalog':
          await catalog.refresh()
          break
        case 'open-app':
          await openApp(request.appId)
          break
        case 'guest-command':
          if (request.command === 'close') {
            closeGuest()
          }
          else if (guest) {
            const history = guest.webContents.navigationHistory
            if (request.command === 'back' && history.canGoBack()) {
              history.goBack()
            }
            else if (request.command === 'forward' && history.canGoForward()) {
              history.goForward()
            }
            else if (request.command === 'reload') {
              state.guest.error = ''
              guest.webContents.reload()
            }
          }
          break
        case 'viewport':
          if (request.bounds === null) {
            clearViewport()
          }
          else if (!shellNavigating) {
            viewport = request.bounds
            layout()
          }
          break
        case 'theme':
          nativeTheme.themeSource = request.preference
          break
        case 'check-updates':
          if (updatesReady && state.updates.status !== 'checking')
            autoCheckUpdates()
          break
      }
      return state
    })
    ipcMain.handle(GUEST_ENVIRONMENT, (event) => {
      const origin = currentApp ? new URL(currentApp.websiteUrl).origin : ''
      if (!guest || !isCurrentFrame(event, guest.webContents, origin))
        throw new Error('Forbidden: current guest main frame required')
      return { platform: process.platform, version: 1, appId: currentApp?.id }
    })
    await createWindow()
    void catalog.refresh()
    updatesReady = await initializeUpdates((updates) => {
      state.updates = updates
      sendState()
    })
  }).catch((error) => {
    console.error(error)
    app.exit(1)
  })
}

function autoCheckUpdates() {
  import('electron').then(({ autoUpdater }) => autoUpdater.checkForUpdates()).catch((error) => {
    console.error('[updates]', error)
    state.updates = { status: 'error', message: '暂时无法检查更新' }
    sendState()
  })
}
