import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { resolveNativeDeepLink } from '../../app/utils/nativeDeepLink'

describe('native deep links', () => {
  it('maps a public workshop Universal Link to the local route', () => {
    expect(resolveNativeDeepLink('https://apps.yunle.fun/w/ej83n5?from=qr'))
      .toEqual({
        type: 'route',
        path: '/w/EJ83N5',
        closeBrowser: false,
      })
  })

  it('supports the workshop custom scheme as a fallback', () => {
    expect(resolveNativeDeepLink('yunlefun://workshop/EJ83N5'))
      .toEqual({
        type: 'route',
        path: '/w/EJ83N5',
        closeBrowser: true,
      })
  })

  it('preserves auth and wallet deep links', () => {
    expect(resolveNativeDeepLink('yunlefun://auth/callback?code=abc&state=xyz'))
      .toEqual({
        type: 'oauth-callback',
        code: 'abc',
        state: 'xyz',
        closeBrowser: true,
      })
    expect(resolveNativeDeepLink('yunlefun://wallet'))
      .toEqual({
        type: 'route',
        path: '/wallet',
        closeBrowser: true,
      })
  })

  it.each([
    'https://example.com/w/EJ83N5',
    'https://apps.yunle.fun/w/invalid',
    'yunlefun://workshop/invalid',
    'not a url',
  ])('rejects an untrusted or malformed URL: %s', (url) => {
    expect(resolveNativeDeepLink(url)).toBeNull()
  })

  it('declares the workshop path in the deployed AASA file', () => {
    const association = JSON.parse(readFileSync(
      new URL('../../public/.well-known/apple-app-site-association', import.meta.url),
      'utf8',
    ))
    const paths = association.applinks.details.flatMap(
      (detail: { components?: Array<{ '/': string }> }) =>
        detail.components?.map(component => component['/']) || [],
    )

    expect(paths).toContain('/w/*')
    expect(association.applinks.details).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appIDs: expect.any(Array),
          components: expect.any(Array),
        }),
      ]),
    )
    expect(association.applinks.details).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appIDs: expect.any(Array),
          paths: expect.any(Array),
        }),
      ]),
    )
  })

  it('serves the AASA file with a JSON content type on EdgeOne', () => {
    const edgeone = JSON.parse(readFileSync(
      new URL('../../../../edgeone.json', import.meta.url),
      'utf8',
    ))
    const rule = edgeone.headers.find(
      (item: { source?: string }) =>
        item.source === '/.well-known/apple-app-site-association',
    )

    expect(rule?.headers).toContainEqual({
      key: 'Content-Type',
      value: 'application/json; charset=utf-8',
    })
  })
})
