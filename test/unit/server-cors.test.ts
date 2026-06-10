import { describe, expect, it } from 'vitest'
import { resolveCorsOrigin } from '../../server/utils/cors'

describe('resolveCorsOrigin', () => {
  it('allows native app webview origins', () => {
    expect(resolveCorsOrigin('capacitor://localhost')).toBe('capacitor://localhost')
    expect(resolveCorsOrigin('ionic://localhost')).toBe('ionic://localhost')
    expect(resolveCorsOrigin('https://localhost')).toBe('https://localhost')
  })

  it('allows localhost dev origins with optional port', () => {
    expect(resolveCorsOrigin('http://localhost:8001')).toBe('http://localhost:8001')
    expect(resolveCorsOrigin('http://127.0.0.1:3000')).toBe('http://127.0.0.1:3000')
    expect(resolveCorsOrigin('http://localhost')).toBe('http://localhost')
  })

  it('rejects missing or unknown origins', () => {
    expect(resolveCorsOrigin(undefined)).toBeNull()
    expect(resolveCorsOrigin('')).toBeNull()
    expect(resolveCorsOrigin('https://evil.example.com')).toBeNull()
    // 前缀伪造：localhost.evil.com 不应被放行
    expect(resolveCorsOrigin('http://localhost.evil.com')).toBeNull()
    expect(resolveCorsOrigin('http://localhost.evil.com:8001')).toBeNull()
    expect(resolveCorsOrigin('capacitor://evil.com')).toBeNull()
  })
})
