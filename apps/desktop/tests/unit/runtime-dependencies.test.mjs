import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { expect, it } from 'vitest'
import { root } from '../../scripts/lib.mjs'
import { assertStandaloneRuntime, materializeRuntimeDependencies } from '../../scripts/runtime-dependencies.mjs'

it('materializes the production dependency closure without workspace symlinks or development packages', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-runtime-test-'))
  try {
    const metadata = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'))
    await fs.writeFile(path.join(directory, 'package.json'), JSON.stringify(metadata))
    await materializeRuntimeDependencies(directory)
    await assertStandaloneRuntime(directory)
    expect(await fs.stat(path.join(directory, 'node_modules/update-electron-app/package.json')).then(() => true)).toBe(true)
    expect(await fs.stat(path.join(directory, 'node_modules/electron/package.json')).then(() => true, () => false)).toBe(false)
    expect(await fs.stat(path.join(directory, 'node_modules/@yunlefun/app-core/package.json')).then(() => true, () => false)).toBe(false)
  }
  finally {
    await fs.rm(directory, { recursive: true, force: true })
  }
})
