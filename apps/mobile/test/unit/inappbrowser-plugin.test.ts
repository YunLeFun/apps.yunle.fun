import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  native: true,
  route: { path: '/tabs/discovery' },
  handlers: new Map<string, (...args: any[]) => unknown>(),
  replace: vi.fn(),
  push: vi.fn(),
  sessions: vi.fn(),
}))
vi.mock('@capacitor/core', () => ({ Capacitor: {
  isNativePlatform: () => h.native,
  isPluginAvailable: () => true,
} }))
vi.mock('../../app/host-runtime', () => ({ HostRuntime: {
  addListener: vi.fn((event, handler) => { h.handlers.set(event, handler) }),
} }))
vi.stubGlobal('defineNuxtPlugin', (setup: () => void) => setup)
vi.stubGlobal('useRouter', () => ({
  currentRoute: { value: h.route },
  isReady: async () => {},
  replace: h.replace,
  push: h.push,
}))
vi.stubGlobal('useBackgroundSessions', h.sessions)
const { default: setup } = await import('../../app/plugins/inappbrowser.client')

describe('native browser to 云居 integration', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    h.handlers.clear()
    h.native = true
    h.route.path = '/tabs/discovery'
  })

  it('initializes sessions before handling a minimized browser and returns to 云居', async () => {
    setup()
    expect(h.sessions).toHaveBeenCalledOnce()
    await h.handlers.get('browserMinimized')?.({ key: 'notes' })
    expect(h.replace).toHaveBeenCalledWith('/tabs/home')
  })

  it('preserves the existing 云居 page when already home', async () => {
    h.route.path = '/tabs/home'
    setup()
    await h.handlers.get('browserMinimized')?.({ key: 'notes' })
    expect(h.replace).not.toHaveBeenCalled()
  })

  it('keeps the detail action separate from minimizing', () => {
    setup()
    h.handlers.get('detailRequested')?.({ appId: 'notes' })
    expect(h.push).toHaveBeenCalledWith('/app/notes')
    expect(h.replace).not.toHaveBeenCalled()
  })

  it('does not register native sessions or change browser-only navigation', () => {
    h.native = false
    setup()
    expect(h.sessions).not.toHaveBeenCalled()
    expect(h.handlers.size).toBe(0)
  })
})
