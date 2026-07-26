export interface RumLocationLike {
  href: string
  pathname: string
  search: string
  hash: string
}

export const RUM_PUBLIC_ORIGIN = 'https://apps.yunle.fun'

/**
 * Tencent RUM groups page views by the reported `from` URL.
 *
 * Capacitor serves the bundled app from `capacitor://localhost`, which is not
 * a public Web origin and is not grouped as an application page in RUM.
 * Preserve the current route while mapping native-shell pages to the public
 * HTTPS origin used by the same application.
 */
export function getRumPageUrl(location: RumLocationLike, isNativePlatform: boolean): string {
  if (!isNativePlatform)
    return location.href

  return new URL(
    `${location.pathname}${location.search}${location.hash}`,
    RUM_PUBLIC_ORIGIN,
  ).href
}
