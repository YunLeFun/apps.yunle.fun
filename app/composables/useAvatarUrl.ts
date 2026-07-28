import type { MaybeRefOrGetter } from 'vue'
import { computed, toValue } from 'vue'
import { getPublicCloudbaseStorageUrl } from '~/utils/cloudbase-storage-url'

/**
 * 返回头像的稳定公共 URL，不为公开头像生成短期签名。
 */
export function useAvatarUrl(source: MaybeRefOrGetter<string | null | undefined>) {
  const config = useRuntimeConfig()
  const envId = config.public.tcbEnvId as string
  const publicStorageOrigin = config.public.cloudbaseStoragePublicOrigin as string
  const resolvedSrc = computed(() => {
    const currentSource = toValue(source)
    return currentSource
      ? getPublicCloudbaseStorageUrl(currentSource, envId, publicStorageOrigin)
      : null
  })

  return {
    resolvedSrc,
  }
}
