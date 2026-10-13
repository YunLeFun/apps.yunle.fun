import { describe, expect, it, vi } from 'vitest'
import { resolveNativePresentation } from '~/utils/native-presentation'

describe('native presentation context', () => {
  it('accepts a versioned direct context and delegates close', () => {
    const close = vi.fn()
    const presentation = resolveNativePresentation({
      __YLF_NATIVE_PRESENTATION__: {
        version: 1,
        kind: 'app-detail-sheet',
        target: 'reviews',
        close,
      },
    })

    expect(presentation).toMatchObject({
      version: 1,
      kind: 'app-detail-sheet',
      target: 'reviews',
    })
    presentation?.close()
    expect(close).toHaveBeenCalledOnce()
  })

  it('uses the Android bridge fallback when document-start scripts are unavailable', () => {
    const close = vi.fn()
    const presentation = resolveNativePresentation({
      YlfNativePresentationAndroid: {
        getContext: () => JSON.stringify({ version: 1, kind: 'developer-sheet' }),
        close,
      },
    })

    expect(presentation).toMatchObject({ version: 1, kind: 'developer-sheet' })
    presentation?.close()
    expect(close).toHaveBeenCalledOnce()
  })

  it.each([
    { version: 2, kind: 'app-detail-sheet' },
    { version: 1, kind: 'unknown' },
    { version: 1, kind: 'developer-sheet', target: 'reviews' },
    { version: 1, kind: 'app-detail-sheet', target: 'unknown' },
  ])('rejects an unsupported context: %o', (context) => {
    expect(resolveNativePresentation({
      __YLF_NATIVE_PRESENTATION__: { ...context, close: vi.fn() },
    })).toBeUndefined()
  })

  it('fails closed for malformed Android context JSON', () => {
    expect(resolveNativePresentation({
      YlfNativePresentationAndroid: {
        getContext: () => '{invalid',
        close: vi.fn(),
      },
    })).toBeUndefined()
  })
})
