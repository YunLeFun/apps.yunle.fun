import type { AcquisitionContext } from './acquisition'
import type {
  HostAuthorizationEvent,
  HostAuthorizationRequest,
} from '~/host-runtime'
import { sanitizeAcquisitionContext } from './acquisition'

const SSO_ISSUER = 'https://www.yunle.fun'
const IDENTITY_SCOPE = 'identity:bootstrap'
const IDENTITY_PERMISSION_DESCRIPTION = '账号标识、昵称和头像'
const CLIENT_ID_RE = /^[a-z0-9][a-z0-9-]{1,127}$/
const APP_ID_RE = /^[a-z0-9][a-z0-9-]{0,127}$/
const NONCE_RE = /^[\w-]{32,128}$/
const PKCE_CHALLENGE_RE = /^[\w-]{43}$/
const SSO_CODE_RE = /^[\w-]{43}$/
const FINGERPRINT_RE = /^[a-f0-9]{64}$/

export interface HostAuthorizationResolutionRequest {
  action: 'resolveSsoAuthorization'
  mode: 'redirect'
  clientId: string
  targetOrigin: string
  returnUrl: string
  scope: typeof IDENTITY_SCOPE
  nonce: string
  codeChallenge: string
  codeChallengeMethod: 'S256'
  prompt?: 'consent' | 'select_account'
  acquisition?: AcquisitionContext
}

export interface ValidatedHostAuthorization {
  appId: string
  applicationIconUrl?: string
  applicationName: string
  applicationOrigin: string
  clientId: string
  codeChallenge: string
  consent: 'explicit' | 'trusted'
  issuer: typeof SSO_ISSUER
  nonce: string
  permissionDescription: typeof IDENTITY_PERMISSION_DESCRIPTION
  policyVersion: string
  prompt?: 'consent' | 'select_account'
  redirectUri: string
  registrationFingerprint: string
  scope: typeof IDENTITY_SCOPE
  targetOrigin: string
  issueRequest: Omit<HostAuthorizationResolutionRequest, 'action' | 'prompt'>
}

/**
 * Performs only protocol-shape validation locally. Client authorization and
 * presentation metadata are resolved by the central signed Registry.
 */
export function createHostAuthorizationResolutionRequest(
  event: HostAuthorizationEvent,
): HostAuthorizationResolutionRequest {
  const request = event.request as HostAuthorizationRequest
  const sourceOrigin = exactHttpsOrigin(event.sourceOrigin)
  const redirectUri = exactHttpsUrl(request?.redirectUri)
  if (
    !sourceOrigin
    || !CLIENT_ID_RE.test(request?.clientId || '')
    || !redirectUri
    || new URL(redirectUri).origin !== sourceOrigin
    || request?.codeChallengeMethod !== 'S256'
    || !NONCE_RE.test(request?.nonce || '')
    || !PKCE_CHALLENGE_RE.test(request?.codeChallenge || '')
    || !Array.isArray(request?.scope)
    || request.scope.length !== 1
    || request.scope[0] !== IDENTITY_SCOPE
    || (request.prompt !== undefined
      && request.prompt !== 'consent'
      && request.prompt !== 'select_account')
  ) {
    throw invalidRequest()
  }

  const acquisition = sanitizeAcquisitionContext(request.acquisition)
  return {
    action: 'resolveSsoAuthorization',
    mode: 'redirect',
    clientId: request.clientId,
    targetOrigin: sourceOrigin,
    returnUrl: redirectUri,
    scope: IDENTITY_SCOPE,
    nonce: request.nonce,
    codeChallenge: request.codeChallenge,
    codeChallengeMethod: 'S256',
    ...(request.prompt ? { prompt: request.prompt } : {}),
    ...(acquisition ? { acquisition } : {}),
  }
}

/**
 * Accepts a resolution only when every protocol field is echoed exactly. This
 * prevents a stale, confused, or incorrectly routed policy response from being
 * used to issue a code for another request.
 */
