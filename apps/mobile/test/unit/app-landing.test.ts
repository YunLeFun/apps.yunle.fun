import { readFile } from 'node:fs/promises'
import { createApp, createRouter, defineEventHandler, toWebHandler } from 'h3'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const asset = await readFile(new URL('../../server/assets/app-landing.html', import.meta.url), 'utf8')
const getItem = vi.fn()
vi.stubGlobal('defineEventHandler', defineEventHandler)
vi.stubGlobal('useStorage', (name: string) => {
  expect(name).toBe('assets:server')
  return { getItem }
})
const { default: landing } = await import('../../server/routes/index.get')
const serve = toWebHandler(createApp().use(createRouter().get('/', landing)))

describe('static App landing', () => {
  beforeEach(() => {
    getItem.mockReset().mockResolvedValue(asset)
  })

  it('serves the HTML asset without loading the client app shell', async () => {
    const response = await serve(new Request('https://apps.yunle.fun/'))
    expect(response.status).toBe(200)
    expect(response.headers.get('content-type')).toContain('text/html')
    const html = await response.text()
    expect(getItem).toHaveBeenCalledWith('app-landing.html')
    expect(html).toBe(asset)
    expect(html).toContain('href="/tabs/home"')
    expect(html).toContain('href="https://www.yunle.fun/download"')
    expect(html).toContain('<script defer src="/landing/app.js"></script>')
    expect(html).toContain('name="apple-itunes-app"')
    expect(html).not.toMatch(/<ion-app|\/_nuxt\//)
  })

  it('keeps the old showcase query link usable', async () => {
    const response = await serve(new Request('https://apps.yunle.fun/?showcase'))
    expect(await response.text()).toBe(asset)
  })

  it('reports a missing artifact as unavailable', async () => {
    getItem.mockResolvedValue(null)
    const response = await serve(new Request('https://apps.yunle.fun/'))
    expect(response.status).toBe(503)
  })
})
