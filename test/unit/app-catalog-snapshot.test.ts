import { describe, expect, it } from 'vitest'
import { getAppById } from '../../app/constants/apps'
import { resolveAppIconPresentation } from '../../app/utils/appIconAssets'
import { findFirstPartySsoClient } from '../../app/utils/first-party-sso-clients'

describe('offline app catalog snapshot', () => {
  it('keeps the published 云栈 brand aligned across the catalog and SSO registry', () => {
    const app = getAppById('yunjian')

    expect(app).toMatchObject({
      name: '云栈',
      logo: 'https://cms.yunle.fun/icon.svg',
      themeColor: '#35566b',
      websiteUrl: 'https://cms.yunle.fun/',
    })
    expect(app?.iconAssets?.appIcon?.src).toBe('/app-icons/cms-app-icon.svg')
    expect(app?.iconAssets?.mark).toBeUndefined()
    expect(resolveAppIconPresentation({ assets: app?.iconAssets })).toEqual({
      role: 'app-icon',
      source: '/app-icons/cms-app-icon.svg',
    })
    expect(findFirstPartySsoClient('yunjian', 'https://cms.yunle.fun')).toMatchObject({
      displayName: '云栈',
    })
  })
})
