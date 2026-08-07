import { FIRST_PARTY_SSO_CLIENTS } from '../../app/utils/first-party-sso-clients'

export interface NativeTestSessionProxyOptions {
  brokerBaseUrl: string
  serviceToken: string
  request?: (url: string, options: Record<string, unknown>) => Promise<unknown>
}

export interface NativeTestSsoRequest {
  mode: 'redirect'
  clientId: string
  targetOrigin: string
  returnUrl: string
  scope: 'identity:bootstrap'
  nonce: string
  codeChallenge: string
  codeChallengeMethod: 'S256'
}

const NATIVE_TEST_SSO_APP_IDS = new Set(['ai-sfc', 'yunjian'])

export class NativeTestSessionInputError extends Error {
  override name = 'NativeTestSessionInputError'
}

export async function exchangeNativeTestSession(
  input: { publicAlias: string, challengeId: string, code: string },
  options: NativeTestSessionProxyOptions,
) {
  const body = {
    publicAlias: normalizeAlias(input?.publicAlias),
    challengeId: requireReference(input?.challengeId),
    code: requireCode(input?.code),
  }
  const response = await callBroker('exchange', body, options)
  if (!isRecord(response)
    || typeof response.hostSession !== 'string'
    || response.hostSession.length < 8
    || response.hostSession.length > 4096
    || typeof response.expiresAt !== 'number'
    || !Number.isSafeInteger(response.expiresAt)
    || response.expiresAt <= Date.now()
    || !isRecord(response.account)
    || normalizeAlias(response.account.publicAlias) !== body.publicAlias
    || typeof response.account.virtualPhone !== 'string'
    || typeof response.account.displayName !== 'string') {
    throw new Error('Native test session broker returned an invalid response')
  }
  return {
    hostSession: response.hostSession,
    expiresAt: response.expiresAt as number,
    account: {
      publicAlias: body.publicAlias,
      virtualPhone: response.account.virtualPhone,
      displayName: response.account.displayName,
    },
  }
}

export async function authorizeNativeTestSession(
  input: { hostSession: string, request: NativeTestSsoRequest },
  options: NativeTestSessionProxyOptions,
) {
  if (typeof input?.hostSession !== 'string' || input.hostSession.length < 8 || input.hostSession.length > 4096)
    throw new NativeTestSessionInputError('Native test host session is invalid')
  assertNativeSsoRequest(input.request)
  const response = await callBroker('authorize', {
    hostSession: input.hostSession,
    request: input.request,
  }, options)
  if (!isRecord(response)
    || typeof response.code !== 'string'
    || !/^[\w-]{43}$/.test(response.code)
    || typeof response.expiresAt !== 'number'
    || !Number.isSafeInteger(response.expiresAt)
    || response.expiresAt <= Date.now()) {
    throw new Error('Native test SSO broker returned an invalid response')
  }
  return { ok: true as const, code: response.code, expiresAt: response.expiresAt as number }
}

async function callBroker(
  action: 'exchange' | 'authorize',
  body: Record<string, unknown>,
  options: NativeTestSessionProxyOptions,
): Promise<unknown> {
  const baseUrl = normalizeBrokerBaseUrl(options.brokerBaseUrl)
  if (typeof options.serviceToken !== 'string'
    || options.serviceToken.length < 32
    || options.serviceToken.length > 512) {
    throw new Error('Native test session service token is not configured')
  }
  const request = options.request ?? ((url, requestOptions) => $fetch(url, requestOptions))
  return await request(`${baseUrl}/api/internal/test-broker/native-session/${action}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${options.serviceToken}` },
    body,
    retry: 0,
    timeout: 10_000,
  })
}

function assertNativeSsoRequest(request: NativeTestSsoRequest): void {
  const registeredClient = request && FIRST_PARTY_SSO_CLIENTS.find(client => (
    NATIVE_TEST_SSO_APP_IDS.has(client.appId)
    && client.clientId === request.clientId
    && client.origin === request.targetOrigin
    && client.redirectUri === request.returnUrl
    && client.scope[0] === request.scope
  ))
  if (!registeredClient
    || request.mode !== 'redirect'
    || request.scope !== 'identity:bootstrap'
    || request.codeChallengeMethod !== 'S256'
    || !/^[\w-]{32,128}$/.test(request.nonce)
    || !/^[\w-]{43}$/.test(request.codeChallenge)) {
    throw new NativeTestSessionInputError('Native test SSO request is invalid')
  }
}

function normalizeBrokerBaseUrl(raw: string): string {
  let url: URL
  try {
    url = new URL(raw)
  }
  catch {
    throw new Error('Native test session broker URL is invalid')
  }
  const loopback = url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '[::1]'
  if (url.username
    || url.password
    || url.pathname !== '/'
    || url.search
    || url.hash
    || (url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback))) {
    throw new Error('Native test session broker URL is invalid')
  }
  return url.origin
}

function normalizeAlias(value: unknown): string {
  const alias = typeof value === 'string' ? value.trim().toLowerCase() : ''
  if (!/^[a-z0-9][a-z0-9-]{1,62}@yunlefun$/.test(alias))
    throw new NativeTestSessionInputError('Native test public alias is invalid')
  return alias
}

function requireReference(value: unknown): string {
  if (typeof value !== 'string' || !/^[\w:-]{4,128}$/.test(value))
    throw new NativeTestSessionInputError('Native test challenge id is invalid')
  return value
}

function requireCode(value: unknown): string {
  if (typeof value !== 'string' || !/^\d{6}$/.test(value))
    throw new NativeTestSessionInputError('Native test verification code is invalid')
  return value
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
