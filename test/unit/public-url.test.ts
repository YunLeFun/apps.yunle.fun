import { describe, expect, it } from 'vitest'
import {
  buildPublicWorkshopUrl,
  DEFAULT_PUBLIC_APP_BASE_URL,
} from '../../app/utils/publicUrl'

describe('public workshop URL', () => {
  it('uses the production HTTPS origin by default', () => {
    expect(buildPublicWorkshopUrl('ej83n5')).toBe(
      `${DEFAULT_PUBLIC_APP_BASE_URL}/w/EJ83N5`,
    )
  })

  it('allows an explicitly configured HTTPS deployment origin', () => {
    expect(buildPublicWorkshopUrl('ABC123', 'https://staging.apps.yunle.fun/'))
      .toBe('https://staging.apps.yunle.fun/w/ABC123')
  })

  it.each([
    'capacitor://localhost',
    'ionic://localhost',
    'http://localhost:8001',
    'not a url',
  ])('never exposes a non-public origin: %s', (origin) => {
    expect(buildPublicWorkshopUrl('EJ83N5', origin))
      .toBe('https://apps.yunle.fun/w/EJ83N5')
  })

  it('returns an empty URL without a workshop id', () => {
    expect(buildPublicWorkshopUrl('  ')).toBe('')
  })
})
