import type { DesktopBridge, DesktopState } from '../../shared/desktop'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createRenderer, isReadonly } from 'vue'
import { useDesktop } from '../../app/composables/useDesktop'
import { useRecentApps } from '../../app/composables/useRecentApps'

// A document-free host runs real Vue mount/unmount hooks in the Node test suite.
const renderer = createRenderer<object, object>({
  patchProp() {},
  insert() {},
  remove() {},
  createElement: () => ({}),
  createText: () => ({}),
  createComment: () => ({}),
  setText() {},
  setElementText() {},
  parentNode: () => null,
  nextSibling: () => null,
})
const cleanup: (() => void)[] = []
function withSetup<T>(setup: () => T): T {
  let result!: T
  const app = renderer.createApp({
    setup() {
      result = setup()
      return () => null
    },
  })
  app.mount({})
  cleanup.push(() => app.unmount())
  return result
}

afterEach(() => {
  cleanup.splice(0).forEach(unmount => unmount())
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

function state(guest: Partial<DesktopState['guest']> = {}): DesktopState {
  return {
    version: '0.1.0',
    platform: 'darwin',
    electron: '44',
    chromium: '152',
    catalog: { apps: [], source: 'online', loading: false, error: '', updatedAt: 1 },
    guest: { open: false, appId: '', title: '', url: '', loading: false, canGoBack: false, canGoForward: false, error: '', ...guest },
    updates: { status: 'disabled', message: '' },
  }
}

function makeBridge(initial: DesktopState) {
  const listeners = new Set<(state: DesktopState) => void>()
  const unsubscribe = vi.fn()
  const bridge = {
    version: 1,
    getState: vi.fn().mockResolvedValue(initial),
    refreshCatalog: vi.fn().mockResolvedValue(initial),
    openApp: vi.fn().mockResolvedValue(initial),
    command: vi.fn().mockResolvedValue(initial),
    setViewport: vi.fn().mockResolvedValue(initial),
    setTheme: vi.fn().mockResolvedValue(initial),
    checkUpdates: vi.fn().mockResolvedValue(initial),
    onState: vi.fn((listener: (state: DesktopState) => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
        unsubscribe()
      }
    }),
  } satisfies DesktopBridge
  return { bridge, listeners, unsubscribe }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: Error) => void
  const promise = new Promise<T>((onResolve, onReject) => {
    resolve = onResolve
    reject = onReject
  })
  return { promise, resolve, reject }
}

describe('recent apps storage boundary', () => {
  it('restores sanitized readonly slugs and writes only the promoted slug list', () => {
    const storage = {
      getItem: vi.fn().mockReturnValue(JSON.stringify(['cook', { account: 'private' }, 'https://arbitrary.example/', 'fc', 'cook'])),
      setItem: vi.fn(),
    }
    vi.stubGlobal('window', { localStorage: storage })
    const recent = withSetup(useRecentApps)
    expect(storage.getItem).toHaveBeenCalledWith('yunlefun.desktop.recent.v1')
    expect(recent.slugs.value).toEqual(['cook', 'fc'])
    expect(isReadonly(recent.slugs.value)).toBe(true)
    recent.record('fc')
    expect(recent.slugs.value).toEqual(['fc', 'cook'])
    expect(storage.setItem).toHaveBeenLastCalledWith('yunlefun.desktop.recent.v1', '["fc","cook"]')
    recent.record('https://arbitrary.example/?token=secret')
    expect(storage.setItem).toHaveBeenCalledTimes(1)
  })

  it('retains in-memory history if access or quota restrictions prevent persistence', () => {
    const storage = {
      getItem: vi.fn(() => { throw new Error('access denied') }),
      setItem: vi.fn(() => { throw new Error('quota exceeded') }),
    }
    vi.stubGlobal('window', { localStorage: storage })
    const recent = withSetup(useRecentApps)
    expect(recent.slugs.value).toEqual([])
    expect(() => recent.record('cook')).not.toThrow()
    expect(recent.slugs.value).toEqual(['cook'])
  })

  it('stores at most twenty slugs and keeps valid apps missing from the offline catalog', () => {
    const storage = { getItem: vi.fn().mockReturnValue('["pixi-painter"]'), setItem: vi.fn() }
    vi.stubGlobal('window', { localStorage: storage })
    const recent = withSetup(useRecentApps)
    expect(recent.slugs.value).toEqual(['pixi-painter'])
    for (let index = 0; index < 30; index++)
      recent.record(`app-${index}`)
    const persisted: string[] = JSON.parse(storage.setItem.mock.lastCall![1])
    expect(persisted).toHaveLength(20)
    expect(persisted[0]).toBe('app-29')
    expect(persisted[19]).toBe('app-10')
  })
})

