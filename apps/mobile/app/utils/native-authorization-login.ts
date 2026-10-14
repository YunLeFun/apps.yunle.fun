const PENDING_AUTHORIZATION_LOGIN_KEY = 'ylf_pending_native_authorization_login'
const REQUEST_ID_PATTERN = /^[a-z0-9-]{16,128}$/i

export const NATIVE_AUTHORIZATION_LOGIN_RETURN_TO = 'native-authorization'

function storage(): Storage | undefined {
  try {
    return typeof window === 'undefined' ? undefined : window.sessionStorage
  }
  catch {
    return undefined
  }
}

export function rememberNativeAuthorizationLogin(requestId: string): boolean {
  if (!REQUEST_ID_PATTERN.test(requestId))
    return false
  try {
    const target = storage()
    if (!target)
      return false
    target.setItem(PENDING_AUTHORIZATION_LOGIN_KEY, requestId)
    return target.getItem(PENDING_AUTHORIZATION_LOGIN_KEY) === requestId
  }
  catch {
    return false
  }
}

export function readNativeAuthorizationLogin(): string | undefined {
  try {
    const requestId = storage()?.getItem(PENDING_AUTHORIZATION_LOGIN_KEY)?.trim()
    return requestId && REQUEST_ID_PATTERN.test(requestId) ? requestId : undefined
  }
  catch {
    return undefined
  }
}

export function clearNativeAuthorizationLogin(requestId?: string): void {
  const current = readNativeAuthorizationLogin()
  try {
    if (!requestId || current === requestId)
      storage()?.removeItem(PENDING_AUTHORIZATION_LOGIN_KEY)
  }
  catch {
    // sessionStorage can become unavailable after an OS-level WebView restore.
  }
}
