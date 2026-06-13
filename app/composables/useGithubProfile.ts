/**
 * useGithubProfile - 按 GitHub 登录名拉取公开资料（含中文 name）
 *
 * 开发者标识（ownerLogin）通常即 GitHub 登录名，借此自动获取：
 * - `name`：开发者展示名（很多人填的是中文名）
 * - `avatarUrl` / `bio` / `htmlUrl`
 *
 * 结果带 localStorage 7 天缓存，避免重复请求与 GitHub 匿名限流（60 次/小时/IP）。
 * 请求失败或非真实 GitHub 用户时回退 null，调用方据此回退到登录名 + 首字母头像。
 */
export interface GithubProfile {
  login: string
  name: string | null
  avatarUrl: string | null
  bio: string | null
  htmlUrl: string | null
}

const CACHE_PREFIX = 'ylf:gh-profile:'
const CACHE_TTL = 7 * 24 * 60 * 60 * 1000

interface CacheEntry {
  profile: GithubProfile | null
  ts: number
}

export function useGithubProfile(login: MaybeRefOrGetter<string>) {
  const profile = ref<GithubProfile | null>(null)
  const loading = ref(false)

  function readCache(key: string): CacheEntry | null {
    if (!import.meta.client)
      return null
    try {
      const raw = localStorage.getItem(CACHE_PREFIX + key)
      if (!raw)
        return null
      const entry = JSON.parse(raw) as CacheEntry
      if (Date.now() - entry.ts > CACHE_TTL)
        return null
      return entry
    }
    catch {
      return null
    }
  }

  function writeCache(key: string, value: GithubProfile | null) {
    if (!import.meta.client)
      return
    try {
      localStorage.setItem(CACHE_PREFIX + key, JSON.stringify({ profile: value, ts: Date.now() } satisfies CacheEntry))
    }
    catch {
      // 忽略配额 / 隐私模式
    }
  }

  async function load() {
    const key = toValue(login)
    if (!key) {
      profile.value = null
      return
    }

    // 命中缓存（含「确认无此用户」的 null 负缓存）即用，跳过网络
    const cached = readCache(key)
    if (cached) {
      profile.value = cached.profile
      return
    }

    loading.value = true
    try {
      const res = await fetch(`https://api.github.com/users/${encodeURIComponent(key)}`, {
        headers: { Accept: 'application/vnd.github+json' },
      })
      // 仅 404（确认无此用户）才负缓存；403/429/5xx 等瞬时错误（多为匿名限流）不缓存，留待下次重试
      if (res.status === 404) {
        profile.value = null
        writeCache(key, null)
        return
      }
      if (!res.ok)
        throw new Error(`github ${res.status}`)
      const data = await res.json()
      const parsed: GithubProfile = {
        login: data.login || key,
        name: data.name || null,
        avatarUrl: data.avatar_url || null,
        bio: data.bio || null,
        htmlUrl: data.html_url || null,
      }
      profile.value = parsed
      writeCache(key, parsed)
    }
    catch {
      // 瞬时失败：不缓存，回退登录名展示
      profile.value = null
    }
    finally {
      loading.value = false
    }
  }

  watch(() => toValue(login), () => load(), { immediate: true })

  return { profile, loading, load }
}
