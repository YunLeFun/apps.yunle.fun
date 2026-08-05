import { describe, expect, it } from 'vitest'
import { getAppById } from '../../app/constants/apps'

describe('offline app catalog snapshot', () => {
  it('includes the published 云笺 app with its trusted production URL', () => {
    expect(getAppById('yunjian')).toMatchObject({
      name: '云笺',
      logo: 'https://cms.yunle.fun/icon.svg',
      websiteUrl: 'https://cms.yunle.fun/',
    })
  })
})
