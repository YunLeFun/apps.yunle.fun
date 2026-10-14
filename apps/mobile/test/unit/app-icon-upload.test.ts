import { Buffer } from 'node:buffer'
import { describe, expect, it } from 'vitest'
import {
  normalizeAppIconRole,
  NORMALIZED_APP_ICON_MAX_BYTES,
  validateNormalizedAppIcon,
} from '../../server/utils/app-icon-upload'

function pngHeader(width = 1024, height = 1024) {
  const bytes = Buffer.alloc(24)
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).copy(bytes)
  bytes.write('IHDR', 12, 'ascii')
  bytes.writeUInt32BE(width, 16)
  bytes.writeUInt32BE(height, 20)
  return bytes
}

describe('normalized app icon upload validation', () => {
  it('accepts both roles and a 1024px PNG', () => {
    expect(normalizeAppIconRole('app-icon')).toBe('app-icon')
    expect(normalizeAppIconRole('mark')).toBe('mark')
    expect(validateNormalizedAppIcon(pngHeader(), 'image/png')).toEqual({ width: 1024, height: 1024 })
  })

  it('rejects invalid roles, formats, dimensions, and sizes', () => {
    expect(() => normalizeAppIconRole('logo')).toThrow(/类型/)
    expect(() => validateNormalizedAppIcon(pngHeader(), 'image/webp')).toThrow(/PNG/)
    expect(() => validateNormalizedAppIcon(pngHeader(512, 512), 'image/png')).toThrow(/1024/)
    expect(() => validateNormalizedAppIcon(Buffer.alloc(NORMALIZED_APP_ICON_MAX_BYTES + 1), 'image/png')).toThrow(/4 MB/)
  })
})
