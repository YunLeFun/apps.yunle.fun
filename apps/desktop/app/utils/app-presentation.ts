import type { CatalogEntry } from '../../shared/desktop'

const APP_COLORS: Readonly<Record<string, string>> = {
  'cook': '#d97851',
  'air-conditioner': '#69b1f5',
  'electric-fan': '#89d9b2',
  'char-dust': '#343438',
  'color-dust': '#d9e9ca',
  'pixi-painter': '#f1f0ed',
  'fc': '#e96b5c',
  'paper-star': '#adc7dc',
  'dayun-kicker': '#f2d577',
  'wenta': '#edb4c3',
  'web-resume': '#d8d6d0',
}

const SHORT_DESCRIPTIONS: Readonly<Record<string, string>> = {
  'air-conditioner': '随身的小凉意',
  'electric-fan': '给夏天一点风',
  'char-dust': '把图片变成字符画',
  'color-dust': '从图片寻找配色',
  'pixi-painter': '随手画一点灵感',
  'fc': '重温经典小游戏',
}

export function appIconColor(slug: string): string {
  return APP_COLORS[slug] || '#b6bbc6'
}

export function appSummary(app: Readonly<CatalogEntry>): string {
  return app.unavailableReason || SHORT_DESCRIPTIONS[app.slug] || app.description || app.category
}
