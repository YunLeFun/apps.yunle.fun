import { spawn } from 'node:child_process'
import fs from 'node:fs/promises'
import { createRequire } from 'node:module'
import path from 'node:path'
import process from 'node:process'

const require = createRequire(import.meta.url)

export async function prepareMacosMaker() {
  if (process.platform !== 'darwin')
    return
  // Resolve through the maker's declared dependency graph, not hoisted aliases.
  const makerRequire = createRequire(require.resolve('@electron-forge/maker-dmg'))
  const installerRequire = createRequire(makerRequire.resolve('electron-installer-dmg'))
  const appdmgRequire = createRequire(installerRequire.resolve('appdmg'))
  const storeRequire = createRequire(appdmgRequire.resolve('ds-store'))
  const addons = [
    { name: 'macos-alias', metadata: storeRequire.resolve('macos-alias/package.json'), binary: 'volume.node' },
    { name: 'fs-xattr', metadata: appdmgRequire.resolve('fs-xattr/package.json'), binary: 'xattr.node' },
  ]
  for (const addon of addons) {
    const directory = path.dirname(addon.metadata)
    const binary = path.join(directory, 'build/Release', addon.binary)
    if (await fs.stat(binary).then(() => true, () => false))
      continue
    // pnpm 11 does not infer these legacy packages' node-gyp install scripts.
    // npm rebuild supplies that default; it installs no dependencies. These
    // addons execute in the host's Node process, not in the packaged Electron.
    console.info(`[make] Building ${addon.name} for host Node ${process.versions.node} ${process.arch}`)
    await new Promise((resolve, reject) => {
      const child = spawn('npm', ['rebuild', '--prefix', directory, '--ignore-scripts=false'], { stdio: 'inherit' })
      child.once('error', reject)
      child.once('exit', code => code === 0 ? resolve() : reject(new Error(`Native DMG helper ${addon.name} failed (${code})`)))
    })
    await fs.stat(binary)
  }
}
