import fs from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { root } from './lib.mjs'

export function validateRelease(metadata, environment = process.env) {
  const { RELEASE_TAG: tag, GITHUB_REPOSITORY: repository, GITHUB_REPOSITORY_VISIBILITY: visibility } = environment
  const stableTag = /^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/
  if (!tag || !stableTag.test(tag) || tag !== `v${metadata.version}`)
    throw new Error('Release tag must be a stable v<desktop package.json version> tag.')
  if (!repository || metadata.desktop?.updateRepository !== repository)
    throw new Error('Set desktop.updateRepository to this repository before publishing.')
  if (typeof metadata.desktop.updatesEnabled !== 'boolean')
    throw new Error('Set desktop.updatesEnabled to a boolean before publishing.')
  if (metadata.desktop.updatesEnabled === true && visibility !== 'public')
    throw new Error('The public Electron update service requires public repository visibility. Keep updates disabled for private builds.')
  return { tag, repository, updatesEnabled: metadata.desktop.updatesEnabled === true }
}

export async function checkRelease() {
  const metadata = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'))
  const release = validateRelease(metadata)
  console.info(`Validated release ${release.tag}; automatic updates ${release.updatesEnabled ? 'enabled' : 'disabled'}.`)
  return release
}

if (process.argv[1] && path.resolve(process.argv[1]) === import.meta.filename)
  await checkRelease()
