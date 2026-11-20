import { describe, expect, it } from 'vitest'
import {
  boardAppUrl,
  buildPublicWorkshopUrl,
  DEFAULT_PUBLIC_APP_BASE_URL,
} from '../../app/utils/publicUrl'

it('opens the exact canonical board from the browser fallback', () => {
  const id = '9fad9eef-b0da-4b0f-8161-79bfc59c88bc'
  const path = `/boards/${id}`
  expect(boardAppUrl(path)).toBe(`yunlefun://board/${id}`)
  for (const candidate of [`${path}/`, `${path}?role=player`, `${path}#login`, `${path}\n`, `/boards/%39${id.slice(1)}`, '/boards/invalid'])
    expect(boardAppUrl(candidate)).toBeNull()
})

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
