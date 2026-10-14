#!/usr/bin/env node

import { access, readdir, readFile, realpath, stat } from 'node:fs/promises'
import { dirname, isAbsolute, join, relative, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath, pathToFileURL } from 'node:url'

export const deploymentEnvFiles = ['.env', '.env.production', '.env.local', '.env.production.local']

export async function assertNoDeploymentEnvFiles(appRoot) {
  const entries = await readdir(appRoot)
  if (entries.some(entry => deploymentEnvFiles.includes(entry))) {
    throw new Error('EdgeOne builds must not contain private .env files. Configure server variables in EdgeOne runtime settings instead.')
  }
}

async function requireFile(file) {
  if (!(await stat(file)).isFile())
    throw new Error(`Expected an EdgeOne build file: ${file}`)
}

export async function verifyEdgeOneOutput(outputDir, { adapted = false } = {}) {
  const root = resolve(outputDir)
  const server = join(root, 'cloud-functions/ssr-node')
  try {
    const metadata = JSON.parse(await readFile(join(root, 'nitro.json'), 'utf8'))
    if (metadata.preset !== 'node-server' || metadata.framework?.name !== 'nuxt')
      throw new Error('Expected the official Nuxt adapter with the Nitro node-server preset.')

    await requireFile(join(root, 'assets/index.html'))
    const assets = await readdir(join(root, 'assets/_nuxt'))
    if (!assets.some(file => file.endsWith('.js')))
      throw new Error('Nuxt client JavaScript is missing from EdgeOne assets.')

    // The official adapter creates handler.js/config.json after our build command
    // returns, then removes index.mjs in onPostBuild. Check the appropriate phase.
    await requireFile(join(server, adapted ? 'handler.js' : 'index.mjs'))
    const chunks = ['chunks/nitro/nitro.mjs', 'chunks/_/nitro.mjs']
    if (!(await Promise.all(chunks.map(file => access(join(server, file)).then(() => true, () => false)))).some(Boolean))
      throw new Error('The Nitro application chunk is missing.')

    const packageJson = JSON.parse(await readFile(join(server, 'package.json'), 'utf8'))
    if (!packageJson.dependencies?.['@cloudbase/node-sdk'])
      throw new Error('@cloudbase/node-sdk is missing from the server runtime dependencies.')
    const sdk = await realpath(join(server, 'node_modules/@cloudbase/node-sdk/package.json'))
    const sdkRelative = relative(await realpath(server), sdk)
    if (sdkRelative.startsWith('..') || isAbsolute(sdkRelative))
      throw new Error('The CloudBase server SDK must be included in the deployment output.')
    await requireFile(sdk)
    await assertNoDeploymentEnvFiles(server)

    if (adapted) {
      const config = JSON.parse(await readFile(join(server, 'config.json'), 'utf8'))
      const routes = config.routes
      if (config.version !== 3 || !Array.isArray(routes) || !routes.some(route => route.handle === 'filesystem'))
        throw new Error('The EdgeOne function route configuration is incomplete.')
      const filesystem = routes.findIndex(route => route.handle === 'filesystem')
      const functionRoutes = routes.slice(filesystem + 1)
      for (const route of ['/login', '/tabs/home', '/api/apps/public', '/api/apps/access']) {
        if (!functionRoutes.some(rule => typeof rule.src === 'string' && new RegExp(rule.src).test(route)))
          throw new Error(`No EdgeOne function route matches ${route}.`)
      }
    }
  }
  catch (cause) {
    throw new Error('EdgeOne full-stack output is incomplete. Set the project root to apps/mobile and the framework to Nuxt; publishing only .output/public would lose page fallback and APIs.', { cause })
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
  await verifyEdgeOneOutput(join(appRoot, '.edgeone'), { adapted: process.argv.includes('--adapted') })
  console.log('✓ EdgeOne assets, Nitro server and traced runtime dependencies verified')
}
