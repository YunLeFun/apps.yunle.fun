#!/usr/bin/env node

import { spawn } from 'node:child_process'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { assertNoDeploymentEnvFiles, verifyEdgeOneOutput } from './check-edgeone-output.mjs'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
await assertNoDeploymentEnvFiles(appRoot)

// EdgeOne's Nuxt prebuild hook injects its output configuration before running
// this command. Never accept an older successful output after a failed build.
await rm(join(appRoot, '.edgeone'), { recursive: true, force: true })
const staging = await mkdtemp(join(tmpdir(), 'yunlefun-edgeone-build-'))
try {
  const dotenv = join(staging, 'empty.env')
  await writeFile(dotenv, '')
  const require = createRequire(join(appRoot, 'package.json'))
  const nuxtPackagePath = require.resolve('nuxt/package.json')
  const nuxtPackage = JSON.parse(await readFile(nuxtPackagePath, 'utf8'))
  const nuxtBin = resolve(dirname(nuxtPackagePath), nuxtPackage.bin.nuxt)
  await new Promise((fulfill, reject) => {
    const child = spawn(process.execPath, [nuxtBin, 'build', '--dotenv', dotenv], {
      cwd: appRoot,
      stdio: 'inherit',
    })
    child.once('error', reject)
    child.once('exit', (code, signal) => {
      if (code === 0)
        fulfill()
      else
        reject(new Error(`Nuxt EdgeOne build failed (${signal || code}).`))
    })
  })
  await verifyEdgeOneOutput(join(appRoot, '.edgeone'))
  console.log('✓ EdgeOne Nitro output verified; the platform adapter will generate its function handler and routes next')
}
finally {
  await rm(staging, { recursive: true, force: true })
}
