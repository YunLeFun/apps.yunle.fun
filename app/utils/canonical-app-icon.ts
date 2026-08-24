import type { YlfAppInfo } from '@yunlefun/types'

const CMS_CATALOG_KEYS = new Set(['cms', 'yunjian'])
const CMS_APP_ICON = '/app-icons/cms-app-icon.svg'
const GIVE_ME_MONEY_CATALOG_KEYS = new Set(['give-me-money'])
const GIVE_ME_MONEY_MARK = 'https://gmm.yunle.fun/favicon.png'

/**
 * Keep first-party launcher assets stable while the catalog publication catches up.
 *
 * Give Me Money already publishes its canonical transparent mark as a favicon,
 * so reuse it directly instead of duplicating it in YunLeFun/icons.
 *
 * The CMS SVG snapshot is copied exactly from YunLeFun/icons. Keep its complete
 * app icon because the transparent mark has insufficient contrast on the
 * catalog's dark theme color.
 */
export function withCanonicalAppIcon<T extends YlfAppInfo>(app: T): T {
  if (GIVE_ME_MONEY_CATALOG_KEYS.has(app.slug) || GIVE_ME_MONEY_CATALOG_KEYS.has(app.id)) {
    return {
      ...app,
      iconAssets: {
        mark: { src: GIVE_ME_MONEY_MARK },
      },
    }
  }

  if (!CMS_CATALOG_KEYS.has(app.slug) && !CMS_CATALOG_KEYS.has(app.id))
    return app

  return {
    ...app,
    iconAssets: {
      appIcon: { src: CMS_APP_ICON },
    },
  }
}
