export interface CatalogBrowserApp {
  id?: string
  slug?: string
  websiteUrl: string
}

/** Open web content in a separate tab without exposing the host window. */
export async function openInAppBrowser(url: string) {
  const target = new URL(url)
  if (!['https:', 'http:'].includes(target.protocol) || target.username || target.password)
    throw new TypeError('Unsupported application URL')
  window.open(target.href, '_blank', 'noopener,noreferrer')
}

export function openCatalogAppInBrowser(app: CatalogBrowserApp): Promise<void> {
  if (!app.slug && !app.id)
    throw new TypeError('Catalog app requires a stable slug or id')
  return openInAppBrowser(app.websiteUrl)
}
