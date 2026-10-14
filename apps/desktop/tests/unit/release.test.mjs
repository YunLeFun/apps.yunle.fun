import { describe, expect, it } from 'vitest'
import { validateRelease } from '../../scripts/check-release.mjs'

const metadata = { version: '0.1.0', desktop: { updateRepository: 'YunLeFun/apps.yunle.fun', updatesEnabled: false } }
const environment = { RELEASE_TAG: 'v0.1.0', GITHUB_REPOSITORY: 'YunLeFun/apps.yunle.fun', GITHUB_REPOSITORY_VISIBILITY: 'private' }

describe('desktop release preflight', () => {
  it('allows private draft distribution with automatic updates disabled', () => {
    expect(validateRelease(metadata, environment)).toMatchObject({ tag: 'v0.1.0', updatesEnabled: false })
  })
  it('rejects missing, mismatched and invalid stable version tags', () => {
    for (const tag of [undefined, 'v0.2.0', 'v00.1.0', 'v0.1.0-beta.1', 'mobile-v0.1.0'])
      expect(() => validateRelease(metadata, { ...environment, RELEASE_TAG: tag })).toThrow(/stable/)
  })
  it('rejects an unexpected destination repository', () => {
    for (const repository of [undefined, 'another/repository'])
      expect(() => validateRelease(metadata, { ...environment, GITHUB_REPOSITORY: repository })).toThrow(/repository/)
  })
  it('rejects ambiguous updater configuration', () => {
    expect(() => validateRelease({ ...metadata, desktop: { ...metadata.desktop, updatesEnabled: 'false' } }, environment)).toThrow(/boolean/)
  })
  it('refuses public updater releases from private or unknown repository visibility', () => {
    const updates = { ...metadata, desktop: { ...metadata.desktop, updatesEnabled: true } }
    for (const visibility of ['private', undefined])
      expect(() => validateRelease(updates, { ...environment, GITHUB_REPOSITORY_VISIBILITY: visibility })).toThrow(/public/)
    expect(validateRelease(updates, { ...environment, GITHUB_REPOSITORY_VISIBILITY: 'public' }).updatesEnabled).toBe(true)
  })
})
