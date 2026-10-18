import { readFile, stat } from 'node:fs/promises'

export function validatePreviewTarget(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || value.projectId !== 'pages-duzdocfvhq4g'
    || value.environment !== 'Preview' || value.status !== 'Success'
    || value.branch !== 'codex/ios-native-app'
    || typeof value.deploymentId !== 'string' || !/^dp[a-z0-9]{8,24}$/.test(value.deploymentId)
    || typeof value.commit !== 'string' || !/^[a-f0-9]{40}$/.test(value.commit)
    || value.origin !== `https://yunlefun-apps-${value.deploymentId}.edgeone.cool`) {
    throw new Error('An approved, successful Apps preview deployment receipt is required')
  }
  return value
}

export async function readPreviewTarget(path) {
  const info = await stat(path)
  if (!info.isFile() || (info.mode & 0o077) !== 0)
    throw new Error('The local preview receipt must be an owner-only regular file')
  const target = validatePreviewTarget(JSON.parse(await readFile(path, 'utf8')))
  previewHeaders(target)
  return target
}

export function previewHeaders(target, now = Date.now()) {
  validatePreviewTarget(target)
  const access = target.previewAccess
  if (!access || !Number.isSafeInteger(access.expiresAt)
    || access.expiresAt <= now || access.expiresAt > now + 3 * 60 * 60 * 1000 + 60000
    || typeof access.cookie !== 'string' || access.cookie.length > 8192
    || !/^[\x20-\x7E]+$/.test(access.cookie)) {
    throw new Error('A fresh, bounded platform preview session is required')
  }
  const pairs = access.cookie.split('; ')
  if (pairs.length !== 2 || !/^eo_token=[^;\s]+$/.test(pairs[0]) || !/^eo_time=\d{1,16}$/.test(pairs[1]))
    throw new Error('Unexpected platform preview cookie')
  return { Cookie: access.cookie }
}
