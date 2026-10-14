import fs from 'node:fs/promises'
import { afterEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({ release: vi.fn() }))
vi.mock('@electron-forge/core', () => ({ api: { release: mocks.release } }))

const { runForge } = await import('../../scripts/forge.mjs')
const metadata = JSON.parse(await fs.readFile(new URL('../../package.json', import.meta.url), 'utf8'))

afterEach(() => {
  vi.unstubAllEnvs()
  vi.clearAllMocks()
})

describe('forge publish entry', () => {
  it('rejects a missing release tag before touching the publisher', async () => {
    vi.stubEnv('RELEASE_TAG', '')
    await expect(runForge(['publish'])).rejects.toThrow(/stable/)
    expect(mocks.release).not.toHaveBeenCalled()
  })
  it('passes the requested target as Forge 8 makeOptions after preflight', async () => {
    vi.stubEnv('RELEASE_TAG', `v${metadata.version}`)
    vi.stubEnv('GITHUB_REPOSITORY', metadata.desktop.updateRepository)
    vi.stubEnv('GITHUB_REPOSITORY_VISIBILITY', 'private')
    await runForge(['publish', '--arch=arm64', '--platform=darwin'])
    expect(mocks.release).toHaveBeenCalledWith(expect.objectContaining({
      makeOptions: { arch: 'arm64', platform: 'darwin' },
    }))
  })
})
