/** Supported native container presentations. */
export type NativePresentationKind = 'app-detail-sheet' | 'developer-sheet'

/** Supported anchors requested by a native container. */
export type NativePresentationTarget = 'reviews'

/** Validated context exposed by a native bundled-page container. */
export interface NativePresentationContext {
  /** Protocol version shared by iOS, Android, and the web adapter. */
  version: 1
  /** Native surface hosting the current first-party route. */
  kind: NativePresentationKind
  /** Optional page anchor requested by the native entry point. */
  target?: NativePresentationTarget
  /** Closes only the bundled-page container. */
  close: () => void
}

interface AndroidNativePresentationBridge {
  getContext: () => string
  close: () => void
}

interface NativePresentationWindow {
  __YLF_NATIVE_PRESENTATION__?: unknown
  YlfNativePresentationAndroid?: unknown
}

function isPresentationKind(value: unknown): value is NativePresentationKind {
  return value === 'app-detail-sheet' || value === 'developer-sheet'
}

function isPresentationTarget(
  kind: NativePresentationKind,
  value: unknown,
): value is NativePresentationTarget | undefined {
  if (kind === 'developer-sheet')
    return value === undefined || value === null
  return value === undefined || value === null || value === 'reviews'
}

function parseContext(value: unknown, close: unknown): NativePresentationContext | undefined {
  if (!value || typeof value !== 'object' || typeof close !== 'function')
    return undefined

  const context = value as Record<string, unknown>
  if (
    context.version !== 1
    || !isPresentationKind(context.kind)
    || !isPresentationTarget(context.kind, context.target)
  ) {
    return undefined
  }

  return {
    version: 1,
    kind: context.kind,
    ...(context.target === 'reviews' ? { target: context.target } : {}),
    close: close as () => void,
  }
}

function parseAndroidBridge(value: unknown): NativePresentationContext | undefined {
  if (!value || typeof value !== 'object')
    return undefined

  const bridge = value as Partial<AndroidNativePresentationBridge>
  if (typeof bridge.getContext !== 'function' || typeof bridge.close !== 'function')
    return undefined

  try {
    const context = JSON.parse(bridge.getContext()) as unknown
    return parseContext(context, () => bridge.close?.())
  }
  catch {
    return undefined
  }
}

/**
 * Resolve and validate the presentation injected before the bundled app loads.
 *
 * @param source - Window-like source used by native platforms or unit tests
 * @returns A validated native context, or `undefined` outside a native presentation
 */
export function resolveNativePresentation(
  source: unknown,
): NativePresentationContext | undefined {
  if (!source || typeof source !== 'object')
    return undefined

  const presentationSource = source as NativePresentationWindow
  const direct = presentationSource.__YLF_NATIVE_PRESENTATION__
  if (direct && typeof direct === 'object') {
    const context = direct as Record<string, unknown>
    const resolved = parseContext(context, context.close)
    if (resolved)
      return resolved
  }

  return parseAndroidBridge(presentationSource.YlfNativePresentationAndroid)
}
