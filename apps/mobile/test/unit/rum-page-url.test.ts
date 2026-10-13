import { describe, expect, it } from 'vitest'
import { getRumPageUrl } from '../../app/utils/rum'

describe('getRumPageUrl', () => {
  it('maps Capacitor pages to the public HTTPS origin', () => {
    expect(getRumPageUrl({
      href: 'capacitor://localhost/tabs/home?source=smoke#today',
      pathname: '/tabs/home',
      search: '?source=smoke',
      hash: '#today',
    }, true)).toBe('https://apps.yunle.fun/tabs/home?source=smoke#today')
  })

  it('keeps the browser URL unchanged', () => {
    expect(getRumPageUrl({
      href: 'https://apps.yunle.fun/tabs/discovery?q=cloud',
      pathname: '/tabs/discovery',
      search: '?q=cloud',
      hash: '',
    }, false)).toBe('https://apps.yunle.fun/tabs/discovery?q=cloud')
  })
})
