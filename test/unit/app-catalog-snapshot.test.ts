import { describe, expect, it } from 'vitest'
import { FEATURED_APP, getAppById } from '../../app/constants/apps'
import { resolveAppIconPresentation } from '../../app/utils/appIconAssets'

describe('offline app catalog snapshot', () => {
  it('keeps the published 云栈 brand aligned in the catalog', () => {
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
  })

  it('omits private entries and uses localized catalog titles', () => {
    expect(getAppById('valaxy')).toBeUndefined()
    expect(getAppById('air-conditioner')?.name).toBe('云空调')
    expect(getAppById('electric-fan')?.name).toBe('云风扇')
    expect(getAppById('give-me-money')).toMatchObject({
      name: '请给我钱！',
      websiteUrl: 'https://gmm.yunle.fun/',
      iconAssets: {
        mark: { src: 'https://gmm.yunle.fun/favicon.png' },
      },
    })
    expect(getAppById('cook')?.name).toBe('今天来做菜')
    expect(getAppById('dayun-kicker')?.name).toBe('暴力电驴')
    expect(getAppById('pachinko')?.name).toBe('云乐弹珠')
    expect(FEATURED_APP.slug).toBe('yun-home')
  })
})
