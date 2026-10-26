import type { H3Event } from 'h3'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const fixture = vi.hoisted(() => ({ resolve: vi.fn(), reason: vi.fn() }))
vi.mock('../../server/domain/catalog/cloudbase', () => ({
  createCloudbaseCatalogResolver: () => ({ resolveCatalog: fixture.resolve }),
  catalogAppViewToRecord: (app: unknown) => app,
}))
vi.mock('../../server/utils/public-app-availability', () => ({ publicAppUnavailableReason: fixture.reason }))
vi.stubGlobal('defineEventHandler', (handler: (event: H3Event) => unknown) => handler)

function eventFor(key: string) {
  const headers = new Map<string, unknown>()
  const event = {
    context: { params: { key } },
    node: { res: { setHeader: (name: string, value: unknown) => headers.set(name, value) } },
  } as unknown as H3Event
  return { event, headers }
}

describe('public application status route', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    fixture.resolve.mockResolvedValue({ apps: [] })
    fixture.reason.mockResolvedValue('delisted')
  })

  it('returns a no-store 404 with the safe reason code for an unavailable application', async () => {
    const { default: handler } = await import('../../server/api/apps/public/[key].get')
    const { event, headers } = eventFor('removed')
    await expect(handler(event)).rejects.toMatchObject({ statusCode: 404, data: { code: 'APP_UNAVAILABLE', reasonCode: 'delisted' } })
    expect(headers.get('Cache-Control')).toBe('no-store')
    expect(fixture.reason).toHaveBeenCalledExactlyOnceWith('removed')
  })

  it('returns current public metadata when an application is relisted', async () => {
    const app = { _id: 'stable-id', marketShortName: 'public-key', name: '重新上架的应用' }
    fixture.resolve.mockResolvedValue({ apps: [app] })
    const { default: handler } = await import('../../server/api/apps/public/[key].get')
    const { event, headers } = eventFor('PUBLIC-KEY')
    await expect(handler(event)).resolves.toEqual({ app })
    expect(fixture.reason).not.toHaveBeenCalled()
    expect(headers.get('Cache-Control')).toBe('no-store')
  })

  it('does not convert a failed catalog read into an application removal', async () => {
    fixture.resolve.mockRejectedValue(new Error('catalog unavailable'))
    const { default: handler } = await import('../../server/api/apps/public/[key].get')
    await expect(handler(eventFor('public-key').event)).rejects.toThrow('catalog unavailable')
    expect(fixture.reason).not.toHaveBeenCalled()
  })

  it('rejects invalid keys before looking up application state', async () => {
    const { default: handler } = await import('../../server/api/apps/public/[key].get')
    await expect(handler(eventFor('../private').event)).rejects.toMatchObject({ statusCode: 400 })
    expect(fixture.resolve).not.toHaveBeenCalled()
    expect(fixture.reason).not.toHaveBeenCalled()
  })
})