export function readResolvedHostAuthorization(
  input: unknown,
  pending: HostAuthorizationResolutionRequest,
): ValidatedHostAuthorization {
  const envelope = unwrapEnvelope(input)
  if (isRecord(envelope) && envelope.ok === false)
    throw invalidRequest()
  if (!isRecord(envelope) || envelope.ok !== true)
    throw failedResolution()

  const request = envelope.request
  const presentation = envelope.presentation
  if (!isRecord(request) || !isRecord(presentation))
    throw failedResolution()

  const requestMatches = request.mode === pending.mode
    && request.clientId === pending.clientId
    && request.targetOrigin === pending.targetOrigin
    && request.returnUrl === pending.returnUrl
    && request.scope === pending.scope
    && request.nonce === pending.nonce
    && request.codeChallenge === pending.codeChallenge
    && request.codeChallengeMethod === pending.codeChallengeMethod
  const prompt = presentation.prompt
  const promptAllowed = prompt === undefined || prompt === 'consent' || prompt === 'select_account'
  const promptMatches = pending.prompt
    ? prompt === pending.prompt
    : prompt === undefined || prompt === 'consent'
  const consentPromptMatches = presentation.consent !== 'explicit'
    || prompt === 'consent'
    || prompt === 'select_account'
  const iconUrl = presentation.applicationIconUrl

  if (
    envelope.issuer !== SSO_ISSUER
    || typeof envelope.policyVersion !== 'string'
    || !envelope.policyVersion
    || envelope.policyVersion.length > 128
    || typeof envelope.registrationFingerprint !== 'string'
    || !FINGERPRINT_RE.test(envelope.registrationFingerprint)
    || !requestMatches
    || typeof presentation.appId !== 'string'
    || !APP_ID_RE.test(presentation.appId)
    || !isDisplayName(presentation.applicationName)
    || presentation.applicationOrigin !== pending.targetOrigin
    || presentation.permissionDescription !== IDENTITY_PERMISSION_DESCRIPTION
    || (presentation.consent !== 'explicit' && presentation.consent !== 'trusted')
    || !promptAllowed
    || !promptMatches
    || !consentPromptMatches
    || (iconUrl !== undefined && !exactHttpsUrl(iconUrl))
  ) {
    throw failedResolution()
  }

  return {
    appId: presentation.appId,
    ...(typeof iconUrl === 'string' ? { applicationIconUrl: iconUrl } : {}),
    applicationName: presentation.applicationName,
    applicationOrigin: pending.targetOrigin,
    clientId: pending.clientId,
    codeChallenge: pending.codeChallenge,
    consent: presentation.consent,
    issuer: SSO_ISSUER,
    nonce: pending.nonce,
    permissionDescription: IDENTITY_PERMISSION_DESCRIPTION,
    policyVersion: envelope.policyVersion,
    ...(prompt ? { prompt } : {}),
    redirectUri: pending.returnUrl,
    registrationFingerprint: envelope.registrationFingerprint,
    scope: IDENTITY_SCOPE,
    targetOrigin: pending.targetOrigin,
    issueRequest: {
      mode: pending.mode,
      clientId: pending.clientId,
      targetOrigin: pending.targetOrigin,
      returnUrl: pending.returnUrl,
      scope: pending.scope,
      nonce: pending.nonce,
      codeChallenge: pending.codeChallenge,
      codeChallengeMethod: pending.codeChallengeMethod,
      ...(pending.acquisition ? { acquisition: pending.acquisition } : {}),
    },
  }
}

export function readIssuedAuthorizationCode(input: unknown): {
  code: string
  expiresAt?: number
} {
  const envelope = unwrapEnvelope(input)
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
      | 'HOST_AUTH_DENIED'
      | 'HOST_AUTH_FAILED',
    message: string,
  ) {
    super(message)
    this.name = 'HostIdentityBrokerError'
  }
}

function exactHttpsOrigin(input: unknown): string {
  if (typeof input !== 'string')
    return ''
  try {
    const url = new URL(input)
    return url.protocol === 'https:'
      && !url.username
      && !url.password
      && !url.search
      && !url.hash
      && url.pathname === '/'
      && url.origin === input
      && !url.hostname.endsWith('.')
      ? input
      : ''
  }
  catch {
    return ''
  }
}

function exactHttpsUrl(input: unknown): string {
  if (typeof input !== 'string')
    return ''
  try {
    const url = new URL(input)
    return url.protocol === 'https:'
      && !url.username
      && !url.password
      && !url.hash
      && !url.hostname.endsWith('.')
      && url.toString() === input
      ? input
      : ''
  }
  catch {
    return ''
  }
}

function isDisplayName(input: unknown): input is string {
  return typeof input === 'string'
    && input === input.trim()
    && input.length > 0
    && input.length <= 80
}

function invalidRequest(): HostIdentityBrokerError {
  return new HostIdentityBrokerError(
    'HOST_AUTH_INVALID_REQUEST',
    '内嵌应用请求未获统一身份策略授权',
  )
}

function failedResolution(): HostIdentityBrokerError {
  return new HostIdentityBrokerError(
    'HOST_AUTH_FAILED',
    '统一身份服务返回了无效的授权策略',
  )
}

function unwrapEnvelope(input: unknown): unknown {
  return isRecord(input) && isRecord(input.result)
    ? input.result
    : input
}

function isRecord(input: unknown): input is Record<string, unknown> {
  return input !== null && typeof input === 'object' && !Array.isArray(input)
}
