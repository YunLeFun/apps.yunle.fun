import type { YlfAppInfo } from '@yunlefun/types'

const CMS_CATALOG_KEYS = new Set(['cms', 'yunjian'])
const CMS_APP_ICON = '/app-icons/cms-app-icon.svg'
const CMS_MARK = '/app-icons/cms-mark.svg'

/**
 * Keep first-party launcher assets stable while the catalog publication catches up.
 *
 * The SVG snapshots are copied exactly from YunLeFun/icons:
 * `packages/icons/svg/cms-{app-icon,mark}.svg`.
 */
export function withCanonicalAppIcon<T extends YlfAppInfo>(app: T): T {
  if (!CMS_CATALOG_KEYS.has(app.slug) && !CMS_CATALOG_KEYS.has(app.id))
    return app

  return {
    ...app,
    iconAssets: {
      appIcon: { src: CMS_APP_ICON },
      mark: { src: CMS_MARK },
    },
  }
}
