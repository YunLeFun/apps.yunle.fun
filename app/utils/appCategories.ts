import type { AppCategory } from '~/constants/apps'
import { APP_CATEGORIES } from '~/constants/apps'

interface CategorizedApp {
  category?: string
}

const FALLBACK_ALL_CATEGORY: AppCategory = {
  id: 'all',
  name: '全部',
  icon: '📱',
}

/**
 * 根据当前范围内的应用生成可用分类。
 *
 * 已配置的分类沿用全局顺序与图标；应用提交的其他分类按首次出现顺序追加。
 */
export function getAvailableAppCategories(
  apps: readonly CategorizedApp[],
): AppCategory[] {
  const availableNames = new Set<string>()

  for (const app of apps) {
    const category = app.category?.trim()
    if (category && category !== '全部')
      availableNames.add(category)
  }

  const allCategory
    = APP_CATEGORIES.find(category => category.name === '全部')
      ?? FALLBACK_ALL_CATEGORY
  const configuredCategories = APP_CATEGORIES.filter(category =>
    category.name !== '全部' && availableNames.has(category.name),
  )
  const configuredNames = new Set(
    configuredCategories.map(category => category.name),
  )
  const submittedCategories = Array.from(availableNames)
    .filter(name => !configuredNames.has(name))
    .map(name => ({
      id: `submitted:${name}`,
      name,
      icon: '📂',
    }))

  return [allCategory, ...configuredCategories, ...submittedCategories]
}
