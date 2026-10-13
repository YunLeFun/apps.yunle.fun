import { readFile } from 'node:fs/promises'

import { describe, expect, it } from 'vitest'

describe('android release boundary', () => {
  it('fails closed unless the complete signing environment is present', async () => {
    const build = await readFile(
      new URL('../../android/app/build.gradle', import.meta.url),
      'utf8',
    )

    expect(build).toContain('YUNLEFUN_ANDROID_RELEASE_STORE_FILE')
    expect(build).toContain('YUNLEFUN_ANDROID_RELEASE_STORE_PASSWORD')
    expect(build).toContain('YUNLEFUN_ANDROID_RELEASE_KEY_ALIAS')
    expect(build).toContain('YUNLEFUN_ANDROID_RELEASE_KEY_PASSWORD')
    expect(build).toContain('YUNLEFUN_ANDROID_VERSION_CODE')
    expect(build).toContain('versionName packageMetadata.version.toString()')
    expect(build).toContain('releasePackagingRequested && (!hasCompleteReleaseSigningValues || !parsedReleaseVersionCode)')
  })

  it('verifies both release artifacts without storing signing credentials', async () => {
    const [script, gitignore] = await Promise.all([
      readFile(new URL('../../scripts/android-release.sh', import.meta.url), 'utf8'),
      readFile(new URL('../../../../.gitignore', import.meta.url), 'utf8'),
    ])

    expect(script).toContain('apksigner')
    expect(script).toContain('jarsigner -verify -strict')
    expect(script).toContain('-keystore "$YUNLEFUN_ANDROID_RELEASE_STORE_FILE"')
    expect(script).toContain('-storepass:env YUNLEFUN_ANDROID_RELEASE_STORE_PASSWORD')
    expect(script).toContain('YUNLEFUN_ANDROID_RELEASE_CERT_SHA256')
    expect(script).toContain('Release APK certificate does not match the pinned upload key')
    expect(script).toContain('Release AAB certificate does not match the pinned upload key')
    expect(script).toContain('shasum -a 256')
    expect(script).toContain('pnpm exec cap sync android')
    expect(script).not.toContain('pnpm sync')
    expect(script).not.toMatch(/(?:STORE|KEY)_PASSWORD=['"][^$<]/)
    expect(gitignore).toContain('*.jks')
    expect(gitignore).toContain('*.keystore')
  })
})
