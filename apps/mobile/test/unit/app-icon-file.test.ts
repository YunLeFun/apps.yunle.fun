import { describe, expect, it } from 'vitest'
import {
  APP_ICON_INPUT_MAX_BYTES,
  validateAppIconInput,
  validatePassiveSvg,
} from '../../app/utils/appIconFile'

describe('app icon source validation', () => {
  it('allows supported raster and passive SVG inputs', () => {
    expect(() => validateAppIconInput({ type: 'image/png', size: 1024 })).not.toThrow()
    expect(() => validatePassiveSvg('<svg viewBox="0 0 64 64"><path d="M0 0h1v1z"/></svg>')).not.toThrow()
  })

  it('rejects unsupported, oversized, and active SVG inputs', () => {
    expect(() => validateAppIconInput({ type: 'image/jpeg', size: 1024 })).toThrow(/PNG/)
    expect(() => validateAppIconInput({ type: 'image/png', size: APP_ICON_INPUT_MAX_BYTES + 1 })).toThrow(/5 MB/)
    expect(() => validatePassiveSvg('<svg><script>alert(1)</script></svg>')).toThrow(/活动内容/)
    expect(() => validatePassiveSvg('<svg><image href="https://evil.example/a.png"/></svg>')).toThrow(/外部资源/)
  })
})
