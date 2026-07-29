import type {
  HostAuthorizationEvent,
  HostAuthorizationRequest,
} from '~/composables/useBrowser'
import {
  findFirstPartySsoClient,
} from '~/utils/first-party-sso-clients'

const IDENTITY_SCOPE = 'identity:bootstrap'
const SSO_VALUE_RE = /^[\w-]{32,128}$/
const SSO_CODE_RE = /^[\w-]{32,256}$/

export interface ValidatedHostAuthorization {
  appId: string
  clientId: string
  codeChallenge: string
  nonce: string
  redirectUri: string
  scope: typeof IDENTITY_SCOPE
  targetOrigin: string
}

export function validateHostAuthorization(
  event: HostAuthorizationEvent,
): ValidatedHostAuthorization {
  const request = event.request as HostAuthorizationRequest
  const client = findFirstPartySsoClient(event.appId, event.sourceOrigin)
  if (
    !client
    || request.clientId !== client.clientId
    || request.redirectUri !== client.redirectUri
    || request.codeChallengeMethod !== 'S256'
    || !SSO_VALUE_RE.test(request.nonce)
    || !SSO_VALUE_RE.test(request.codeChallenge)
    || !Array.isArray(request.scope)
    || request.scope.length !== 1
    || request.scope[0] !== client.scope[0]
  ) {
    throw new HostIdentityBrokerError(
      'HOST_AUTH_INVALID_REQUEST',
      '内嵌应用请求的统一登录参数无效',
    )
  }
  return {
    appId: client.appId,
    clientId: client.clientId,
    codeChallenge: request.codeChallenge,
    nonce: request.nonce,
    redirectUri: client.redirectUri,
    scope: IDENTITY_SCOPE,
    targetOrigin: client.origin,
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
