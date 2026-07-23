import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const browser = readFileSync(new URL('../../app/composables/useBrowser.ts', import.meta.url), 'utf8')
const native = readFileSync(new URL('../../ios/App/App/WebViewController.swift', import.meta.url), 'utf8')
const manifest = JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8'))

describe('native WebView authorization boundary', () => {
  it('does not expose SSO or host credentials through window.ylf', () => {
    expect(native).not.toContain('getAuthCode')
    expect(native).not.toContain('authReady')
    expect(native).not.toContain('refreshToken')
    expect(browser).not.toContain('auth?:')
    expect(browser).not.toContain('resolveAuthContext')
  })

  it('removes the bespoke native authorization service', () => {
    expect(manifest.dependencies).not.toHaveProperty('@yunlefun/sso')
    expect(existsSync(new URL('../../server/utils/jsapi-auth.ts', import.meta.url))).toBe(false)
    expect(existsSync(new URL('../../server/api/jsapi/auth/code.post.ts', import.meta.url))).toBe(false)
    expect(existsSync(new URL('../../server/api/jsapi/auth/exchange.post.ts', import.meta.url))).toBe(false)
  })
})
