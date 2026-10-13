import { execFile } from 'node:child_process'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { promisify } from 'node:util'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { cleanBuildArtifacts, createBuildArtifacts, readGitState, verifyBuildArtifacts } from '../../scripts/build-artifacts.mjs'

const exec = promisify(execFile)
const abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
let directory

beforeEach(async () => {
  directory = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-artifacts-test-'))
})

afterEach(async () => {
  await fs.rm(directory, { recursive: true, force: true })
})

async function installer(relative, contents = 'abc') {
  const file = path.join(directory, 'out/make', relative)
  await fs.mkdir(path.dirname(file), { recursive: true })
  await fs.writeFile(file, contents)
  return file
}

function makeResult(artifacts, platform = 'darwin', arch = 'arm64') {
  return { artifacts, platform, arch, packageJSON: { version: '0.1.0', productName: '云乐坊' } }
}

function collect(results, forgeConfig = {}) {
  return createBuildArtifacts(results, {
    directory,
    forgeConfig,
    electronVersion: '44.7.0',
    gitState: { commit: 'a'.repeat(40), dirty: true },
  })
}

function verify() {
  return verifyBuildArtifacts(path.join(directory, 'out/artifacts'))
}

describe('installer distribution artifacts', () => {
  it('selects only the current Forge results and replaces the previous clean distribution', async () => {
    const previous = await installer('zip/darwin/x64/云乐坊-0.0.9.zip', 'old build')
    await collect([makeResult([previous], 'darwin', 'x64')])
    const current = await installer('dmg/arm64/云乐坊-0.1.0-arm64.dmg')
    await installer('dmg/arm64/云乐坊-0.0.9-arm64.dmg', 'stale version')
    await installer('zip/darwin/x64/云乐坊-0.1.0-x64.zip', 'another architecture')
    const manifest = await collect([makeResult([current])])
    expect(manifest).toMatchObject({
      version: '0.1.0',
      electronVersion: '44.7.0',
      platform: 'darwin',
      arch: 'arm64',
      gitCommit: 'a'.repeat(40),
      gitDirty: true,
      signing: { status: 'unsigned', scope: 'distribution-identity', verified: false },
      artifacts: [{ path: 'dmg/arm64/云乐坊-0.1.0-arm64.dmg', bytes: 3, sha256: abcSha256 }],
    })
    expect((await verify()).artifacts).toHaveLength(1)
    await expect(fs.stat(path.join(directory, 'out/artifacts/zip/darwin/x64/云乐坊-0.0.9.zip'))).rejects.toThrow()
    const checksums = await fs.readFile(path.join(directory, 'out/artifacts/SHA256SUMS'), 'utf8')
    expect(checksums).toContain(`${abcSha256} *dmg/arm64/云乐坊-0.1.0-arm64.dmg\n`)
    expect(checksums).toMatch(/[a-f0-9]{64} \*build-manifest\.json\n$/)
    expect(checksums).not.toContain('x64')
    expect(checksums).not.toContain('0.0.9')
  })

  it('supports Windows Squirrel files with spaces and Unicode without recording signing credentials', async () => {
    const setup = await installer('squirrel.windows/x64/云乐坊-0.1.0 Setup.exe')
    const release = await installer('squirrel.windows/x64/RELEASES')
    const nupkg = await installer('squirrel.windows/x64/yunlefun-0.1.0-full.nupkg')
    await collect([makeResult([setup, nupkg, release], 'win32', 'x64')], {
      makers: [{ name: '@electron-forge/maker-squirrel', config: { certificateFile: '/private/signing.pfx', certificatePassword: 'must-never-appear' } }],
    })
    const manifest = await verify()
    expect(manifest.signing).toMatchObject({ status: 'configured-unverified', installerRequested: true, verified: false })
    expect(manifest.artifacts.map(artifact => artifact.path)).toEqual([
      'squirrel.windows/x64/RELEASES',
      'squirrel.windows/x64/yunlefun-0.1.0-full.nupkg',
      'squirrel.windows/x64/云乐坊-0.1.0 Setup.exe',
    ])
    const contents = await fs.readFile(path.join(directory, 'out/artifacts/build-manifest.json'), 'utf8')
    expect(contents).not.toContain('must-never-appear')
    expect(contents).not.toContain('/private/signing.pfx')
  })

  it('describes configured macOS signing and notarization without claiming they were verified', async () => {
    const zip = await installer('zip/darwin/arm64/云乐坊-0.1.0.zip')
    const manifest = await collect([makeResult([zip])], { packagerConfig: { osxSign: { identity: 'private identity' }, osxNotarize: { appleApiKey: 'private key' } } })
    expect(manifest.signing).toMatchObject({ status: 'configured-unverified', appRequested: true, notarizationRequested: true, verified: false })
    expect(JSON.stringify(manifest)).not.toContain('private')
  })

  it('detects same-size installer tampering and missing files', async () => {
    const file = await installer('deb/x64/yunlefun_0.1.0_amd64.deb')
    await collect([makeResult([file], 'linux', 'x64')])
    const copied = path.join(directory, 'out/artifacts/deb/x64/yunlefun_0.1.0_amd64.deb')
    await fs.writeFile(copied, 'xyz')
    await expect(verify()).rejects.toThrow('checksum or size mismatch')
    await fs.rm(copied)
    await expect(verify()).rejects.toThrow()
  })

  it('detects changed metadata, a damaged checksum list and unlisted environment files', async () => {
    const file = await installer('dmg/arm64/云乐坊.dmg')
    await collect([makeResult([file])])
    const manifestFile = path.join(directory, 'out/artifacts/build-manifest.json')
    const originalManifest = await fs.readFile(manifestFile, 'utf8')
    await fs.writeFile(manifestFile, originalManifest.replace('"gitDirty": true', '"gitDirty": false'))
    await expect(verify()).rejects.toThrow('SHA256SUMS')
    await fs.writeFile(manifestFile, originalManifest)
    const checksums = path.join(directory, 'out/artifacts/SHA256SUMS')
    const originalChecksums = await fs.readFile(checksums, 'utf8')
    await fs.writeFile(checksums, originalChecksums.replace(abcSha256, '0'.repeat(64)))
    await expect(verify()).rejects.toThrow('SHA256SUMS')
    await fs.writeFile(checksums, originalChecksums)
    await fs.writeFile(path.join(directory, 'out/artifacts/runtime.env'), 'private configuration')
    await expect(verify()).rejects.toThrow('Unlisted file')
  })

  it('rejects an environment file or mixed architectures in the current maker results', async () => {
    const env = await installer('runtime.env', 'private configuration')
    await expect(collect([makeResult([env])])).rejects.toThrow('Unexpected installer artifact')
    const dmg = await installer('dmg/arm64/云乐坊.dmg')
    const zip = await installer('zip/darwin/x64/云乐坊.zip')
    await expect(collect([makeResult([dmg]), makeResult([zip], 'darwin', 'x64')])).rejects.toThrow('one product version, platform and architecture')
    await expect(fs.stat(path.join(directory, 'out/artifacts'))).rejects.toThrow()
  })

  it('invalidates the previous distribution before a new maker attempt', async () => {
    const file = await installer('dmg/arm64/云乐坊.dmg')
    await collect([makeResult([file])])
    await cleanBuildArtifacts(directory)
    await expect(verify()).rejects.toThrow()
  })

  it('records a real Git commit and distinguishes clean, modified and untracked source trees', async () => {
    await exec('git', ['init', '--quiet'], { cwd: directory })
    await fs.writeFile(path.join(directory, 'source.txt'), 'committed source')
    await exec('git', ['add', 'source.txt'], { cwd: directory })
    await exec('git', ['-c', 'user.name=Build Test', '-c', 'user.email=build-test@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'test(build): create source fixture'], { cwd: directory })
    const clean = await readGitState(directory)
    expect(clean.commit).toMatch(/^[a-f0-9]{40}$/)
    expect(clean.dirty).toBe(false)
    await fs.writeFile(path.join(directory, 'source.txt'), 'modified source')
    expect(await readGitState(directory)).toEqual({ commit: clean.commit, dirty: true })
    await exec('git', ['checkout', '--', 'source.txt'], { cwd: directory })
    await fs.writeFile(path.join(directory, 'untracked.txt'), 'untracked source')
    expect((await readGitState(directory)).dirty).toBe(true)
  })
})
