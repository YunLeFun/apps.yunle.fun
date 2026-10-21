import type { AddressInfo } from 'node:net'
import { createServer } from 'node:http'
import { createApp, defineEventHandler, toNodeListener } from 'h3'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'
import { resolveAssistantRollout, resolvePublicFeatures } from '../../server/utils/feature-flags'

describe('assistant rollout config', () => {
  it('defaults to members at 100 percent', () => {
    expect(resolvePublicFeatures({})).toEqual({ assistant: { audience: 'members', percent: 100 } })
  })
  it('accepts every known audience', () => {
    for (const audience of ['off', 'members', 'signedIn', 'everyone'])
      expect(resolveAssistantRollout(audience, 100).audience).toBe(audience)
  })
  it('falls back to members for unknown audiences', () => {
    expect(resolveAssistantRollout('all', 100).audience).toBe('members')
    expect(resolveAssistantRollout(' ', 100).audience).toBe('members')
    expect(resolveAssistantRollout(42, 100).audience).toBe('members')
  })
  it('clamps and parses percentages', () => {
    expect(resolveAssistantRollout('members', '25').percent).toBe(25)
    expect(resolveAssistantRollout('members', 12.9).percent).toBe(12)
    expect(resolveAssistantRollout('members', -5).percent).toBe(0)
    expect(resolveAssistantRollout('members', '250').percent).toBe(100)
    expect(resolveAssistantRollout('members', 'half').percent).toBe(100)
    expect(resolveAssistantRollout('members', '').percent).toBe(100)
  })
})

describe('public features route', () => {
  let server: ReturnType<typeof createServer>
  let origin: string

  beforeAll(async () => {
    vi.stubGlobal('defineEventHandler', defineEventHandler)
    vi.stubGlobal('useRuntimeConfig', () => ({ assistantAudience: 'signedIn', assistantRolloutPercent: '30', tencentApiSecretKey: 'secret' }))
    const handler = (await import('../../server/api/features.get')).default
    const app = createApp()
    app.use('/api/features', handler)
    server = createServer(toNodeListener(app))
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })
  afterAll(async () => {
    vi.unstubAllGlobals()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  })

  it('returns only the public rollout with a short public cache', async () => {
    const response = await fetch(`${origin}/api/features`)
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('public, max-age=300')
    expect(await response.json()).toEqual({ assistant: { audience: 'signedIn', percent: 30 } })
  })
})
