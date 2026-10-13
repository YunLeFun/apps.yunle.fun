export const SHELL_REQUEST = 'desktop:invoke'
export const SHELL_STATE = 'desktop:state'
export const GUEST_ENVIRONMENT = 'guest:environment'
export const SHELL_ORIGIN = 'app://shell'

export type GuestCommand = 'back' | 'forward' | 'reload' | 'close'
export interface ViewportBounds { x: number, y: number, width: number, height: number }
export interface CatalogEntry {
  id: string
  slug: string
  name: string
  description: string
  emoji: string
  category: string
  websiteUrl: string
  available: boolean
  unavailableReason: string
}
export interface CatalogState {
  apps: CatalogEntry[]
  source: 'snapshot' | 'cache' | 'online'
  loading: boolean
  error: string
  updatedAt: number | null
}
export interface GuestState {
  open: boolean
  appId: string
  title: string
  url: string
  loading: boolean
  canGoBack: boolean
  canGoForward: boolean
  error: string
}
export interface DesktopState {
  version: string
  platform: string
  electron: string
  chromium: string
  catalog: CatalogState
  guest: GuestState
  updates: { status: 'disabled' | 'idle' | 'checking' | 'available' | 'downloaded' | 'error', message: string }
}
export type DesktopRequest
  = | { type: 'snapshot' }
    | { type: 'refresh-catalog' }
    | { type: 'open-app', appId: string }
    | { type: 'guest-command', command: GuestCommand }
    | { type: 'viewport', bounds: ViewportBounds | null }
    | { type: 'theme', preference: 'system' | 'light' | 'dark' }
    | { type: 'check-updates' }

export interface DesktopBridge {
  version: 1
  getState: () => Promise<DesktopState>
  refreshCatalog: () => Promise<DesktopState>
  openApp: (appId: string) => Promise<DesktopState>
  command: (command: GuestCommand) => Promise<DesktopState>
  setViewport: (bounds: ViewportBounds | null) => Promise<DesktopState>
  setTheme: (preference: 'system' | 'light' | 'dark') => Promise<DesktopState>
  checkUpdates: () => Promise<DesktopState>
  onState: (listener: (state: DesktopState) => void) => () => void
}
