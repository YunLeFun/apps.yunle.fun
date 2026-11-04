import type { HostListenerHandle } from './contracts'

/** Supported packaged hosts and the ordinary browser. */
export type HostPlatform = 'android' | 'ios' | 'web'

/** Platform facts consumed by business code without a transport dependency. */
export interface HostEnvironment {
  isNative: () => boolean
  platform: () => HostPlatform
  hasRuntime: () => boolean
}

/** Build identity exposed by the packaged application. */
export interface HostBuildInfo {
  id: string
  name: string
  version: string
  build: string
}

/** Application lifecycle and inbound URL capabilities. */
export interface HostApplication {
  getInfo: () => Promise<HostBuildInfo>
  getLaunchUrl: () => Promise<{ url: string } | undefined>
  addListener: (event: 'appUrlOpen', handler: (data: { url: string }) => void) => Promise<HostListenerHandle>
}

/** System browser presentation kept stable across native implementations. */
export interface HostBrowser {
  open: (options: { url: string, toolbarColor?: string, presentationStyle?: 'fullscreen' | 'popover' }) => Promise<void>
  close: () => Promise<void>
  addListener: (event: 'browserFinished' | 'browserPageLoaded', handler: () => void) => Promise<HostListenerHandle>
  removeAllListeners: () => Promise<void>
}

/** Semantic feedback strengths independent of plugin enums. */
export const HostImpactStyle = { Light: 'light', Medium: 'medium', Heavy: 'heavy' } as const

/** Semantic result feedback independent of plugin enums. */
export const HostNotificationType = { Success: 'success', Warning: 'warning', Error: 'error' } as const

/** Optional tactile feedback available to interactive views. */
export interface HostHaptics {
  impact: (options: { style: typeof HostImpactStyle[keyof typeof HostImpactStyle] }) => Promise<void>
  notification: (options: { type: typeof HostNotificationType[keyof typeof HostNotificationType] }) => Promise<void>
  vibrate: (options: { duration: number }) => Promise<void>
}

/** A successful native scan; cancellation is handled by the calling flow. */
export interface NativeBarcodeResult {
  ScanResult: string
  format?: number
}
