import { describe, expect, it } from 'vitest'
import { withCanonicalAppDomain } from '~/utils/canonical-app-domain'

describe('canonical app domains', () => {
  it('always opens AI SFC on its yunle.fun primary domain', () => {
    expect(withCanonicalAppDomain({
      id: 'ai-sfc',
      slug: 'ai-sfc',
      name: 'AI 春联',
      websiteUrl: 'https://ai-sfc.yunyoujun.cn',
    }).websiteUrl).toBe('https://ai-sfc.yunle.fun')
  })

  it('always opens Give Me Money on its yunle.fun primary domain', () => {
    expect(withCanonicalAppDomain({
      id: 'give-me-money',
      slug: 'give-me-money',
      name: '请给我钱！',
      websiteUrl: 'https://gmm.yunyoujun.cn',
    }).websiteUrl).toBe('https://gmm.yunle.fun/')
  })

  it('opens cached and bundled Web Resume entries on the registered login origin', () => {
    for (const websiteUrl of ['https://resume.elpsy.cn', 'https://resume.yunyoujun.cn']) {
      expect(withCanonicalAppDomain({
        id: 'web-resume',
        slug: 'web-resume',
        name: 'Web Resume',
        websiteUrl,
      }).websiteUrl).toBe('https://resume.yunle.fun')
    }
  })

  it('leaves unrelated applications unchanged', () => {
    const app = {
      id: 'play',
      slug: 'play',
      name: 'Play',
      websiteUrl: 'https://play.yunle.fun',
    }
    expect(withCanonicalAppDomain(app)).toBe(app)
  })
})
