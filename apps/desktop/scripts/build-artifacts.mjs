import { execFile } from 'node:child_process'
import { createHash } from 'node:crypto'
import { constants, createReadStream } from 'node:fs'
import fs from 'node:fs/promises'
import { createRequire } from 'node:module'
import path from 'node:path'
import { promisify } from 'node:util'
import { root } from './lib.mjs'

const exec = promisify(execFile)
const manifestName = 'build-manifest.json'
const checksumName = 'SHA256SUMS'
const platforms = new Set(['darwin', 'win32', 'linux'])
const architectures = new Set(['arm64', 'x64', 'ia32', 'armv7l', 'universal'])

function portablePath(value) {
  if (typeof value !== 'string' || !value || value.includes('\\')
    || [...value].some(character => character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127)
    || path.posix.isAbsolute(value) || path.win32.isAbsolute(value)
    || path.posix.normalize(value) !== value || value.split('/').includes('..')) {
    throw new Error(`Invalid artifact path: ${value}`)
  }
  return value
}

function allowedArtifact(platform, filename) {
  const extension = path.posix.extname(filename).toLowerCase()
  if (platform === 'darwin')
    return ['.dmg', '.zip'].includes(extension)
  if (platform === 'win32')
    return ['.exe', '.nupkg'].includes(extension) || path.posix.basename(filename) === 'RELEASES'
  return platform === 'linux' && extension === '.deb'
}

async function fileDigest(file) {
  const stat = await fs.lstat(file)
  if (!stat.isFile() || stat.isSymbolicLink())
    throw new Error(`Artifact must be a regular file: ${file}`)
  const hash = createHash('sha256')
  for await (const chunk of createReadStream(file))
    hash.update(chunk)
  return { bytes: stat.size, sha256: hash.digest('hex') }
}

function checksumText(entries) {
  return entries.map(entry => `${entry.sha256} *${entry.path}\n`).join('')
}

function signingMetadata(config, platform) {
  const squirrel = config.makers?.find(maker => /(?:maker-)?squirrel$/.test(maker.name))?.config
  const appRequested = Boolean(platform === 'darwin' && config.packagerConfig?.osxSign)
  const installerRequested = Boolean(platform === 'win32' && (squirrel?.certificateFile || squirrel?.signWithParams || squirrel?.windowsSign))
  const notarizationRequested = Boolean(platform === 'darwin' && config.packagerConfig?.osxNotarize)
  return {
    // Electron/macOS may carry an ad-hoc signature. "Unsigned" here means
    // no distribution identity was configured, not absence of every signature.
    scope: 'distribution-identity',
    status: appRequested || installerRequested ? 'configured-unverified' : 'unsigned',
    appRequested,
    installerRequested,
    notarizationRequested,
    verified: false,
  }
}

export async function readGitState(directory = root) {
  const { stdout: commit } = await exec('git', ['rev-parse', '--verify', 'HEAD'], { cwd: directory, encoding: 'utf8' })
  const { stdout: changes } = await exec('git', ['status', '--porcelain', '--untracked-files=normal'], { cwd: directory, encoding: 'utf8' })
  return { commit: commit.trim(), dirty: changes.trim().length > 0 }
}

export async function cleanBuildArtifacts(directory = root) {
  await fs.rm(path.join(directory, 'out/artifacts'), { recursive: true, force: true })
}

