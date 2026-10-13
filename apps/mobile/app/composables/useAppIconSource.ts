import type { MaybeRefOrGetter } from 'vue'
import type { AppIconAssets } from '~/types/app'
import { resolveAppIconPresentation } from '~/utils/appIconAssets'
import { getPublicCloudbaseStorageUrl } from '~/utils/cloudbase-storage-url'

/** 为仍使用原生 img 的小型界面解析稳定的完整图标 URL。 */
export function useAppIconSource(
  assets: MaybeRefOrGetter<AppIconAssets | null | undefined>,
  legacyIcon: MaybeRefOrGetter<string | null | undefined>,
) {
  const config = useRuntimeConfig()
  const settingsStore = useSettingsStore()
  const resolvedSrc = computed(() => {
    const presentation = resolveAppIconPresentation({
      assets: toValue(assets) || undefined,
      legacyIcon: toValue(legacyIcon) || undefined,
      dark: settingsStore.currentTheme === 'dark',
      preferOriginal: true,
    })
    return presentation.source
      ? getPublicCloudbaseStorageUrl(
          presentation.source,
          config.public.tcbEnvId as string,
          config.public.cloudbaseStoragePublicOrigin as string,
        )
      : null
  })

  return { resolvedSrc }
}
