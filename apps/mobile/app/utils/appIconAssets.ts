import type { AppIconAssets, AppIconAssetVariants } from '~/types/app'

export interface AppIconAssetVariantsDraft {
  src: string
  darkSrc: string
}

export interface AppIconAssetsDraft {
  appIcon: AppIconAssetVariantsDraft
  mark: AppIconAssetVariantsDraft
}

export type AppIconPresentationRole = 'app-icon' | 'mark' | 'legacy' | 'emoji'

export interface AppIconPresentation {
  role: AppIconPresentationRole
  source: string
}

export function createEmptyAppIconAssetsDraft(): AppIconAssetsDraft {
  return {
    appIcon: { src: '', darkSrc: '' },
    mark: { src: '', darkSrc: '' },
  }
}

export function createAppIconAssetsDraft(assets?: AppIconAssets): AppIconAssetsDraft {
  return {
    appIcon: {
      src: assets?.appIcon?.src || '',
      darkSrc: assets?.appIcon?.darkSrc || '',
    },
    mark: {
      src: assets?.mark?.src || '',
      darkSrc: assets?.mark?.darkSrc || '',
    },
  }
}

export function compactAppIconAssets(draft: AppIconAssetsDraft): AppIconAssets | undefined {
  const appIcon = compactVariants(draft.appIcon)
  const mark = compactVariants(draft.mark)
  if (!appIcon && !mark)
    return undefined
  return { appIcon, mark }
}

/**
 * 选择实际展示资源：原始风格优先完整图标，其余风格优先透明主体。
 * 未提供主体时仍原样展示完整图标，避免给完整图标重复叠加生成式背景。
 */
export function resolveAppIconPresentation(options: {
  assets?: AppIconAssets
  legacyIcon?: string
  dark?: boolean
  preferOriginal?: boolean
}): AppIconPresentation {
  const { assets, dark = false, preferOriginal = false } = options
  const primary = preferOriginal ? assets?.appIcon : assets?.mark
  const secondary = preferOriginal ? assets?.mark : assets?.appIcon
  const primaryRole: AppIconPresentationRole = preferOriginal ? 'app-icon' : 'mark'
  const secondaryRole: AppIconPresentationRole = preferOriginal ? 'mark' : 'app-icon'

  const primarySource = selectVariant(primary, dark)
  if (primarySource)
    return { role: primaryRole, source: primarySource }

  const secondarySource = selectVariant(secondary, dark)
  if (secondarySource)
    return { role: secondaryRole, source: secondarySource }

  const legacySource = options.legacyIcon?.trim() || ''
  if (legacySource)
    return { role: 'legacy', source: legacySource }

  return { role: 'emoji', source: '' }
}

function compactVariants(value: AppIconAssetVariantsDraft): AppIconAssetVariants | undefined {
  const src = value.src.trim()
  if (!src)
    return undefined
  const darkSrc = value.darkSrc.trim()
  return darkSrc ? { src, darkSrc } : { src }
}

function selectVariant(value: AppIconAssetVariants | undefined, dark: boolean): string {
  if (!value)
    return ''
  return (dark ? value.darkSrc?.trim() : '') || value.src.trim()
}
