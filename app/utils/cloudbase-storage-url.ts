const CLOUDBASE_STORAGE_HOST_SUFFIXES = [
  '.tcb.qcloud.la',
  '.tcb.qcloud.cn',
]
const CLOUDBASE_PUBLIC_HOST_SUFFIX = '.tcb.qcloud.la'
const PUBLIC_AVATAR_PATH_PATTERN = /^\/avatars\/[^/]+\.(?:jpe?g|png|webp)$/i

function isPublicAvatarPath(pathname: string): boolean {
  try {
    return PUBLIC_AVATAR_PATH_PATTERN.test(decodeURIComponent(pathname))
  }
  catch {
    return false
  }
}

function getPublicStorageOrigin(value: string): URL | null {
  try {
    const url = new URL(value)
    const isCloudbaseStorage = CLOUDBASE_STORAGE_HOST_SUFFIXES.some(suffix =>
      url.hostname.endsWith(suffix),
    )
    if (
      url.protocol !== 'https:'
      || url.pathname !== '/'
      || url.search
      || url.hash
      || !isCloudbaseStorage
    ) {
      return null
    }
    return url
  }
  catch {
    return null
  }
}

function getPublicCloudbaseFileUrl(
  source: string,
  envId: string,
  publicStorageOrigin: string,
): string | null {
  if (!source.startsWith('cloud://') || !envId)
    return null

  try {
    const url = new URL(source)
    const publicOrigin = getPublicStorageOrigin(publicStorageOrigin)
    const environmentPrefix = `${envId}.`
    if (
      !publicOrigin
      || url.protocol !== 'cloud:'
      || !url.hostname.startsWith(environmentPrefix)
      || !isPublicAvatarPath(url.pathname)
    ) {
      return null
    }

    const bucket = url.hostname.slice(environmentPrefix.length)
    if (
      !bucket
      || !bucket.includes(envId)
      || publicOrigin.hostname !== `${bucket}${CLOUDBASE_PUBLIC_HOST_SUFFIX}`
    ) {
      return null
    }

    return new URL(url.pathname, publicOrigin).toString()
  }
  catch {
    return null
  }
}

function getCurrentCloudbaseStorageUrl(
  source: string,
  envId: string,
  publicStorageOrigin: string,
): URL | null {
  try {
    const url = new URL(source)
    const publicOrigin = getPublicStorageOrigin(publicStorageOrigin)

    if (
      !publicOrigin
      || url.protocol !== 'https:'
      || url.origin !== publicOrigin.origin
      || !url.hostname.includes(envId)
      || !isPublicAvatarPath(url.pathname)
    ) {
      return null
    }

    return url
  }
  catch {
    return null
  }
}

/**
 * 返回头像等公开 CloudBase 对象的稳定 URL。
 *
 * 认证资料里可能残留短期签名查询参数；公开读后应直接使用去掉签名的
 * 原始地址，让浏览器和 CDN 能长期缓存。第三方地址保持原样。
 */
export function getPublicCloudbaseStorageUrl(
  source: string,
  envId: string,
  publicStorageOrigin: string,
): string | null {
  const fileUrl = getPublicCloudbaseFileUrl(source, envId, publicStorageOrigin)
  if (fileUrl)
    return fileUrl
  if (source.startsWith('cloud://'))
    return null

  const url = getCurrentCloudbaseStorageUrl(source, envId, publicStorageOrigin)
  if (!url)
    return source

  url.search = ''
  url.hash = ''
  return url.toString()
}
