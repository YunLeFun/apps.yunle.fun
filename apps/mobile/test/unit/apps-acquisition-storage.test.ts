import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  APPS_ACQUISITION_FIRST_WINDOW_MS,
  APPS_ACQUISITION_KEYS,
  APPS_ACQUISITION_WINDOW_MS,
  captureAppsAcquisitionTouch,
  createAppsAcquisitionStorage,
  readAppsLaunchAcquisitionUrl,
} from '../../app/utils/apps-acquisition-storage'

const NOW = 1_791_547_200_000

function memoryStorage() {
  const values = new Map<string, string>()
  return {
    values,
    getItem: vi.fn((key: string) => values.get(key) || null),
    setItem: vi.fn((key: string, value: string) => values.set(key, value)),
    removeItem: vi.fn((key: string) => values.delete(key)),
  }
}

describe('apps direct acquisition storage', () => {
  let local: ReturnType<typeof memoryStorage>
  let session: ReturnType<typeof memoryStorage>
  let now: number
  let nextId: number

  beforeEach(() => {
    local = memoryStorage()
    session = memoryStorage()
    now = NOW
    nextId = 0
  })

  function createStore() {
    return createAppsAcquisitionStorage({ local, session, now: () => now, createId: () => `attempt-${++nextId}` })
  }

  it('retains first landing but uses new explicit UTM at registration through login navigation', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu&utm_medium=social'), 'https://www.zhihu.com/question/42')
    now += 1000
    store.captureEntry(new URL('https://apps.yunle.fun/tabs/discovery?utm_source=weixin&utm_campaign=october'), '', 'navigation')
    store.captureEntry(new URL('https://apps.yunle.fun/login'), 'https://github.com/', 'navigation')
    const attempt = store.beginAuthentication('phone_otp')
    expect(attempt.context?.firstTouch).toMatchObject({ utmSource: 'zhihu', referrerHost: 'www.zhihu.com', landingPath: '/' })
    expect(attempt.context?.registerTouch).toMatchObject({ utmSource: 'weixin', referrerHost: '', landingPath: '/tabs/discovery' })
  })

  it('freezes OAuth context across document callback and ignores an imported SSO context', () => {
    const store = createStore()
    const foreign = JSON.stringify({ version: 1, entryAppId: 'cook', firstTouch: {}, registerTouch: {} })
    store.captureEntry(new URL(`https://apps.yunle.fun/?utm_source=launch&acquisition=${encodeURIComponent(foreign)}`))
    const attempt = store.beginAuthentication('github', 'state-own')
    store.captureEntry(new URL('https://apps.yunle.fun/auth/callback?code=secret&state=state-own&utm_source=github'), 'https://github.com/')
    expect(store.readAttempt()).toEqual(attempt)
    expect(store.completeAuthentication('uid-1', 'state-wrong')).toBeNull()
    expect(store.completeAuthentication('uid-1', 'state-own')?.context?.registerTouch.utmSource).toBe('launch')
    expect(JSON.stringify(session.values.get(APPS_ACQUISITION_KEYS.pending))).not.toContain('secret')
    expect(store.readAttempt()).toBeNull()
  })

  it('does not begin attribution from an unsolicited OAuth callback or an SSO request', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/auth/callback?state=app-github_x'), 'https://github.com/')
    expect(store.completeAuthentication('uid-1', 'app-github_x')).toBeNull()
    store.captureEntry(new URL('https://apps.yunle.fun/auth/sso?client_id=cook-web&acquisition=anything'))
    expect(store.beginAuthentication('phone_otp').context).toBeNull()
  })

  it('lets the Registry SSO writer own host login initiated by another app, even after the native request marker is cleared', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=apps-promotion'))
    const attempt = store.beginAuthentication('phone_otp', undefined, true)
    expect(attempt.delegatedSso).toBe(true)
    expect(attempt.context).toBeNull()
    // Native login success resumes the requesting WebView and clears its marker before this hook.
    expect(store.completeAuthentication('uid-1')).toBeNull()
    expect(store.readPending()).toBeNull()
  })

  it('keeps a frozen pending context while another landing/attempt appears and cannot clear that new task', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=first'))
    store.beginAuthentication('phone_otp')
    const first = store.completeAuthentication('uid-1')!
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=second'), '', 'navigation')
    expect(store.readPending()?.context?.registerTouch.utmSource).toBe('first')
    store.beginAuthentication('email_otp')
    const second = store.completeAuthentication('uid-2')!
    store.clearPending(first.id)
    store.savePending({ ...first, attempts: 1 })
    expect(store.readPending()).toEqual(second)
  })

  it('expires authentication attempts after 30 minutes and first touch after 30 days', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=old'))
    store.beginAuthentication('phone_otp')
    now += APPS_ACQUISITION_WINDOW_MS + 1
    expect(store.completeAuthentication('uid-1')).toBeNull()
    now += APPS_ACQUISITION_FIRST_WINDOW_MS
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=new'))
    expect(store.beginAuthentication('phone_otp').context?.firstTouch.utmSource).toBe('new')
  })

  it('supports delayed signup on the same landing without losing the original channel', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu'))
    now += 45 * 60 * 1000
    expect(store.beginAuthentication('phone_otp').context?.registerTouch.utmSource).toBe('zhihu')
  })

  it.each(['login', 'signup'])('replaces an old campaign at a new /%s document while retaining the browser first touch', (path) => {
    const initial = createStore()
    initial.captureEntry(new URL('https://apps.yunle.fun/?utm_source=old-campaign'))
    now += 24 * 60 * 60 * 1000
    const reopened = createStore()
    reopened.captureEntry(new URL(`https://apps.yunle.fun/${path}`), 'https://apps.yunle.fun/')
    const attempt = reopened.beginAuthentication('phone_otp')
    expect(attempt.context?.firstTouch.utmSource).toBe('old-campaign')
    expect(attempt.context?.registerTouch).toMatchObject({ landingPath: `/${path}`, capturedAt: now, utmSource: '', referrerHost: '' })
  })

  it('uses current external referrer at a new login document without borrowing an older campaign', () => {
    const initial = createStore()
    initial.captureEntry(new URL('https://apps.yunle.fun/?utm_source=old-campaign'))
    const reopened = createStore()
    reopened.captureEntry(new URL('https://apps.yunle.fun/login'), 'https://example.org/article')
    expect(reopened.beginAuthentication('email_otp').context?.registerTouch).toMatchObject({
      landingPath: '/login',
      utmSource: '',
      referrerHost: 'example.org',
    })
  })

  it('can restore a frozen attempt from session storage after a full Web OAuth redirect', () => {
    const initial = createStore()
    initial.captureEntry(new URL('https://apps.yunle.fun/?utm_source=github'))
    initial.beginAuthentication('github', 'state-1')
    const restored = createStore()
    restored.captureEntry(new URL('https://apps.yunle.fun/auth/callback?code=sensitive'), 'https://github.com/')
    expect(restored.completeAuthentication('uid-1', 'state-1')?.context?.registerTouch.utmSource).toBe('github')
  })

  it('matches state captured by the pre plugin even when SDK initialization removes callback query before the page mounts', () => {
    const initial = createStore()
    initial.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu'))
    initial.beginAuthentication('github', 'state-original')
    const callback = createStore()
    callback.captureEntry(new URL('https://apps.yunle.fun/auth/callback?code=private&state=state-original'))
    // SDK has now replaced browser history with /auth/callback. No state remains for the page to read.
    callback.captureEntry(new URL('https://apps.yunle.fun/auth/callback'))
    expect(callback.completeAuthentication('uid-1')?.context?.registerTouch.utmSource).toBe('zhihu')
    expect(JSON.stringify([...session.values.values()])).not.toContain('private')
  })

  it('invalidates an earlier matching snapshot when a different callback state arrives before SDK cleanup', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu'))
    store.beginAuthentication('github', 'state-own')
    store.captureEntry(new URL('https://apps.yunle.fun/auth/callback?code=first&state=state-own'))
    store.captureEntry(new URL('https://apps.yunle.fun/auth/callback?code=other&state=state-foreign'))
    store.captureEntry(new URL('https://apps.yunle.fun/auth/callback'))
    expect(store.completeAuthentication('uid-1')).toBeNull()
  })

  it('validates frozen retry context at the original attempt time without replacing first touch at a 30-day boundary', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=old-first'))
    now += APPS_ACQUISITION_FIRST_WINDOW_MS - 1000
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=register'), '', 'navigation')
    store.beginAuthentication('phone_otp')
    const pending = store.completeAuthentication('uid-1')!
    now += 2000
    expect(store.readPending()?.context).toEqual(pending.context)
    expect(store.readPending()?.context?.firstTouch.utmSource).toBe('old-first')
  })

  it('preserves the original context when OAuth completes after first touch crosses the 30-day boundary', () => {
    const initial = createStore()
    initial.captureEntry(new URL('https://apps.yunle.fun/?utm_source=first'))
    now += APPS_ACQUISITION_FIRST_WINDOW_MS - 1000
    initial.captureEntry(new URL('https://apps.yunle.fun/?utm_source=register'), '', 'navigation')
    const attempt = initial.beginAuthentication('github', 'original-state')
    now += 2000
    const callback = createStore()
    callback.captureEntry(new URL('https://apps.yunle.fun/auth/callback?state=original-state&code=sensitive'))
    const pending = callback.completeAuthentication('uid-1')!
    expect(pending.createdAt).toBe(attempt.createdAt)
    expect(pending.context).toEqual(attempt.context)
    expect(callback.readPending()?.context?.registerTouch.utmSource).toBe('register')
  })

  it('uses memory when WebView storage is denied, without storing authentication tokens', () => {
    const denied = {
      getItem: () => { throw new Error('denied') },
      setItem: () => { throw new Error('denied') },
      removeItem: () => { throw new Error('denied') },
    }
    const store = createAppsAcquisitionStorage({ local: denied, session: denied, now: () => NOW })
    store.captureEntry(new URL('capacitor://localhost/login?utm_source=weixin&access_token=secret#private'))
    store.beginAuthentication('phone_otp')
    const pending = store.completeAuthentication('uid-1')!
    expect(pending.context?.registerTouch).toMatchObject({ landingHost: 'apps.yunle.fun', landingPath: '/login', utmSource: 'weixin' })
    expect(JSON.stringify(pending)).not.toMatch(/secret|private|access_token/)
  })

  it.each(['remove', 'corrupt', 'oversize'])('does not resurrect a pending task from memory after readable storage is %s', (mutation) => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu'))
    store.beginAuthentication('phone_otp')
    store.completeAuthentication('uid-1')
    if (mutation === 'remove')
      session.values.delete(APPS_ACQUISITION_KEYS.pending)
    else
      session.values.set(APPS_ACQUISITION_KEYS.pending, mutation === 'corrupt' ? '{bad-json' : 'x'.repeat(6145))
    expect(store.readPending()).toBeNull()
  })

  it('does not recover a deleted callback snapshot from memory after SDK cleanup', () => {
    const store = createStore()
    store.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu'))
    store.beginAuthentication('github', 'state-own')
    store.captureEntry(new URL('https://apps.yunle.fun/auth/callback?state=state-own&code=code'))
    session.values.delete(APPS_ACQUISITION_KEYS.callback)
    expect(store.completeAuthentication('uid-1')).toBeNull()
  })

  it.each(['https://www.yunle.fun/login', 'https://cook.yunyoujun.cn/', 'https://apps.yunle.fun/w/123', 'https://www.yunle.fun./login', 'https://cook.yunyoujun.cn./'])('excludes internal referrer %s', (referrer) => {
    expect(captureAppsAcquisitionTouch(new URL('https://apps.yunle.fun/'), referrer, NOW)?.referrerHost).toBe('')
  })

  it('drops malformed UTM and refuses untrusted document origins', () => {
    expect(captureAppsAcquisitionTouch(new URL('https://apps.yunle.fun/?utm_source=token%3Dsecret&utm_medium=social'), '', NOW)).toMatchObject({ utmSource: '', utmMedium: 'social' })
    expect(captureAppsAcquisitionTouch(new URL('https://evil.example/?utm_source=evil'), '', NOW)).toBeNull()
  })

  it('captures supported native launch UTM only after mapping to a trusted Apps route', () => {
    const url = readAppsLaunchAcquisitionUrl('yunlefun://workshop/EJ83N5?utm_source=weixin&code=secret#private', '/w/EJ83N5')!
    expect(url.href).toBe('https://apps.yunle.fun/w/EJ83N5?utm_source=weixin')
    expect(readAppsLaunchAcquisitionUrl('https://apps.yunle.fun/w/EJ83N5?utm_campaign=qr', '/w/EJ83N5')?.searchParams.get('utm_campaign')).toBe('qr')
    expect(readAppsLaunchAcquisitionUrl('yunlefun://wallet?utm_source=weixin', '/wallet')?.searchParams.get('utm_source')).toBe('weixin')
    expect(readAppsLaunchAcquisitionUrl('yunlefun://auth/callback?utm_source=github', '/auth/callback')).toBeNull()
    expect(readAppsLaunchAcquisitionUrl('https://evil.example/w/EJ83N5?utm_source=evil', '/w/EJ83N5')).toBeNull()
  })
})
