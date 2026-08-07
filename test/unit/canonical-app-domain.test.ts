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
