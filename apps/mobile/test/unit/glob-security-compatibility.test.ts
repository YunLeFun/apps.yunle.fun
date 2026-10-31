import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

const require = createRequire(import.meta.url)
const installerRequire = createRequire(require.resolve('electron-installer-common'))
const asarRequire = createRequire(installerRequire.resolve('@electron/asar'))
const legacyGlob = asarRequire('glob') as {
  (pattern: string, options: object, callback: (error: Error | null, paths: string[]) => void): void
  sync: (pattern: string, options: object) => string[]
}
const asar = installerRequire('@electron/asar') as {
  createPackageWithOptions: (source: string, destination: string, options: object) => Promise<void>
  listPackage: (archive: string) => string[]
}
const archiveRequire = createRequire(require.resolve('archiver-utils'))
const modernGlob = archiveRequire('glob') as { glob: (pattern: string, options: object) => Promise<string[]> }
const { Minimatch } = require('minimatch') as {
  Minimatch: new (pattern: string, options: object) => { set: unknown[] }
}

let directory: string

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), 'yunle-glob-compat-'))
  await mkdir(join(directory, 'input', 'nested'), { recursive: true })
  await writeFile(join(directory, 'input', 'index.js'), 'export const value = 1\n')
  await writeFile(join(directory, 'input', 'nested', 'note.txt'), 'unpacked content')
  await writeFile(join(directory, 'input', '.hidden.txt'), 'hidden content')
})
afterEach(async () => {
  await rm(directory, { recursive: true, force: true })
})

describe('security-updated file matching consumers', () => {
  it('preserves the legacy Electron ASAR glob callback and synchronous matching', async () => {
    const options = { cwd: join(directory, 'input'), nodir: true }
    expect(legacyGlob.sync('**/*.{js,txt}', options).sort()).toEqual(['index.js', 'nested/note.txt'])
    const paths = await new Promise<string[]>((resolve, reject) => {
      legacyGlob('**/*.txt', { ...options, dot: true }, (error, values) => error ? reject(error) : resolve(values))
    })
    expect(paths.sort()).toEqual(['.hidden.txt', 'nested/note.txt'])
  })

  it.each([{ unpack: '**/*.txt' }, { unpackDir: '**/nested' }])('packs a real legacy ASAR archive with %o', async (options) => {
    const archive = join(directory, 'application.asar')
    await asar.createPackageWithOptions(join(directory, 'input'), archive, options)
    expect(asar.listPackage(archive)).toContain('/index.js')
    expect(await readFile(`${archive}.unpacked/nested/note.txt`, 'utf8')).toBe('unpacked content')
  })

  it('preserves the modern archive consumer promise API and bounds pattern preprocessing', async () => {
    const paths = await modernGlob.glob('**/*.txt', { cwd: join(directory, 'input'), nodir: true, dot: true })
    expect(paths.sort()).toEqual(['.hidden.txt', 'nested/note.txt'])
    const matcher = new Minimatch(Array.from({ length: 8 }).fill('**/../a/b').join('/'), {
      optimizationLevel: 2,
      braceExpandMax: 8,
    })
    expect(matcher.set.length).toBeLessThanOrEqual(8)
  })
})
