import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

interface EdgeOneHeaderRule {
  source: string
  headers: Array<{ key: string, value: string }>
}

const config = JSON.parse(readFileSync(resolve('edgeone.json'), 'utf8')) as {
  headers: EdgeOneHeaderRule[]
}

describe('edgeOne workshop API headers', () => {
  for (const source of ['/api/workshops', '/api/workshops/*']) {
    it(`prevents edge caching for ${source}`, () => {
      const rule = config.headers.find(item => item.source === source)
      expect(rule).toBeDefined()
      const headers = Object.fromEntries(
        rule!.headers.map(header => [header.key.toLowerCase(), header.value]),
      )
      expect(headers['cache-control']).toContain('private')
      expect(headers['cache-control']).toContain('no-store')
      expect(headers.pragma).toBe('no-cache')
    })
  }
})
