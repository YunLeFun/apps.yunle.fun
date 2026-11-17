import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const { getOptions } = vi.hoisted(() => ({ getOptions: vi.fn() }))
vi.mock('../../server/utils/cloudbase-admin', () => ({
  useCloudbaseAdmin: () => ({ db: { collection: () => ({ doc: () => ({ get: getOptions }) }) } }),
}))

describe('public login options', () => {
  let server: ReturnType<typeof createServer>
  let url: string
  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    const { default: handler } = await import('../../server/api/login-options.get')
    server = createServer(toNodeListener(createApp().use('/api/login-options', handler)))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/login-options`
  })
  beforeEach(() => {
    getOptions.mockReset()
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })

  it.each([
    { data: [{ weChatLoginVisible: true, updatedBy: 'operator', revision: 1 }], expected: true },
    { data: [{ weChatLoginVisible: false }], expected: false },
    { data: [{ weChatLoginVisible: 'true' }], expected: false },
    { data: [], expected: false },
  ])('only publishes the configured boolean ($expected)', async ({ data, expected }) => {
    getOptions.mockResolvedValue({ data })
    const response = await fetch(url)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(await response.json()).toEqual({ weChatLoginVisible: expected })
  })

  it('hides the entry when settings are unavailable', async () => {
    getOptions.mockRejectedValue(new Error('DB unavailable'))
    expect(await (await fetch(url)).json()).toEqual({ weChatLoginVisible: false })
  })
})
