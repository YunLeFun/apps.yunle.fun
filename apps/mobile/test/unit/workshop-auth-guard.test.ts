import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const ownerMutationRoutes = [
  new URL('../../server/api/workshops/index.post.ts', import.meta.url),
  new URL('../../server/api/workshops/[id].patch.ts', import.meta.url),
  new URL('../../server/api/workshops/[id]/members/[uid].post.ts', import.meta.url),
]

describe('personal workshop auth guards', () => {
  it('allows active registered accounts without requiring app-submission verification', () => {
    for (const routeUrl of ownerMutationRoutes) {
      const source = readFileSync(routeUrl, 'utf8')
      expect(source).toContain('requireRegisteredCloudbaseUser')
      expect(source).not.toContain('requireVerifiedCloudbaseUser')
    }
  })
})
