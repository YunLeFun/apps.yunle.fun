import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

interface EdgeOneHeaderRule {
  source: string
  headers: Array<{ key: string, value: string }>
}

const config = JSON.parse(readFileSync(fileURLToPath(new URL('../../../../edgeone.json', import.meta.url)), 'utf8')) as {
  buildCommand: string
  installCommand: string
  outputDirectory: string
  headers: EdgeOneHeaderRule[]
}
const appConfig = JSON.parse(readFileSync(fileURLToPath(new URL('../../edgeone.json', import.meta.url)), 'utf8')) as typeof config

describe('edgeOne monorepo build entry', () => {
  it('installs the workspace from the Nuxt application root and guards full-stack output', () => {
    expect(appConfig.installCommand).toBe('pnpm --dir ../.. install --frozen-lockfile')
    expect(appConfig.buildCommand).toBe('pnpm run build:edgeone')
    expect(appConfig.outputDirectory).toBe('.edgeone/assets')
    expect(config.buildCommand).toBe('pnpm run build:edgeone')
    expect(config.outputDirectory).toBe('apps/mobile/.edgeone/assets')
    expect(appConfig.headers).toEqual(config.headers)
  })
})

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
