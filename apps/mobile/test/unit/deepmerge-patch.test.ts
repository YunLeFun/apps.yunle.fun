import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { runInNewContext } from 'node:vm'
import { describe, expect, it } from 'vitest'

// Exercise the installed dependency used by Nitro's real Rollup resolver.
const require = createRequire(import.meta.url)
const nitroRequire = createRequire(require.resolve('nitropack/package.json'))
const resolverRequire = createRequire(nitroRequire.resolve('@rollup/plugin-node-resolve'))
type Merge = (target: unknown, source: unknown) => Record<PropertyKey, unknown>
const commonjs: Merge = resolverRequire('deepmerge')
const packageRoot = dirname(resolverRequire.resolve('deepmerge/package.json'))
const browser: { deepmerge?: Merge } = {}
runInNewContext(readFileSync(join(packageRoot, 'dist/umd.js'), 'utf8'), browser, { timeout: 1000 })

for (const [name, merge] of [['CommonJS', commonjs], ['browser UMD', browser.deepmerge!]] as const) {
  describe(`patched deepmerge ${name}`, () => {
    const safePrototype = Object.getPrototypeOf(merge({}, {}))
    function expectSafe(result: Record<PropertyKey, unknown>) {
      expect(result.deepmergeTestPoison).toBeUndefined()
      expect(Object.getPrototypeOf(result)).toBe(safePrototype)
      expect(Object.hasOwn(result, '__proto__')).toBe(false)
    }

    it('rejects a source prototype key even when the target has no prototype', () => {
      const source = JSON.parse('{"__proto__":{"deepmergeTestPoison":true},"safe":"kept"}')
      const result = merge(Object.create(null), source)
      expectSafe(result)
      expect(result.safe).toBe('kept')
    })

    it.each([null, undefined, 1, 'placeholder'])('protects a nested %s placeholder', (placeholder) => {
      const source = JSON.parse('{"session":{"__proto__":{"deepmergeTestPoison":true},"safe":1}}')
      const result = merge({ session: placeholder }, source)
      expectSafe(result.session as Record<PropertyKey, unknown>)
      expect(result.session).toEqual({ safe: 1 })
    })

    it('rejects target prototype keys before copying, including nested input', () => {
      const target = JSON.parse('{"__proto__":{"deepmergeTestPoison":true},"safe":1}')
      expectSafe(merge(target, {}))
      expectSafe(merge({ session: target }, {}).session as Record<PropertyKey, unknown>)
      expectSafe(merge(target, JSON.parse('{"__proto__":{"deepmergeTestPoison":true}}')))
    })

    it('preserves regular nested objects, array concatenation, symbols and input immutability', () => {
      const symbol = Symbol('config')
      const target = { nested: { first: 1 }, values: [1] }
      const source = { nested: { second: 2 }, values: [2], [symbol]: 'kept' }
      const result = merge(target, source)
      expect(result).toEqual({ nested: { first: 1, second: 2 }, values: [1, 2], [symbol]: 'kept' })
      expect(target).toEqual({ nested: { first: 1 }, values: [1] })
      expect(source).toEqual({ nested: { second: 2 }, values: [2], [symbol]: 'kept' })
    })
  })
}
