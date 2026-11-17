import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  standalone: false,
  remembered: null as string | null,
  navigateTo: vi.fn((path: string, options?: unknown) => ({ path, options })),
}))
vi.stubGlobal('defineNuxtRouteMiddleware', (middleware: unknown) => middleware)
vi.stubGlobal('navigateTo', h.navigateTo)
vi.stubGlobal('window', { matchMedia: () => ({ matches: h.standalone }) })
vi.stubGlobal('navigator', {})
vi.stubGlobal('localStorage', { getItem: () => h.remembered })
const { default: middleware } = await import('../../app/middleware/web-entry') as unknown as {
  default: (to: { query: Record<string, unknown> }) => unknown
}

describe('root path entry for the showcase page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    h.standalone = false
    h.remembered = null
  })

  it('shows the showcase to first-time browser visitors', () => {
    expect(middleware({ query: {} })).toBeUndefined()
    expect(h.navigateTo).not.toHaveBeenCalled()
  })

  it('sends home-screen web apps straight into the app', () => {
    h.standalone = true
    middleware({ query: {} })
    expect(h.navigateTo).toHaveBeenCalledWith('/tabs/home', { replace: true })
  })

  it('remembers visitors who chose the web app, with ?showcase as an override', () => {
    h.remembered = 'app'
    middleware({ query: {} })
    expect(h.navigateTo).toHaveBeenCalledWith('/tabs/home', { replace: true })

    h.navigateTo.mockClear()
    expect(middleware({ query: { showcase: null } })).toBeUndefined()
    expect(h.navigateTo).not.toHaveBeenCalled()
  })
})
