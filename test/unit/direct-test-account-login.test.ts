import { access, readFile } from 'node:fs/promises'
import { describe, expect, it } from 'vitest'

const root = new URL('../../', import.meta.url)

describe('direct fixed test account login', () => {
  it('uses the standard password session for native CMS authorization', async () => {
    const [login, broker, userStore] = await Promise.all([
      readFile(new URL('app/pages/login/index.vue', root), 'utf8'),
      readFile(new URL('app/plugins/identity-broker.client.ts', root), 'utf8'),
      readFile(new URL('app/stores/user.ts', root), 'utf8'),
    ])

    expect(login).toContain('signInWithPassword')
    expect(login).toContain('params.username = passwordAccount.value')
    expect(`${login}\n${broker}\n${userStore}`).not.toMatch(/nativeTestSession|native-test-session|模拟验证码|挑战 ID/)
  })

  it('does not expose the retired native test-session proxy routes', async () => {
    for (const file of [
      'server/api/auth/native-test-session/exchange.post.ts',
      'server/api/auth/native-test-session/authorize.post.ts',
      'server/utils/native-test-session-proxy.ts',
    ]) {
      await expect(access(new URL(file, root))).rejects.toMatchObject({ code: 'ENOENT' })
    }
  })
})
