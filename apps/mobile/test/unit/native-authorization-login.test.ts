import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  clearNativeAuthorizationLogin,
  readNativeAuthorizationLogin,
  rememberNativeAuthorizationLogin,
} from '../../app/utils/native-authorization-login'

function installSessionStorage() {
  const values = new Map<string, string>()
  vi.stubGlobal('window', {
    sessionStorage: {
      getItem: (key: string) => values.get(key) ?? null,
      removeItem: (key: string) => values.delete(key),
      setItem: (key: string, value: string) => values.set(key, value),
    },
  })
}

describe('native authorization login handoff', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('stores only bounded native request identifiers', () => {
    installSessionStorage()
    expect(rememberNativeAuthorizationLogin('native-request-1234')).toBe(true)
    expect(readNativeAuthorizationLogin()).toBe('native-request-1234')
    expect(rememberNativeAuthorizationLogin('../bad')).toBe(false)
    expect(readNativeAuthorizationLogin()).toBe('native-request-1234')
  })

  it('clears only the matching pending request', () => {
    installSessionStorage()
    rememberNativeAuthorizationLogin('native-request-1234')
    clearNativeAuthorizationLogin('different-request-1234')
    expect(readNativeAuthorizationLogin()).toBe('native-request-1234')
    clearNativeAuthorizationLogin('native-request-1234')
    expect(readNativeAuthorizationLogin()).toBeUndefined()
  })

  it('fails closed when session storage is unavailable', () => {
    vi.stubGlobal('window', {})
    expect(rememberNativeAuthorizationLogin('native-request-1234')).toBe(false)
    expect(readNativeAuthorizationLogin()).toBeUndefined()
  })
})
