/**
 * JSAPI 自举登录（仅云乐坊原生容器内的第一方页面，如详情 sheet）
 *
 * 详情页被原生容器以 sheet 盖在应用之上时是独立 webview，与主 App 的 cookie /
 * localStorage 隔离、默认未登录。这里在容器内（`window.ylf` 注入）且未登录时，
 * 用 `@yunlefun/sso` 的原生适配器取回会话（内部走 `window.ylf` 一次性授权码 +
 * 同源 `/api/jsapi/auth/exchange` 兑换），把 access_token + 用户快照写入 userStore，
 * 使 `$api` 的 `Authorization: Bearer` 生效，详情页内即可看/写评价。
 *
 * 与各子应用共用同一套登录入口（`@yunlefun/sso`），不再各自手写 getAuthCode + exchange。
 * 非阻塞：不拖慢页面启动；登录态写入后由 Pinia 响应式驱动 UI。
 */
import { isInYunleApp, requestSsoNative } from '@yunlefun/sso'

export default defineNuxtPlugin(() => {
  if (!import.meta.client || !isInYunleApp())
    return

  const userStore = useUserStore()
  if (userStore.isLoggedIn)
    return

  // fire-and-forget：后台换登录态，避免阻塞详情页首屏
  void (async () => {
    const res = await requestSsoNative({
      scope: ['profile', 'cloudbase:session'],
      // 同源兑换：详情页与 /api 同源（apps.yunle.fun），保持相对地址即可
      exchangeUrl: '/api/jsapi/auth/exchange',
    })
    if (!res.ok)
      return
    const user = res.session.user as { nickname?: string, avatar?: string } | undefined
    if (res.session.access_token && user?.nickname)
      userStore.login(res.session.access_token, { nickname: user.nickname, avatar: user.avatar ?? '' })
  })()
})
