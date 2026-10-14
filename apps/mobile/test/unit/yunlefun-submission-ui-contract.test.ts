import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const detailPage = readFileSync(
  new URL('../../app/pages/workshop/[slug]/index.vue', import.meta.url),
  'utf8',
)
const appForm = readFileSync(
  new URL('../../app/composables/useAppForm.ts', import.meta.url),
  'utf8',
)
const createPage = readFileSync(
  new URL('../../app/pages/workshop/new.vue', import.meta.url),
  'utf8',
)
const editPage = readFileSync(
  new URL('../../app/pages/workshop/[slug]/edit.vue', import.meta.url),
  'utf8',
)

describe('yunLeFun owner submission UI contract', () => {
  it('uses the unified product name and exposes the private-to-public confirmation', () => {
    expect(detailPage).toContain('云乐坊状态')
    expect(detailPage).toContain('设为公开并投稿')
    expect(detailPage).toContain('站点自身的登录、邀请或其他访问保护仍由开发者负责')
    expect(detailPage).toContain('submitPublicMarket(app.value._id, { makePublic, shortName })')
    expect(detailPage).not.toContain('公共市场审核')
  })

  it('checks display-name availability on create and edit forms', () => {
    expect(appForm).toContain('isNameTaken')
    expect(appForm).toContain('nameChecking')
    expect(appForm).toContain('nameError')
    expect(appForm).toContain('if (!userStore.isLoggedIn)')
    for (const page of [createPage, editPage]) {
      expect(page).toContain('nameChecking')
      expect(page).toContain('nameError')
      expect(page).toContain('名称可用')
    }
  })
})
