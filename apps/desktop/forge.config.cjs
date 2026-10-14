const path = require('node:path')
const process = require('node:process')
const { FusesPlugin } = require('@electron-forge/plugin-fuses')
const { FuseV1Options, FuseVersion } = require('@electron/fuses')
const metadata = require('./package.json')

const repository = metadata.desktop.updateRepository.split('/')
module.exports = {
  packagerConfig: {
    name: metadata.productName,
    executableName: 'YunLeFun',
    icon: path.join(__dirname, 'build/icons/icon'),
    appBundleId: metadata.desktop.appId,
    appCategoryType: 'public.app-category.entertainment',
    asar: true,
    // Only the explicitly materialized production tree is shipped.
    prune: false,
    ignore: (file) => {
      if (!file)
        return false
      return ![
        /^\/package\.json$/,
        /^\/LICENSE$/,
        /^\/dist-electron(?:\/|$)/,
        /^\/\.output$/,
        /^\/\.output\/public(?:\/|$)/,
      ].some(pattern => pattern.test(file.replaceAll('\\', '/')))
    },
    ...(process.env.APPLE_SIGN_IDENTITY
      ? {
          osxSign: { identity: process.env.APPLE_SIGN_IDENTITY, hardenedRuntime: true },
        }
      : {}),
    ...(process.env.APPLE_API_KEY_PATH
      ? {
          osxNotarize: {
            appleApiKey: process.env.APPLE_API_KEY_PATH,
            appleApiKeyId: process.env.APPLE_API_KEY_ID,
            appleApiIssuer: process.env.APPLE_API_ISSUER,
          },
        }
      : {}),
  },
  makers: [
    { name: '@electron-forge/maker-squirrel', config: {
      name: 'yunlefun',
      setupIcon: path.join(__dirname, 'build/icons/icon.ico'),
      iconUrl: 'https://apps.yunle.fun/favicon.ico',
      certificateFile: process.env.WINDOWS_CERTIFICATE_FILE,
      certificatePassword: process.env.WINDOWS_CERTIFICATE_PASSWORD,
    } },
    { name: '@electron-forge/maker-zip', platforms: ['darwin'] },
    { name: '@electron-forge/maker-dmg', config: { format: 'ULFO', icon: path.join(__dirname, 'build/icons/icon.icns') } },
    { name: '@electron-forge/maker-deb', config: { options: { name: 'yunlefun', bin: 'YunLeFun', icon: path.join(__dirname, 'build/icons/icon.png'), maintainer: metadata.author.name, homepage: metadata.repository.url } } },
  ],
  publishers: [{
    name: '@electron-forge/publisher-github',
    config: { repository: { owner: repository[0], name: repository[1] }, draft: true, prerelease: false },
  }],
  plugins: [new FusesPlugin({
    version: FuseVersion.V1,
    [FuseV1Options.RunAsNode]: false,
    [FuseV1Options.EnableCookieEncryption]: true,
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
    [FuseV1Options.EnableNodeCliInspectArguments]: false,
    [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
    [FuseV1Options.OnlyLoadAppFromAsar]: true,
  })],
  hooks: {
    async preMake() {
      const { cleanBuildArtifacts } = await import('./scripts/build-artifacts.mjs')
      await cleanBuildArtifacts()
      const { prepareMacosMaker } = await import('./scripts/prepare-macos-maker.mjs')
      await prepareMacosMaker()
    },
    async postMake(config, results) {
      const { createBuildArtifacts } = await import('./scripts/build-artifacts.mjs')
      const manifest = await createBuildArtifacts(results, { forgeConfig: config })
      console.info(`Verified ${manifest.artifacts.length} installers, build-manifest.json and SHA256SUMS in out/artifacts.`)
      return results
    },
    async packageAfterCopy(_config, buildPath) {
      const { materializeRuntimeDependencies } = await import('./scripts/runtime-dependencies.mjs')
      await materializeRuntimeDependencies(buildPath)
    },
    async prePackage() {
      const { runNode } = await import('./scripts/lib.mjs')
      await runNode(path.join(__dirname, 'scripts/build.mjs'))
    },
    async preStart() {
      if (process.env.YUNLE_DESKTOP_DEV_ORIGIN)
        return
      const { runNode } = await import('./scripts/lib.mjs')
      await runNode(path.join(__dirname, 'scripts/build.mjs'))
    },
  },
}
