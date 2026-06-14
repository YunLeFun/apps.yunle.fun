import { beforeEach, describe, expect, it, vi } from 'vitest'

const { records, collection } = vi.hoisted(() => {
  const records: any[] = []
  const collection = {
    add: vi.fn(async (record: any) => {
      const next = { ...record, _id: `code-${records.length + 1}` }
      records.push(next)
      return { id: next._id }
    }),
    where: vi.fn((query: Record<string, unknown>) => ({
      limit: vi.fn(() => ({
        get: vi.fn(async () => ({
          data: records.filter(record => record.codeHash === query.codeHash),
        })),
      })),
    })),
    doc: vi.fn((id: string) => ({
      update: vi.fn(async (patch: Record<string, unknown>) => {
        const record = records.find(record => record._id === id)
        if (record)
          Object.assign(record, patch)
        return { updated: record ? 1 : 0 }
      }),
    })),
  }
  return { records, collection }
})

vi.mock('../../server/utils/cloudbase-admin', () => ({
  useCloudbaseAdmin: () => ({
    db: {
      collection: () => collection,
    },
  }),
}))

describe('jsapi auth utils', () => {
  beforeEach(() => {
    records.length = 0
    vi.clearAllMocks()
    vi.stubGlobal('useRuntimeConfig', () => ({
      jsapiAuthAllowedOrigins: 'https://*.yunyoujun.cn',
    }))
  })

  it('normalizes origins and scopes defensively', async () => {
    const { normalizeCloudbaseSession, normalizeOrigin, normalizeScope } = await import('../../server/utils/jsapi-auth')
    expect(normalizeOrigin('https://gmm.yunyoujun.cn/path?q=1')).toBe('https://gmm.yunyoujun.cn')
    expect(normalizeOrigin('bad')).toBe('')
    expect(normalizeScope(['profile', 'profile', 'bad scope', 'wallet:read'])).toEqual(['profile', 'wallet:read'])
    expect(normalizeScope([])).toEqual(['profile'])
    expect(normalizeCloudbaseSession({
      access_token: 'access-token',
      refresh_token: 'refresh-token',
    })).toEqual({
      access_token: 'access-token',
      refresh_token: 'refresh-token',
    })
    expect(normalizeCloudbaseSession({ access_token: 'access-token' })).toBeUndefined()
  })

  it('accepts configured wildcard origins and rejects protocol mismatches', async () => {
    const { assertAllowedJsapiOrigin } = await import('../../server/utils/jsapi-auth')
    expect(() => assertAllowedJsapiOrigin('https://gmm.yunyoujun.cn')).not.toThrow()
    expect(() => assertAllowedJsapiOrigin('http://gmm.yunyoujun.cn')).toThrow()
  })

  it('creates one-time auth codes bound to the requesting origin', async () => {
    const { createJsapiAuthCode, consumeJsapiAuthCode } = await import('../../server/utils/jsapi-auth')
    const issued = await createJsapiAuthCode({
      user: { uid: 'uid-1', name: 'Alice', picture: 'https://example.com/a.png' },
      appId: 'give-me-money',
      origin: 'https://gmm.yunyoujun.cn',
      scope: ['profile'],
    })

    expect(issued.code).toMatch(/^[\w-]+$/)
    expect(records[0]).toMatchObject({
      uid: 'uid-1',
      appId: 'give-me-money',
      origin: 'https://gmm.yunyoujun.cn',
      consumedAt: 0,
    })
    expect(records[0].code).toBeUndefined()

    await expect(consumeJsapiAuthCode({
      code: issued.code,
      origin: 'https://other.yunyoujun.cn',
    })).rejects.toMatchObject({ statusCode: 403 })

    await expect(consumeJsapiAuthCode({
      code: issued.code,
      origin: 'https://gmm.yunyoujun.cn',
    })).resolves.toEqual({
      appId: 'give-me-money',
      origin: 'https://gmm.yunyoujun.cn',
      scope: ['profile'],
      user: {
        id: 'uid-1',
        nickname: 'Alice',
        avatar: 'https://example.com/a.png',
      },
    })

    await expect(consumeJsapiAuthCode({
      code: issued.code,
      origin: 'https://gmm.yunyoujun.cn',
    })).rejects.toMatchObject({ statusCode: 400 })
  })

  it('returns CloudBase session only for explicit first-party session scope', async () => {
    const { createJsapiAuthCode, consumeJsapiAuthCode } = await import('../../server/utils/jsapi-auth')
    const issued = await createJsapiAuthCode({
      user: { uid: 'uid-1' },
      appId: 'give-me-money',
      origin: 'https://gmm.yunyoujun.cn',
      scope: ['profile', 'cloudbase:session'],
      session: {
        access_token: 'access-token',
        refresh_token: 'refresh-token',
      },
    })

    expect(records[0]).toMatchObject({
      scope: ['profile', 'cloudbase:session'],
      session: {
        access_token: 'access-token',
        refresh_token: 'refresh-token',
      },
    })

    await expect(consumeJsapiAuthCode({
      code: issued.code,
      origin: 'https://gmm.yunyoujun.cn',
    })).resolves.toMatchObject({
      session: {
        access_token: 'access-token',
        refresh_token: 'refresh-token',
      },
    })
  })
})
