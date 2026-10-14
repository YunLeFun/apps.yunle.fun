import path from 'node:path'
import process from 'node:process'
import { api } from '@electron-forge/core'
import { checkRelease } from './check-release.mjs'
import { root } from './lib.mjs'

export function parseForgeOptions(args) {
  const [command, ...flags] = args
  if (!['start', 'package', 'make', 'publish'].includes(command))
    throw new Error('Choose start, package, make or publish')
  const options = { dir: root, interactive: command !== 'start' }
  for (let index = 0; index < flags.length; index++) {
    const match = flags[index].match(/^--(arch|platform)(?:=(.+))?$/)
    if (!match)
      throw new Error(`Unsupported Forge option: ${flags[index]}`)
    const value = match[2] || flags[++index]
    if (!value || !/^[a-z0-9]+$/i.test(value))
      throw new Error(`Invalid Forge ${match[1]}`)
    options[match[1]] = value
  }
  return { command, options }
}

export async function runForge(args) {
  const { command, options } = parseForgeOptions(args)
  // The official API preserves Forge hooks, rebuilds, makers and fuses while
  // avoiding its CLI's obsolete pnpm config-get probes for hyphenated keys.
  if (command === 'publish') {
    await checkRelease()
    const { dir, interactive, ...makeOptions } = options
    return api.release({ dir, interactive, makeOptions })
  }
  if (command !== 'start')
    return api[command](options)
  const child = await api.start(options)
  if (!child)
    throw new Error('Forge did not start Electron')
  await new Promise((resolve, reject) => {
    child.once('error', reject)
    child.once('exit', (code) => {
      process.exitCode = code || 0
      resolve()
    })
  })
}

if (process.argv[1] && path.resolve(process.argv[1]) === import.meta.filename)
  await runForge(process.argv.slice(2))
