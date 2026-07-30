import { readdirSync, readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

const ROOT = resolve(import.meta.dirname, '../..')
const APP_ROOT = resolve(ROOT, 'app')

function collectSourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const file = resolve(directory, entry)
    if (statSync(file).isDirectory())
      return collectSourceFiles(file)
    return /\.(?:ts|vue)$/.test(entry) ? [file] : []
  })
}

describe('全局 Toast 风格契约', () => {
  it('所有业务提示统一经过 useToast 与 AppToast', () => {
    const appSources = collectSourceFiles(APP_ROOT)
      .map(file => readFileSync(file, 'utf8'))
      .join('\n')
    const appShell = readFileSync(resolve(APP_ROOT, 'app.vue'), 'utf8')
    const appToast = readFileSync(resolve(APP_ROOT, 'components/AppToast.vue'), 'utf8')

    expect(appSources).not.toMatch(/\bshowIonicToast\b/)
    expect(appSources).not.toMatch(/\btoastController\b/)
    expect(appSources).not.toMatch(/<IonToast\b/)
    expect(appShell).toContain('<AppToast />')
    expect(appToast).toContain('kToast')
  })
})
