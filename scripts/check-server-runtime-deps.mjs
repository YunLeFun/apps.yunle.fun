#!/usr/bin/env node

import { access, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import process from 'node:process'

const outputDir = resolve(process.cwd(), '.output/server')
const packageJsonPath = resolve(outputDir, 'package.json')
const requiredRuntimeDependencies = [
  '@cloudbase/node-sdk',
]

const packageJson = JSON.parse(await readFile(packageJsonPath, 'utf8'))
const dependencies = packageJson.dependencies || {}

for (const dependency of requiredRuntimeDependencies) {
  if (!dependencies[dependency]) {
    throw new Error(
      `${dependency} is missing from .output/server/package.json. `
      + 'Add it to nitro.externals.traceInclude so serverless runtimes can load it.',
    )
  }

  await access(resolve(outputDir, 'node_modules', dependency, 'package.json'))
}

console.log(`✓ Server runtime dependencies traced: ${requiredRuntimeDependencies.join(', ')}`)
