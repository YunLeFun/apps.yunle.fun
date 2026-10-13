// Configure a verified public COS object URL. Decorative media is not bundled.
export const COOK_FEATURE_IMAGE_URL = 'https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/desktop/banners/cook-feature.png'

export function editorialMediaOrigin(input: string): string {
  try {
    const url = new URL(input)
    const publicHost = /^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(url.hostname)
      && !/^\d+(?:\.\d+){3}$/.test(url.hostname)
      && !/(?:^|\.)(?:localhost|local|internal|test|invalid)$/.test(url.hostname)
    return url.protocol === 'https:' && publicHost
      && !url.username && !url.password && !url.port && !url.search && !url.hash
      ? url.origin
      : ''
  }
  catch { return '' }
}

export const EDITORIAL_MEDIA_ORIGIN = editorialMediaOrigin(COOK_FEATURE_IMAGE_URL)
