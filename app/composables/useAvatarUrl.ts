import type { MaybeRefOrGetter } from 'vue'
import { ref, toValue, watch } from 'vue'
import { getCloudbaseStoragePath } from '~/utils/cloudbase-storage-url'

const SIGNED_URL_TTL_SECONDS = 60 * 60
const CACHE_TTL_MS = 50 * 60 * 1000

interface CachedAvatarUrl {
  expiresAt: number
  url: string
}

const signedUrlCache = new Map<string, CachedAvatarUrl>()
const pendingResolutions = new Map<string, Promise<string>>()

async function resolveSignedUrl(source: string, envId: string): Promise<string> {
  const path = getCloudbaseStoragePath(source, envId)
  if (!path)
    return source

  const cached = signedUrlCache.get(source)
  if (cached && cached.expiresAt > Date.now())
    return cached.url

  const pending = pendingResolutions.get(source)
  if (pending)
    return pending

  const resolution = (async () => {
    const { app } = useCloudbase()
    const result = await app.storage.from().createSignedUrl(path, SIGNED_URL_TTL_SECONDS)
    if (result.error)
      throw result.error

    const data = result.data as { fullSignedURL?: string, signedUrl?: string } | null
    const signedUrl = data?.signedUrl || data?.fullSignedURL
    if (!signedUrl)
      throw new Error('CloudBase 未返回头像签名 URL')

    signedUrlCache.set(source, {
      url: signedUrl,
      expiresAt: Date.now() + CACHE_TTL_MS,
    })
    return signedUrl
  })()

  pendingResolutions.set(source, resolution)
  try {
    return await resolution
  }
  finally {
    pendingResolutions.delete(source)
  }
}

/**
 * 将 CloudBase 私有存储的头像地址解析为短期签名 URL。
 *
 * 持久化层继续保存稳定的原始地址；签名 URL 只在内存中缓存，避免下次启动
 * 从 localStorage 读到已经过期的签名。
 */
export function useAvatarUrl(source: MaybeRefOrGetter<string | null | undefined>) {
  const config = useRuntimeConfig()
  const envId = config.public.tcbEnvId as string
  const resolvedSrc = ref<string | null>(null)
  const resolutionError = ref<Error | null>(null)
  let requestId = 0

  watch(() => toValue(source), async (nextSource) => {
    const currentRequest = ++requestId
    resolvedSrc.value = null
    resolutionError.value = null

    if (!nextSource)
      return

    try {
      const nextUrl = await resolveSignedUrl(nextSource, envId)
      if (currentRequest === requestId)
        resolvedSrc.value = nextUrl
    }
    catch (error) {
      if (currentRequest !== requestId)
        return

      resolutionError.value = error instanceof Error ? error : new Error(String(error))
      // 签名失败时仍尝试原地址；如果它也不可读，Avatar 组件会展示回退 UI。
      resolvedSrc.value = nextSource
    }
  }, { immediate: true })

  return {
    resolvedSrc,
    resolutionError,
  }
}
