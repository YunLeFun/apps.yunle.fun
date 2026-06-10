import type { H3Event } from 'h3'
import { Buffer } from 'node:buffer'
import { beforeEach, describe, expect, it, vi } from 'vitest'

function makeToken(payload: Record<string, unknown>) {
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `header.${encoded}.signature`
}

function makeEvent(token?: string): H3Event {
  return {
    node: {
      req: {
        headers: token ? { authorization: `Bearer ${token}` } : {},
      },
    },
  } as unknown as H3Event
}

describe('cloudbase auth utils', () => {
  beforeEach(async () => {
    vi.clearAllMocks()
    vi.stubGlobal('useRuntimeConfig', () => ({
      public: { tcbEnvId: 'yunlefun-test' },
    }))
    vi.stubGlobal('fetch', vi.fn())
    const { clearCloudbaseAuthCache } = await import('../../server/utils/cloudbase-auth')
    clearCloudbaseAuthCache()
  })

  it('parses bearer token and JWT exp', async () => {
    const { parseBearerToken, readJwtExpiry } = await import('../../server/utils/cloudbase-auth')
    const token = makeToken({ exp: 2000 })
    expect(parseBearerToken(`Bearer ${token}`)).toBe(token)
    expect(parseBearerToken('Basic abc')).toBeNull()
    expect(readJwtExpiry(token)).toBe(2_000_000)
  })

  it('returns null for missing or expired token without remote request', async () => {
    const { tryGetCloudbaseUser } = await import('../../server/utils/cloudbase-auth')
    await expect(tryGetCloudbaseUser(makeEvent())).resolves.toBeNull()
    await expect(tryGetCloudbaseUser(makeEvent(makeToken({ exp: Math.floor(Date.now() / 1000) - 10 })))).resolves.toBeNull()
    expect(fetch).not.toHaveBeenCalled()
  })

  it('verifies token remotely and caches successful result', async () => {
    const fetchMock = vi.mocked(fetch)
    fetchMock.mockResolvedValue({
      ok: true,
      json: vi.fn().mockResolvedValue({
        sub: 'uid-1',
        nickname: '云游君',
        avatar_url: 'https://example.com/avatar.png',
      }),
    } as unknown as Response)

    const { tryGetCloudbaseUser } = await import('../../server/utils/cloudbase-auth')
    const token = makeToken({ exp: Math.floor(Date.now() / 1000) + 3600 })
    await expect(tryGetCloudbaseUser(makeEvent(token))).resolves.toEqual({
      uid: 'uid-1',
      name: '云游君',
      picture: 'https://example.com/avatar.png',
    })
    await expect(tryGetCloudbaseUser(makeEvent(token))).resolves.toEqual(expect.objectContaining({ uid: 'uid-1' }))
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('throws real 401 from requireCloudbaseUser when invalid', async () => {
    const { requireCloudbaseUser } = await import('../../server/utils/cloudbase-auth')
    await expect(requireCloudbaseUser(makeEvent())).rejects.toMatchObject({ statusCode: 401 })
  })
})
