import { describe, expect, it } from 'vitest'
import { parseWorkshopLink } from '../../app/composables/useWorkshopScan'

describe('workshop scan', () => {
  it('accepts only stable personal workshop links and returns the short id', () => {
    expect(parseWorkshopLink('https://apps.yunle.fun/w/7KM2QX')).toBe('7KM2QX')
    expect(parseWorkshopLink('https://apps.yunle.fun/w/7km2qx?from=qr')).toBe('7KM2QX')
    expect(() => parseWorkshopLink('https://example.com/w/7KM2QX')).toThrow(/个人工坊/)
    expect(() => parseWorkshopLink('{"name":"old market","apps":[]}')).toThrow(/个人工坊/)
  })
})
