const CLOUDBASE_STORAGE_HOST_SUFFIXES = [
  '.tcb.qcloud.la',
  '.tcb.qcloud.cn',
]

/**
 * 从当前 CloudBase 环境的传统存储 URL 中提取对象路径。
 * 外部头像地址保持原样，避免拿当前环境的凭证去签名第三方资源。
 */
export function getCloudbaseStoragePath(source: string, envId: string): string | null {
  try {
    const url = new URL(source)
    const isCloudbaseStorage = CLOUDBASE_STORAGE_HOST_SUFFIXES.some(suffix =>
      url.hostname.endsWith(suffix),
    )

    if (
      url.protocol !== 'https:'
      || !isCloudbaseStorage
      || !url.hostname.includes(envId)
    ) {
      return null
    }

    const path = decodeURIComponent(url.pathname).replace(/^\/+/, '')
    return path || null
  }
  catch {
    return null
  }
}
