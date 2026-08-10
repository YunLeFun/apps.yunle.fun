import type { YlfAppInfo } from '@yunlefun/types'

const CMS_CATALOG_KEYS = new Set(['cms', 'yunjian'])
const CMS_APP_ICON = '/app-icons/cms-app-icon.svg'

/**
 * Keep first-party launcher assets stable while the catalog publication catches up.
 *
 * The SVG snapshot is copied exactly from YunLeFun/icons:
 * `packages/icons/svg/cms-app-icon.svg`.
 *
 * Keep the complete app icon instead of supplying the transparent mark: the
 * mark's ink color has insufficient contrast on the catalog's dark theme color.
 */
export function withCanonicalAppIcon<T extends YlfAppInfo>(app: T): T {
  if (!CMS_CATALOG_KEYS.has(app.slug) && !CMS_CATALOG_KEYS.has(app.id))
    return app

  return {
    ...app,
    iconAssets: {
      appIcon: { src: CMS_APP_ICON },
    },
  }
}
