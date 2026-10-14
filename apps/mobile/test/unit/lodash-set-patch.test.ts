import { createRequire } from 'node:module'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

const require = createRequire(import.meta.url)
const sdkRequire = createRequire(require.resolve('@cloudbase/node-sdk/package.json'))
const databaseRequire = createRequire(sdkRequire.resolve('@cloudbase/database/package.json'))
const set: (object: object, path: string, value: unknown) => object = databaseRequire('lodash.set')

function clearPollution() {
  delete (Object.prototype as Record<string, unknown>).polluted
}

describe('patched lodash.set', () => {
  beforeEach(clearPollution)
  afterEach(clearPollution)

  it.each([
    '__proto__.polluted',
    'constructor.prototype.polluted',
    'prototype.polluted',
  ])('blocks the %s prototype-pollution path', (path) => {
    const target = {}

    set(target, path, true)

    expect((Object.prototype as Record<string, unknown>).polluted).toBeUndefined()
    expect(target).not.toHaveProperty('polluted')
  })
})
