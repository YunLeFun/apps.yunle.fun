// Only curated public assets may supply desktop icons; catalog metadata is not a source.
const APP_ICON_BASE_URL = 'https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/desktop/app-icons/v1/'

export const APP_ICON_URLS = Object.freeze({
  'cook': `${APP_ICON_BASE_URL}cook.webp`,
  'air-conditioner': `${APP_ICON_BASE_URL}air-conditioner.webp`,
  'give-me-money': `${APP_ICON_BASE_URL}give-me-money.webp`,
  'electric-fan': `${APP_ICON_BASE_URL}electric-fan.webp`,
  'fc': `${APP_ICON_BASE_URL}fc.webp`,
  'chat-generator': `${APP_ICON_BASE_URL}chat-generator.webp`,
  'ai-sfc': `${APP_ICON_BASE_URL}ai-sfc.webp`,
  'color-dust': `${APP_ICON_BASE_URL}color-dust.webp`,
  'char-dust': `${APP_ICON_BASE_URL}char-dust.webp`,
  'go-far-away': `${APP_ICON_BASE_URL}go-far-away.webp`,
  'birthday': `${APP_ICON_BASE_URL}birthday.webp`,
  'pixi-painter': `${APP_ICON_BASE_URL}pixi-painter.webp`,
  'web-resume': `${APP_ICON_BASE_URL}web-resume.webp`,
  'ak-ui': `${APP_ICON_BASE_URL}ak-ui.webp`,
  'augma': `${APP_ICON_BASE_URL}augma.webp`,
  'explosions': `${APP_ICON_BASE_URL}explosions.webp`,
  'everything-generator': `${APP_ICON_BASE_URL}everything-generator.webp`,
  'yunjian': `${APP_ICON_BASE_URL}yunjian.webp`,
  'wenta': `${APP_ICON_BASE_URL}wenta.webp`,
  'play': `${APP_ICON_BASE_URL}play.webp`,
  'paper-star': `${APP_ICON_BASE_URL}paper-star.webp`,
  'smap': `${APP_ICON_BASE_URL}smap.webp`,
  'pachinko': `${APP_ICON_BASE_URL}pachinko.webp`,
  'dayun-kicker': `${APP_ICON_BASE_URL}dayun-kicker.webp`,
  'advjs-studio': `${APP_ICON_BASE_URL}advjs-studio.webp`,
  'sponsors': `${APP_ICON_BASE_URL}sponsors.webp`,
  'wc-github-corners': `${APP_ICON_BASE_URL}wc-github-corners.webp`,
  'star-markdown-css': `${APP_ICON_BASE_URL}star-markdown-css.webp`,
})

export function appIconUrl(slug: string): string {
  return Object.hasOwn(APP_ICON_URLS, slug) ? APP_ICON_URLS[slug as keyof typeof APP_ICON_URLS] : ''
}
