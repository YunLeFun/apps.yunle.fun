import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const pageLoadingUrl = new URL('../../app/components/AppPageLoading.vue', import.meta.url)
const workshopPageUrls = [
  new URL('../../app/pages/user/workshops.vue', import.meta.url),
  new URL('../../app/pages/user/workshop.vue', import.meta.url),
  new URL('../../app/pages/user/reports.vue', import.meta.url),
  new URL('../../app/pages/w/[id].vue', import.meta.url),
  new URL('../../app/pages/workshop/index.vue', import.meta.url),
  new URL('../../app/pages/workshop/[slug]/index.vue', import.meta.url),
  new URL('../../app/pages/workshop/[slug]/edit.vue', import.meta.url),
]

describe('page loading UI contract', () => {
  it('fills the available width and centers its spinner', () => {
    expect(existsSync(pageLoadingUrl)).toBe(true)

    const source = readFileSync(pageLoadingUrl, 'utf8')
    expect(source).toMatch(/inline-size:\s*100%/)
    expect(source).toMatch(/place-items:\s*center/)
    expect(source).toContain('role="status"')
  })

  it('is reused by the targeted page-level loading states', () => {
    for (const pageUrl of workshopPageUrls) {
      const source = readFileSync(pageUrl, 'utf8')
      expect(source).toMatch(/<AppPageLoading\s+v-(?:else-)?if="[^"]*loading/)
    }
  })
})
