/**
 * JSAPI 自举登录（仅云乐坊原生容器内的第一方页面，如详情 sheet）
 *
 * 详情页被原生容器以 sheet 盖在应用之上时是独立 webview，与主 App 的 cookie /
 * localStorage 隔离、默认未登录。这里在容器内（`window.ylf` 注入）且未登录时，
 * 用 JSAPI `getAuthCode(cloudbase:session)` 换一次性授权码，向同源
 * `/api/jsapi/auth/exchange` 兑换 access_token + 用户快照写入 userStore，
 * 使 `$api` 的 `Authorization: Bearer` 生效，详情页内即可看/写评价。
 *
 * 非阻塞：不拖慢页面启动；登录态写入后由 Pinia 响应式驱动 UI。
 */
interface ExchangeResponse {
  data?: {
    user?: { id?: string, nickname?: string, avatar?: string }
    session?: { access_token?: string, refresh_token?: string }
  }
}

export default defineNuxtPlugin(() => {
  if (!import.meta.client)
    return

  const ylf = (window as unknown as { ylf?: { inYunleApp?: boolean, getAuthCode?: (o: { scope: string[] }) => Promise<{ code?: string }> } }).ylf
  if (!ylf?.inYunleApp || typeof ylf.getAuthCode !== 'function')
    return

  const userStore = useUserStore()
  if (userStore.isLoggedIn)
    return

  // fire-and-forget：后台换登录态，避免阻塞详情页首屏
  void (async () => {
    try {
      const { code } = await ylf.getAuthCode!({ scope: ['profile', 'cloudbase:session'] })
      if (!code)
        return
      const res = await $fetch<ExchangeResponse>('/api/jsapi/auth/exchange', {
        method: 'POST',
        body: { code },
      })
      const token = res?.data?.session?.access_token
      const user = res?.data?.user
      if (token && user?.nickname)
        userStore.login(token, { nickname: user.nickname, avatar: user.avatar ?? '' })
    }
    catch {
      // 自举失败：评价区按未登录处理（只读 + 写时提示登录）
    }
  })()
})
