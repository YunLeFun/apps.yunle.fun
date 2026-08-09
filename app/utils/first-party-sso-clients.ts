export interface FirstPartySsoClient {
  appId: string
  clientId: string
  displayName: string
  iconUrl?: string
  origin: string
  redirectUri: string
  scope: readonly ['identity:bootstrap']
  authorizationNotice?: string
  supportsNativeTestSession?: boolean
}

/**
 * Exact first-party authorization registry.
 *
 * A yunle.fun origin is not trusted merely because it shares the parent
 * domain. Every app/client/redirect/scope tuple must be explicitly listed.
 */
export const FIRST_PARTY_SSO_CLIENTS = Object.freeze([
  Object.freeze({
    appId: 'ai-sfc',
    clientId: 'ai-sfc-web',
    displayName: 'AI 春联',
    iconUrl: 'https://ai-sfc.yunle.fun/brand/ai-sfc-logo-256.png',
    origin: 'https://ai-sfc.yunle.fun',
    redirectUri: 'https://ai-sfc.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
    authorizationNotice: '登录本身不会消耗云币；生成春联时会另行提示消耗。',
    supportsNativeTestSession: true,
  }),
  Object.freeze({
    appId: 'admin',
    clientId: 'admin-web',
    displayName: '云乐坊管理后台',
    origin: 'https://admin.yunle.fun',
    redirectUri: 'https://admin.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'saier',
    clientId: 'saier-web',
    displayName: '赛尔',
    origin: 'https://saier.yunle.fun',
    redirectUri: 'https://saier.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'play',
    clientId: 'play-web',
    displayName: 'Play',
    origin: 'https://play.yunle.fun',
    redirectUri: 'https://play.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    appId: 'wenta',
    clientId: 'wenta-web',
    displayName: '闻塔',
    origin: 'https://wenta.yunle.fun',
    redirectUri: 'https://wenta.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
  }),
  Object.freeze({
    // appId is the marketplace catalog slug passed into the native browser.
    appId: 'yunjian',
    clientId: 'cms-web',
    displayName: '云笺',
    origin: 'https://cms.yunle.fun',
    redirectUri: 'https://cms.yunle.fun/',
    scope: ['identity:bootstrap'] as const,
    supportsNativeTestSession: true,
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
