import { api } from '@electron-forge/core'
import { describe, expect, it } from 'vitest'
import forge from '../../forge.config.cjs'
import { parseForgeOptions } from '../../scripts/forge.mjs'

describe('native packaging contract', () => {
  it('uses the supported official Forge lifecycle methods without executing a publish', () => {
    for (const method of ['start', 'package', 'make', 'release'])
      expect(typeof api[method]).toBe('function')
  })
  it('points Debian installation at the real binary and gives the scoped workspace a valid OS package name', () => {
    const deb = forge.makers.find(maker => maker.name === '@electron-forge/maker-deb').config.options
    expect(deb.bin).toBe(forge.packagerConfig.executableName)
    expect(deb.name).toMatch(/^[a-z0-9][a-z0-9+.-]+$/)
    expect(deb.name).not.toContain('/')
    const squirrel = forge.makers.find(maker => maker.name === '@electron-forge/maker-squirrel').config
    expect(squirrel.name).toMatch(/^[a-z_][a-z0-9_]*$/)
  })
  it('accepts the CI target arguments in both forms and rejects unrelated options', () => {
    expect(parseForgeOptions(['make', '--arch=arm64', '--platform', 'darwin'])).toMatchObject({
      command: 'make',
      options: { arch: 'arm64', platform: 'darwin' },
    })
    for (const args of [['execute'], ['make', '--dir=/tmp/other-app'], ['make', '--arch'], ['make', '--arch=../other']])
      expect(() => parseForgeOptions(args)).toThrow()
  })
})
