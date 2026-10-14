import type { PluginListenerHandle } from '@capacitor/core'
import type { ExternalLinkMode } from '~/stores/settings'
import { registerPlugin } from '@capacitor/core'

/** 应用目录传递给宿主容器的稳定元信息。 */
export interface HostAppInfo {
  id?: string
  /** URL slug（评价数据以 slug 优先作为 key）。 */
  slug?: string
  name?: string
  emoji?: string
  logo?: string
  themeColor?: string
  description?: string
  category?: string
  /** Stable, unique catalog owner handle used for profile routing. */
  developer?: string
  /** Non-unique display name shown in native application surfaces. */
  developerName?: string
  rating?: number
  ratingCount?: number
}

/** 平台原生容器保活的页面会话摘要。 */
export interface HostSession {
  /** Native viewport snapshot, kept in memory and refreshed on every minimize. */
  previewImage?: string
  id: string
  key: string
  name: string
  emoji?: string
  logo?: string
  themeColor?: string
  url: string
  title?: string
  displayMode?: 'immersive' | 'titlebar'
}

/** 原生会话池快照；旧版或单会话平台可以不返回自动上限。 */
export interface HostSessionSnapshot {
  sessions: HostSession[]
  sessionLimit?: number
}

/** 页面向宿主申请当前账号授权时使用的统一 PKCE 请求。 */
export interface HostAuthorizationRequest {
  clientId: string
  codeChallenge: string
  codeChallengeMethod: 'S256'
  nonce: string
  redirectUri: string
  scope: string[]
  prompt?: 'consent' | 'select_account'
}

/** 平台适配器上报给 Web 身份代理的授权事件。 */
export interface HostAuthorizationEvent {
  appId: string
  request: HostAuthorizationRequest
  requestId: string
  sourceOrigin: string
}

/**
 * Apps Web 层与 iOS / Android 原生容器之间唯一的跨平台协议。
 *
 * 平台实现负责可信来源、主 frame、用户确认和 pending request 生命周期；
 * Web 层只负责交换一次性授权码，不向页面暴露宿主 token。
 */
export interface HostRuntimePlugin {
  open: (options: {
    url: string
    title?: string
    toolbarColor?: string
    app?: HostAppInfo
    displayMode?: 'immersive' | 'titlebar'
    externalLinkMode?: ExternalLinkMode
    trustedHosts?: string[]
  }) => Promise<void>
  close: () => Promise<void>
  updateAppInfo: (options: { app: HostAppInfo }) => Promise<void>
  /** Applies the account entitlement and preferred native WebView session limit. */
  configureSessionPolicy: (options: {
    isMember: boolean
    preferredLimit?: number
  }) => Promise<{ sessionLimit: number }>
  resumeSession: (options: { id: string }) => Promise<void>
  listSessions: () => Promise<HostSessionSnapshot>
  endSession: (options: { id: string }) => Promise<void>
  confirmAuthorization: (options: {
    requestId: string
    applicationIconUrl?: string
    applicationName: string
    applicationOrigin: string
    accountName: string
    accountAvatarUrl?: string
    permissionDescription: string
    authorizationNotice?: string
  }) => Promise<{
    allowed: boolean
    choice?: 'current' | 'other' | 'cancel'
  }>
  /** 暂停当前页面授权并将云乐坊登录页带到前台。 */
  requestHostLogin: (options: { requestId: string }) => Promise<void>
  /** 登录成功后恢复原页面，并重新投递仍然有效的授权请求。 */
  resumeAuthorizationAfterLogin: (options: { requestId: string }) => Promise<void>
  /** 用户离开登录页时取消并恢复原页面，避免留下悬空请求。 */
  cancelAuthorizationLogin: (options: { requestId: string }) => Promise<void>
  authorizeWithOtherAccount: (options: { requestId: string }) => Promise<void>
  resolveAuthorization: (options: {
    requestId: string
    result?: Record<string, unknown>
    error?: string
  }) => Promise<void>
  clearIdentitySessions: () => Promise<void>
  addListener: ((event: 'browserFinished', handler: () => void) => Promise<PluginListenerHandle>)
    & ((event: 'detailRequested', handler: (data: { appId: string }) => void) => Promise<PluginListenerHandle>)
    & ((event: 'sessionsChanged', handler: (data: HostSessionSnapshot) => void) => Promise<PluginListenerHandle>)
    & ((event: 'browserMinimized', handler: (data: { name: string, key?: string }) => void) => Promise<PluginListenerHandle>)
    & ((event: 'authorizationRequested', handler: (data: HostAuthorizationEvent) => void) => Promise<PluginListenerHandle>)
  removeAllListeners: () => Promise<void>
}

export const HostRuntime = registerPlugin<HostRuntimePlugin>('HostRuntime')
