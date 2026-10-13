import {
  normalizeWorkshopId,
  parseWorkshopLink,
} from './publicUrl'

export type NativeDeepLinkTarget
  = {
    type: 'oauth-callback'
    code: string
    state: string
    closeBrowser: true
  }
  | {
    type: 'route'
    path: string
    closeBrowser: boolean
  }

export function resolveNativeDeepLink(url: string): NativeDeepLinkTarget | null {
  let parsed: URL
  try {
    parsed = new URL(url)
  }
  catch {
    return null
  }

  if (parsed.protocol === 'https:') {
    try {
      const workshopId = parseWorkshopLink(parsed.href)
      return {
        type: 'route',
        path: `/w/${workshopId}`,
        closeBrowser: false,
      }
    }
    catch {
      return null
    }
  }

  if (parsed.protocol !== 'yunlefun:')
    return null

  if (parsed.hostname === 'auth' && parsed.pathname === '/callback') {
    const code = parsed.searchParams.get('code')
    const state = parsed.searchParams.get('state')
    if (!code || !state)
      return null

    return {
      type: 'oauth-callback',
      code,
      state,
      closeBrowser: true,
    }
  }

  if (parsed.hostname === 'wallet' && (!parsed.pathname || parsed.pathname === '/')) {
    return {
      type: 'route',
      path: '/wallet',
      closeBrowser: true,
    }
  }

  if (parsed.hostname === 'workshop') {
    try {
      const workshopId = normalizeWorkshopId(
        decodeURIComponent(parsed.pathname.replace(/^\/+/, '')),
      )
      return {
        type: 'route',
        path: `/w/${workshopId}`,
        closeBrowser: true,
      }
    }
    catch {
      return null
    }
  }

  return null
}
