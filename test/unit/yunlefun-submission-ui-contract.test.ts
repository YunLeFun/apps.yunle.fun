import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const detailPage = readFileSync(
  new URL('../../app/pages/workshop/[slug]/index.vue', import.meta.url),
  'utf8',
)

describe('yunLeFun owner submission UI contract', () => {
  it('uses the unified product name and exposes the private-to-public confirmation', () => {
    expect(detailPage).toContain('云乐坊状态')
    expect(detailPage).toContain('设为公开并投稿')
    expect(detailPage).toContain('站点自身的登录、邀请或其他访问保护仍由开发者负责')
    expect(detailPage).toContain('submitPublicMarket(app.value._id, { makePublic })')
    expect(detailPage).not.toContain('公共市场审核')
  })
})
