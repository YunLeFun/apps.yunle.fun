import fs from 'node:fs/promises'
import { createRequire } from 'node:module'
import path from 'node:path'
import { root } from './lib.mjs'

async function locatePackage(name, from) {
  const require = createRequire(path.join(from, 'package.json'))
  let resolved
  try {
    resolved = require.resolve(`${name}/package.json`)
  }
  catch {
    resolved = require.resolve(name)
  }
  let directory = path.dirname(await fs.realpath(resolved))
  while (directory !== path.dirname(directory)) {
    try {
      const metadata = JSON.parse(await fs.readFile(path.join(directory, 'package.json'), 'utf8'))
      if (metadata.name === name)
        return { directory, metadata }
    }
    catch {}
    directory = path.dirname(directory)
  }
  throw new Error(`Cannot locate runtime package ${name}`)
}

function runtimeNames(metadata) {
  return [...new Set([...Object.keys(metadata.dependencies || {}), ...Object.keys(metadata.optionalDependencies || {})])]
}

/** Copy exact resolved production dependencies, without pnpm's external symlinks. */
export async function materializeRuntimeDependencies(buildPath) {
  const metadata = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'))
  await fs.rm(path.join(buildPath, 'node_modules'), { recursive: true, force: true })
  async function copyPackage(name, from, parentDestination, ancestry = []) {
    let source
    try {
      source = await locatePackage(name, from)
    }
    catch (error) {
      const owner = JSON.parse(await fs.readFile(path.join(from, 'package.json'), 'utf8'))
      if (Object.hasOwn(owner.optionalDependencies || {}, name))
        return
      throw error
    }
    // Node will resolve a cycle to this matching physical ancestor package.
    if (ancestry.includes(source.directory))
      return
    const destination = path.join(parentDestination, 'node_modules', name)
    await fs.mkdir(path.dirname(destination), { recursive: true })
    await fs.cp(source.directory, destination, {
      recursive: true,
      dereference: true,
      filter: file => !path.relative(source.directory, file).split(path.sep).includes('node_modules'),
    })
    for (const child of runtimeNames(source.metadata))
      await copyPackage(child, source.directory, destination, [...ancestry, source.directory])
  }
  for (const name of runtimeNames(metadata))
    await copyPackage(name, root, buildPath)
  await assertStandaloneRuntime(buildPath)
}

export async function assertStandaloneRuntime(buildPath) {
  const realBuildPath = await fs.realpath(buildPath)
  const seen = new Set()
  async function check(directory) {
    const metadata = JSON.parse(await fs.readFile(path.join(directory, 'package.json'), 'utf8'))
    for (const name of runtimeNames(metadata)) {
      let dependency
      try {
        dependency = await locatePackage(name, directory)
      }
      catch (error) {
        if (Object.hasOwn(metadata.optionalDependencies || {}, name))
          continue
        throw error
      }
      const relative = path.relative(realBuildPath, dependency.directory)
      if (relative.startsWith('..') || path.isAbsolute(relative))
        throw new Error(`Runtime dependency escapes the package: ${name}`)
      if (seen.has(dependency.directory))
        continue
      seen.add(dependency.directory)
      await check(dependency.directory)
    }
  }
  await check(buildPath)
  async function rejectSymlinks(directory) {
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      if (entry.isSymbolicLink())
        throw new Error(`Unexpected runtime symlink: ${path.join(directory, entry.name)}`)
      if (entry.isDirectory())
        await rejectSymlinks(path.join(directory, entry.name))
    }
  }
  await rejectSymlinks(path.join(buildPath, 'node_modules'))
}
