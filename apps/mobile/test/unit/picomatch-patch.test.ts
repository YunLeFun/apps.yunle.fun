import { createRequire } from 'node:module'
import { describe, expect, it } from 'vitest'

const require = createRequire(import.meta.url)
type Match = (glob: string, options?: { maxExtglobRecursion?: boolean }) => (input: string) => boolean

describe.each(['anymatch', 'tinyglobby'])('picomatch used by %s', (consumer) => {
  const picomatch: Match = createRequire(require.resolve(consumer))('picomatch')

  it.each(['+(draft*)', '*(draft*)', '+(**/draft)'])('treats repeated wildcard group %s as literal', (glob) => {
    for (const options of [undefined, { maxExtglobRecursion: false }]) {
      const match = picomatch(glob, options)
      expect(match(glob)).toBe(true)
      expect(match('draft')).toBe(false)
    }
  })

  it('keeps ordinary wildcards, literal stars and safe repeated groups working', () => {
    expect(picomatch('**/*.ts')('app/example.ts')).toBe(true)
    expect(picomatch('+(alpha|beta).txt')('alphabeta.txt')).toBe(true)
    expect(picomatch('+(draft\\*)')('draft*draft*')).toBe(true)
    expect(picomatch('+(*(a))')('aaaa')).toBe(true)
  })
})
