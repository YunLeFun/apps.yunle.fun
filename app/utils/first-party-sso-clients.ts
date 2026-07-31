export interface FirstPartySsoClient {
  appId: string
  clientId: string
  origin: string
  redirectUri: string
  scope: readonly ['identity:bootstrap']
}

/**
 * Exact first-party authorization registry.
 *
 * A yunle.fun origin is not trusted merely because it shares the parent
 * domain. Every app/client/redirect/scope tuple must be explicitly listed.
 */
export const FIRST_PARTY_SSO_CLIENTS = Object.freeze([
  Object.freeze({
    appId: 'admin',
    clientId: 'admin-web',
    origin: 'https://admin.yunle.fun',
    redirectUri: 'https://admin.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'saier',
    clientId: 'saier-web',
    origin: 'https://saier.yunle.fun',
    redirectUri: 'https://saier.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'play',
    clientId: 'play-web',
    origin: 'https://play.yunle.fun',
    redirectUri: 'https://play.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'wenta',
    clientId: 'wenta-web',
    origin: 'https://wenta.yunle.fun',
    redirectUri: 'https://wenta.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'cms',
    clientId: 'cms-web',
    origin: 'https://cms.yunle.fun',
    redirectUri: 'https://cms.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
] satisfies readonly FirstPartySsoClient[])

export function findFirstPartySsoClient(
  appId: string,
  origin: string,
): FirstPartySsoClient | undefined {
  return FIRST_PARTY_SSO_CLIENTS.find(client => (
    client.appId === appId && client.origin === origin
  ))
}