describe('desktop requests expose authoritative results', () => {
  it('returns successful open state and unsubscribes the single bridge listener', async () => {
    const fixture = makeBridge(state())
    vi.stubGlobal('window', { desktop: fixture.bridge })
    const desktop = withSetup(useDesktop)
    await vi.waitFor(() => expect(desktop.state.value).toEqual(state()))
    const opened = state({ open: true, appId: 'cook-new-document', title: '今天来做菜' })
    fixture.bridge.openApp.mockResolvedValueOnce(opened)
    expect(await desktop.openApp('cook')).toBe(opened)
    expect(desktop.state.value).toEqual(opened)
    expect(fixture.bridge.openApp).toHaveBeenCalledWith('cook')
    expect(fixture.listeners.size).toBe(1)
    cleanup.splice(0).forEach(unmount => unmount())
    expect(fixture.unsubscribe).toHaveBeenCalledOnce()
    expect(fixture.listeners.size).toBe(0)
  })

  it('returns undefined on a bridge rejection while keeping errors visible and later requests usable', async () => {
    const initial = state()
    const { bridge } = makeBridge(initial)
    vi.stubGlobal('window', { desktop: bridge })
    const desktop = withSetup(useDesktop)
    await vi.waitFor(() => expect(desktop.state.value).toEqual(initial))
    bridge.openApp.mockRejectedValueOnce(new Error('withdrawn app'))
    expect(await desktop.openApp('cook')).toBeUndefined()
    expect(desktop.error.value).toBeTruthy()
    expect(desktop.state.value).toEqual(initial)
    const failedPage = state({ open: true, appId: 'cook', error: '页面加载失败' })
    bridge.openApp.mockResolvedValueOnce(failedPage)
    expect(await desktop.openApp('cook')).toBe(failedPage)
    expect(desktop.state.value?.guest.error).toBe('页面加载失败')
    expect(desktop.error.value).toBe('')
  })

  it('stays unavailable without a bridge and does not manufacture a successful open', async () => {
    vi.stubGlobal('window', {})
    const desktop = withSetup(useDesktop)
    expect(desktop.available.value).toBe(false)
    expect(await desktop.openApp('cook')).toBeUndefined()
    expect(desktop.state.value).toBeUndefined()
  })

  it('keeps newer pushed withdrawal state when an older open reply arrives later', async () => {
    const fixture = makeBridge(state())
    vi.stubGlobal('window', { desktop: fixture.bridge })
    const desktop = withSetup(useDesktop)
    await vi.waitFor(() => expect(desktop.state.value).toEqual(state()))
    const reply = deferred<DesktopState>()
    fixture.bridge.openApp.mockReturnValueOnce(reply.promise)
    const opening = desktop.openApp('cook')
    const withdrawn = state()
    fixture.listeners.forEach(listener => listener(withdrawn))
    reply.resolve(state({ open: true, appId: 'cook', title: '今天来做菜' }))
    expect(await opening).toBe(withdrawn)
    expect(desktop.state.value?.guest.open).toBe(false)
  })

  it('keeps the later successful request result instead of a stale concurrent response', async () => {
    const { bridge } = makeBridge(state())
    vi.stubGlobal('window', { desktop: bridge })
    const desktop = withSetup(useDesktop)
    await vi.waitFor(() => expect(desktop.state.value).toEqual(state()))
    const firstReply = deferred<DesktopState>()
    const secondReply = deferred<DesktopState>()
    bridge.openApp.mockReturnValueOnce(firstReply.promise).mockReturnValueOnce(secondReply.promise)
    const first = desktop.openApp('cook')
    const second = desktop.openApp('fc')
    const latest = state({ open: true, appId: 'fc', title: 'FC 红白机' })
    secondReply.resolve(latest)
    expect(await second).toBe(latest)
    firstReply.resolve(state({ open: true, appId: 'cook' }))
    expect(await first).toBe(latest)
    expect(desktop.state.value?.guest.appId).toBe('fc')
  })

  it('does not surface an old rejection after a later close succeeds', async () => {
    const { bridge } = makeBridge(state())
    vi.stubGlobal('window', { desktop: bridge })
    const desktop = withSetup(useDesktop)
    await vi.waitFor(() => expect(desktop.state.value).toEqual(state()))
    const reply = deferred<DesktopState>()
    bridge.openApp.mockReturnValueOnce(reply.promise)
    const opening = desktop.openApp('cook')
    const closed = state()
    bridge.command.mockResolvedValueOnce(closed)
    expect(await desktop.command('close')).toBe(closed)
    reply.reject(new Error('stale open failed'))
    expect(await opening).toBeUndefined()
    expect(desktop.error.value).toBe('')
    expect(desktop.state.value?.guest.open).toBe(false)
  })

  it('does not return an actionable result after its page has unmounted', async () => {
    const fixture = makeBridge(state())
    vi.stubGlobal('window', { desktop: fixture.bridge })
    const desktop = withSetup(useDesktop)
    await vi.waitFor(() => expect(desktop.state.value).toEqual(state()))
    const reply = deferred<DesktopState>()
    fixture.bridge.openApp.mockReturnValueOnce(reply.promise)
    const opening = desktop.openApp('cook')
    cleanup.splice(0).forEach(unmount => unmount())
    reply.resolve(state({ open: true, appId: 'cook' }))
    expect(await opening).toBeUndefined()
    expect(desktop.state.value?.guest.open).toBe(false)
    expect(fixture.unsubscribe).toHaveBeenCalledOnce()
  })
})
