import { describe, expect, it } from 'vitest'
import { getAppById } from '../../app/constants/apps'
import { findFirstPartySsoClient } from '../../app/utils/first-party-sso-clients'

describe('offline app catalog snapshot', () => {
  it('keeps the published 云栈 brand aligned across the catalog and SSO registry', () => {
    expect(getAppById('yunjian')).toMatchObject({
      name: '云栈',
      logo: 'https://cms.yunle.fun/icon.svg',
      themeColor: '#35566b',
      websiteUrl: 'https://cms.yunle.fun/',
    })
    expect(findFirstPartySsoClient('yunjian', 'https://cms.yunle.fun')).toMatchObject({
      displayName: '云栈',
    })
  })
})
