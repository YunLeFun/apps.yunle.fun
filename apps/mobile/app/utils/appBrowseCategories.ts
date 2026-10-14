export interface BrowseCategory {
  id: string
  name: string
  icon: string
  count: number
}

interface CategorizedApp {
  id?: string
  slug?: string
  category?: string
}

const BROWSE_CATEGORIES = [
  { id: 'all', name: '全部', icon: '📱' },
  { id: 'tools', name: '效率工具', icon: '🔧' },
  { id: 'design', name: '创意设计', icon: '🎨' },
  { id: 'life', name: '生活方式', icon: '🏠' },
  { id: 'games', name: '游戏', icon: '🎮' },
  { id: 'interesting', name: '趣味娱乐', icon: '🤣' },
  { id: 'ai', name: 'AI', icon: '✨' },
  { id: 'development', name: '开发', icon: '💻' },
  { id: 'others', name: '其他', icon: '📂' },
] as const

const CATEGORY_ALIASES = new Map([
  ['工具', '效率工具'],
  ['效率工具', '效率工具'],
  ['设计', '创意设计'],
  ['生活', '生活方式'],
  ['整活', '趣味娱乐'],
  ['插件', '开发'],
  ['参与', '开发'],
  ['实验', '开发'],
  ['开发', '开发'],
])

// Only these built-ins' known legacy labels are reclassified for browsing.
// Any other explicit category supplied by the publisher keeps precedence.
const BUILTIN_CATEGORY_OVERRIDES = new Map<string, { name: string, legacyCategories: readonly string[] }>([
  ['cook', { name: '生活方式', legacyCategories: ['应用'] }],
  ['ai-sfc', { name: 'AI', legacyCategories: ['应用'] }],
  ['char-dust', { name: '创意设计', legacyCategories: ['应用'] }],
  ['color-dust', { name: '创意设计', legacyCategories: ['应用'] }],
  ['pixi-painter', { name: '创意设计', legacyCategories: ['应用', '工具'] }],
  ['birthday', { name: '趣味娱乐', legacyCategories: ['应用'] }],
  ['go-far-away', { name: '生活方式', legacyCategories: ['应用'] }],
  ['fc', { name: '游戏', legacyCategories: ['整活'] }],
])

/** Derive a browsing label without changing the stored application category. */
export function getBrowseCategory(app: CategorizedApp): string {
  const category = app.category?.trim() || ''
  if (!category || category === '全部')
    return '其他'

  for (const identifier of [app.id, app.slug]) {
    const override = BUILTIN_CATEGORY_OVERRIDES.get(identifier || '')
    if (override?.legacyCategories.includes(category))
      return override.name
  }

  if (category === '应用')
    return '其他'

  return CATEGORY_ALIASES.get(category) ?? category
}

/** Keep older in-memory filter selections usable after renaming browse groups. */
export function normalizeBrowseCategorySelection(selected: string): string {
  const category = selected.trim()
  return CATEGORY_ALIASES.get(category) ?? (category || '全部')
}

/** Match canonical groups while preserving exact matches for legacy labels. */
export function matchesBrowseCategory(app: CategorizedApp, selected: string): boolean {
  const category = normalizeBrowseCategorySelection(selected)
  return category === '全部'
    || getBrowseCategory(app) === category
    || app.category?.trim() === selected.trim()
}

/** Count the complete current scope, independently of search and pagination. */
export function getAvailableBrowseCategories(apps: readonly CategorizedApp[]): BrowseCategory[] {
  const counts = new Map<string, number>()
  for (const app of apps) {
    const category = getBrowseCategory(app)
    counts.set(category, (counts.get(category) || 0) + 1)
  }

  const configuredNames = new Set<string>(BROWSE_CATEGORIES.map(category => category.name))
  const configured = BROWSE_CATEGORIES
    .filter(category => category.name === '全部' || counts.has(category.name))
    .map(category => ({
      ...category,
      count: category.name === '全部' ? apps.length : counts.get(category.name)!,
    }))
  const custom = Array.from(counts)
    .filter(([name]) => !configuredNames.has(name))
    .map(([name, count]) => ({ id: `custom:${name}`, name, icon: '📂', count }))

  return [...configured, ...custom]
}
