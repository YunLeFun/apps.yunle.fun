import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { clampViewport, contentSecurityPolicy, isAllowedPage, isLoopbackOrigin, parseRequest, resolveAsset, validUpdateRepository } from '../../electron/policies'
import { COOK_FEATURE_IMAGE_URL, EDITORIAL_MEDIA_ORIGIN, editorialMediaOrigin } from '../../shared/editorial-media'

describe('desktop trust policy', () => {
  it('allows declared HTTPS origins, but rejects credentials and host suffix spoofing', () => {
    const origins = ['https://nuxt.com']
    expect(isAllowedPage('https://nuxt.com/docs', origins)).toBe(true)
    for (const url of ['https://nuxt.com.evil.example/', 'https://user:password@nuxt.com/', 'http://nuxt.com/', 'file:///etc/passwd', 'app://shell/'])
      expect(isAllowedPage(url, origins)).toBe(false)
  })
  it('accepts only explicit loopback development origins', () => {
    expect(isLoopbackOrigin('http://127.0.0.1:3000')).toBe(true)
    for (const url of ['http://localhost.evil.test', 'http://0.0.0.0:3000', 'http://localhost/path', 'http://localhost?x=1', 'https://localhost'])
      expect(isLoopbackOrigin(url)).toBe(false)
  })
  it('rejects forged commands and nonfinite layout values', () => {
    for (const input of [null, [], { type: 'open-app', appId: 'file:///tmp' }, { type: 'execute', script: '...' }, { type: 'viewport', bounds: { x: 0, y: 0, width: Number.POSITIVE_INFINITY, height: 100 } }])
      expect(() => parseRequest(input)).toThrow()
    expect(parseRequest({ type: 'open-app', appId: 'cook', url: 'https://evil.example', partition: 'persist:shell' })).toEqual({ type: 'open-app', appId: 'cook' })
    expect(parseRequest({ type: 'theme', preference: 'dark' })).toEqual({ type: 'theme', preference: 'dark' })
  })
  it('confines viewport updates to the current window', () => {
    expect(clampViewport({ x: -20, y: 50, width: 5000, height: 5000 }, { width: 800, height: 600 }))
      .toEqual({ x: 0, y: 52, width: 800, height: 548 })
    expect(clampViewport({ x: 20, y: 20, width: 100, height: 100 }, { width: 800, height: 600 }, 1.5))
      .toEqual({ x: 30, y: 52, width: 150, height: 128 })
  })
  it('keeps the native titlebar protected when shell zoom shrinks the CSS toolbar', () => {
    expect(clampViewport({ x: 216, y: 52, width: 1064, height: 788 }, { width: 1280, height: 840 }, 0.5))
      .toEqual({ x: 108, y: 52, width: 532, height: 368 })
    expect(clampViewport({ x: 20, y: 0, width: 100, height: 40 }, { width: 800, height: 600 }))
      .toEqual({ x: 20, y: 52, width: 100, height: 0 })
  })
  it('does not enlarge a partially clipped guest or draw outside a tiny window', () => {
    expect(clampViewport({ x: -20, y: 40, width: 100, height: 100 }, { width: 800, height: 600 }))
      .toEqual({ x: 0, y: 52, width: 80, height: 88 })
    expect(clampViewport({ x: 10, y: 10, width: 100, height: 100 }, { width: 30, height: 30 }))
      .toEqual({ x: 10, y: 30, width: 20, height: 0 })
    expect(clampViewport({ x: 10, y: 100, width: -10, height: -10 }, { width: 800, height: 600 }))
      .toEqual({ x: 10, y: 100, width: 0, height: 0 })
  })
  it('keeps decoded resource paths inside the static bundle', () => {
    const root = path.resolve('fixture')
    expect(resolveAsset(root, '/_nuxt/app.js')).toBe(path.join(root, '_nuxt/app.js'))
    for (const name of ['/../secret', '/%2e%2e/secret', '/%00secret', '/%5c..%5csecret', '/%invalid'])
      expect(resolveAsset(root, name)).toBeNull()
  })
  it('hashes executable inline Nuxt scripts without allowing arbitrary inline JavaScript', () => {
    const csp = contentSecurityPolicy('<script>window.test = 1</script><script src="/app.js"></script><script type="application/json">{}</script>')
    expect(csp).toContain('\'sha256-')
    expect(csp.split(';').find(item => item.trim().startsWith('script-src'))).not.toContain('\'unsafe-inline\'')
    expect(csp).toContain('frame-ancestors \'none\'')
    expect(contentSecurityPolicy('<script>window.test = 2</script>')).not.toBe(csp)
  })
  it('accepts an update repository, never a page-supplied feed URL', () => {
    expect(validUpdateRepository('YunLeFun/apps.yunle.fun')).toBe(true)
    for (const value of ['', 'https://evil.test/feed', 'owner/repo/extra', null])
      expect(validUpdateRepository(value)).toBe(false)
  })
  it('derives decorative media origins only from public HTTPS object URLs', () => {
    expect(editorialMediaOrigin('https://cdn.example.com/desktop/cook-feature.png')).toBe('https://cdn.example.com')
    for (const value of [
      '',
      'http://cdn.example.com/desktop/cook-feature.png',
      'https://user:password@cdn.example.com/desktop/cook-feature.png',
      'https://cdn.example.com:8443/desktop/cook-feature.png',
      'https://cdn.example.com/desktop/cook-feature.png?token=secret',
      'https://cdn.example.com/desktop/cook-feature.png#fragment',
      'https://*.example.com/desktop/cook-feature.png',
      'https://127.0.0.1/desktop/cook-feature.png',
      'https://cdn.local/desktop/cook-feature.png',
      'data:image/png;base64,AA==',
      'file:///tmp/cook-feature.png',
    ]) {
      expect(editorialMediaOrigin(value)).toBe('')
    }
  })
  it('allows the fixed editorial origin for images without granting script, API or frame access', () => {
    const directives = contentSecurityPolicy('').split(';').map(item => item.trim())
    const imagePolicy = directives.find(item => item.startsWith('img-src'))
    expect(EDITORIAL_MEDIA_ORIGIN).toBe(editorialMediaOrigin(COOK_FEATURE_IMAGE_URL))
    expect(imagePolicy).toBe(`img-src 'self' data:${EDITORIAL_MEDIA_ORIGIN ? ` ${EDITORIAL_MEDIA_ORIGIN}` : ''}`)
    expect(imagePolicy).not.toContain('*')
    expect(directives.find(item => item.startsWith('connect-src'))).toBe('connect-src \'self\'')
    expect(directives.find(item => item.startsWith('script-src'))).toBe('script-src \'self\'')
    expect(directives.find(item => item.startsWith('frame-src'))).toBe('frame-src \'none\'')
  })
})