export async function createBuildArtifacts(makeResults, { directory = root, forgeConfig = {}, electronVersion, gitState } = {}) {
  if (!Array.isArray(makeResults) || !makeResults.length)
    throw new Error('Forge returned no artifacts for this build')
  const first = makeResults[0]
  if (!platforms.has(first.platform) || !architectures.has(first.arch))
    throw new Error('Unsupported build platform or architecture')
  const { productName, version } = first.packageJSON
  if (!productName || !version)
    throw new Error('Forge result is missing product metadata')
  const makeDirectory = path.resolve(directory, 'out/make')
  const realMakeDirectory = await fs.realpath(makeDirectory)
  const selected = new Map()
  for (const result of makeResults) {
    if (result.platform !== first.platform || result.arch !== first.arch
      || result.packageJSON.version !== version || result.packageJSON.productName !== productName) {
      throw new Error('A build manifest must describe one product version, platform and architecture')
    }
    if (!Array.isArray(result.artifacts) || !result.artifacts.length)
      throw new Error('Forge returned an empty maker result')
    for (const artifact of result.artifacts) {
      const source = path.resolve(artifact)
      const relative = portablePath(path.relative(makeDirectory, source).split(path.sep).join('/'))
      const realSource = await fs.realpath(source)
      const realRelative = portablePath(path.relative(realMakeDirectory, realSource).split(path.sep).join('/'))
      if (realRelative !== relative || !allowedArtifact(first.platform, relative))
        throw new Error(`Unexpected installer artifact: ${relative}`)
      if (selected.has(relative))
        throw new Error(`Duplicate installer artifact: ${relative}`)
      selected.set(relative, source)
    }
  }
  const actualElectronVersion = electronVersion || createRequire(path.join(directory, 'package.json'))('electron/package.json').version
  const git = gitState || await readGitState(directory)
  const out = path.join(directory, 'out')
  const staging = await fs.mkdtemp(path.join(out, '.artifacts-'))
  try {
    const artifacts = []
    for (const [relative, source] of [...selected].sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0)) {
      if (!(await fs.lstat(source)).isFile())
        throw new Error(`Installer must be a regular file: ${relative}`)
      const target = path.join(staging, relative)
      await fs.mkdir(path.dirname(target), { recursive: true })
      await fs.copyFile(source, target, constants.COPYFILE_EXCL)
      artifacts.push({ path: relative, ...await fileDigest(target) })
    }
    const manifest = {
      schemaVersion: 1,
      productName,
      version,
      electronVersion: actualElectronVersion,
      platform: first.platform,
      arch: first.arch,
      gitCommit: git.commit,
      gitDirty: git.dirty,
      builtAt: new Date().toISOString(),
      signing: signingMetadata(forgeConfig, first.platform),
      artifacts,
    }
    await fs.writeFile(path.join(staging, manifestName), `${JSON.stringify(manifest, null, 2)}\n`)
    const manifestDigest = await fileDigest(path.join(staging, manifestName))
    await fs.writeFile(path.join(staging, checksumName), checksumText([...artifacts, { path: manifestName, ...manifestDigest }]))
    await verifyBuildArtifacts(staging)
    await cleanBuildArtifacts(directory)
    await fs.rename(staging, path.join(out, 'artifacts'))
    return manifest
  }
  finally {
    await fs.rm(staging, { recursive: true, force: true })
  }
}

async function listFiles(directory, prefix = '') {
  const files = []
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const relative = portablePath(prefix + entry.name)
    if (entry.isDirectory())
      files.push(...await listFiles(path.join(directory, entry.name), `${relative}/`))
    else if (entry.isFile())
      files.push(relative)
    else
      throw new Error(`Unexpected non-file in artifact directory: ${relative}`)
  }
  return files
}

export async function verifyBuildArtifacts(directory = path.join(root, 'out/artifacts')) {
  const manifestFile = path.join(directory, manifestName)
  const manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'))
  if (manifest.schemaVersion !== 1 || typeof manifest.productName !== 'string' || !manifest.productName
    || !/^\d+\.\d+\.\d+(?:[-+][a-z0-9.+-]+)?$/i.test(manifest.version)
    || !/^\d+\.\d+\.\d+(?:[-+][a-z0-9.+-]+)?$/i.test(manifest.electronVersion)
    || !platforms.has(manifest.platform) || !architectures.has(manifest.arch)
    || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(manifest.gitCommit)
    || typeof manifest.gitDirty !== 'boolean' || !Number.isFinite(Date.parse(manifest.builtAt))
    || manifest.signing?.scope !== 'distribution-identity'
    || !['unsigned', 'configured-unverified'].includes(manifest.signing.status)
    || manifest.signing.verified !== false
    || ['appRequested', 'installerRequested', 'notarizationRequested'].some(key => typeof manifest.signing[key] !== 'boolean')
    || !Array.isArray(manifest.artifacts) || !manifest.artifacts.length) {
    throw new Error('Invalid build manifest metadata')
  }
  const signingStatus = manifest.signing.appRequested || manifest.signing.installerRequested ? 'configured-unverified' : 'unsigned'
  if (manifest.signing.status !== signingStatus)
    throw new Error('Build signing metadata is inconsistent')
  const seen = new Set()
  for (const artifact of manifest.artifacts) {
    portablePath(artifact.path)
    if (!allowedArtifact(manifest.platform, artifact.path) || seen.has(artifact.path)
      || !Number.isSafeInteger(artifact.bytes) || artifact.bytes < 0 || !/^[a-f0-9]{64}$/.test(artifact.sha256)) {
      throw new Error(`Invalid build artifact: ${artifact.path}`)
    }
    seen.add(artifact.path)
    const digest = await fileDigest(path.join(directory, artifact.path))
    if (digest.bytes !== artifact.bytes || digest.sha256 !== artifact.sha256)
      throw new Error(`Artifact checksum or size mismatch: ${artifact.path}`)
  }
  const manifestDigest = await fileDigest(manifestFile)
  const expectedChecksums = checksumText([...manifest.artifacts, { path: manifestName, ...manifestDigest }])
  if (await fs.readFile(path.join(directory, checksumName), 'utf8') !== expectedChecksums)
    throw new Error('SHA256SUMS does not match the build manifest and artifacts')
  const expected = new Set([...seen, manifestName, checksumName])
  for (const file of await listFiles(directory)) {
    if (!expected.has(file))
      throw new Error(`Unlisted file in artifact directory: ${file}`)
  }
  return manifest
}
