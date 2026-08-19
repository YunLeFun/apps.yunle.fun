import type { NativePresentationContext } from '~/utils/native-presentation'
import { resolveNativePresentation } from '~/utils/native-presentation'

/** State exposed to first-party pages hosted by an optional native container. */
export interface UseNativePresentationResult {
  /** Validated context, absent in the regular browser or main shell. */
  presentation?: NativePresentationContext
  /** Whether the current page is hosted by a bundled native container. */
  isPresented: boolean
  /** Close the container when one is available. */
  close: () => void
}

/**
 * Access the validated native bundled-page context without coupling a page to
 * platform-specific injection details.
 *
 * @returns Native presentation state and its close action
 */
export function useNativePresentation(): UseNativePresentationResult {
  const presentation = import.meta.client
    ? resolveNativePresentation(window)
    : undefined

  return {
    presentation,
    isPresented: Boolean(presentation),
    close: () => presentation?.close(),
  }
}
