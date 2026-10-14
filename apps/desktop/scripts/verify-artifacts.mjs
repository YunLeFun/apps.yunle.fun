import { verifyBuildArtifacts } from './build-artifacts.mjs'

const manifest = await verifyBuildArtifacts()
console.info(`Verified ${manifest.artifacts.length} installer artifacts for ${manifest.productName} ${manifest.version} (${manifest.platform}/${manifest.arch}), git ${manifest.gitCommit}${manifest.gitDirty ? ' (dirty)' : ''}.`)
