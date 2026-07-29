import type {
  HostAuthorizationEvent,
  HostAuthorizationRequest,
} from '~/composables/useBrowser'

const PLAY_ORIGIN = 'https://play.yunle.fun'
const PLAY_CLIENT_ID = 'play-web'
const PLAY_REDIRECT_URI = 'https://play.yunle.fun/'
const IDENTITY_SCOPE = 'identity:bootstrap'
const SSO_VALUE_RE = /^[\w-]{32,128}$/
const SSO_CODE_RE = /^[\w-]{32,256}$/

export interface ValidatedHostAuthorization {
  clientId: typeof PLAY_CLIENT_ID
  codeChallenge: string
  nonce: string
  redirectUri: typeof PLAY_REDIRECT_URI
  scope: typeof IDENTITY_SCOPE
  targetOrigin: typeof PLAY_ORIGIN
}

export function validateHostAuthorization(
  event: HostAuthorizationEvent,
): ValidatedHostAuthorization {
  const request = event.request as HostAuthorizationRequest
  if (
    event.sourceOrigin !== PLAY_ORIGIN
    || request.clientId !== PLAY_CLIENT_ID
    || request.redirectUri !== PLAY_REDIRECT_URI
    || request.codeChallengeMethod !== 'S256'
    || !SSO_VALUE_RE.test(request.nonce)
    || !SSO_VALUE_RE.test(request.codeChallenge)
    || !Array.isArray(request.scope)
    || request.scope.length !== 1
    || request.scope[0] !== IDENTITY_SCOPE
  ) {
    throw new HostIdentityBrokerError(
      'HOST_AUTH_INVALID_REQUEST',
      '内嵌应用请求的统一登录参数无效',
    )
  }
  return {
    clientId: PLAY_CLIENT_ID,
    codeChallenge: request.codeChallenge,
    nonce: request.nonce,
    redirectUri: PLAY_REDIRECT_URI,
    scope: IDENTITY_SCOPE,
    targetOrigin: PLAY_ORIGIN,
  }
}

export function readIssuedAuthorizationCode(input: unknown): {
  code: string
  expiresAt?: number
} {
  const envelope = isRecord(input) && isRecord(input.result)
    ? input.result
    : input
  if (
    !isRecord(envelope)
    || envelope.ok !== true
    || typeof envelope.code !== 'string'
    || !SSO_CODE_RE.test(envelope.code)
  ) {
    throw new HostIdentityBrokerError(
      'HOST_AUTH_FAILED',
      '统一身份服务未返回有效授权码',
    )
  }
  return {
    code: envelope.code,
    ...(typeof envelope.expiresAt === 'number'
      ? { expiresAt: envelope.expiresAt }
      : {}),
  }
}

export class HostIdentityBrokerError extends Error {
  constructor(
    readonly code:
      | 'HOST_AUTH_INVALID_REQUEST'
      | 'HOST_AUTH_REQUIRED'
      | 'HOST_AUTH_FAILED',
    message: string,
  ) {
    super(message)
    this.name = 'HostIdentityBrokerError'
  }
}

function isRecord(input: unknown): input is Record<string, unknown> {
  return input !== null && typeof input === 'object' && !Array.isArray(input)
}
