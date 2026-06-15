/**
 * JSAPI 自举登录（仅云乐坊原生容器内的第一方页面，如详情 sheet）
 *
 * 详情页被原生容器以 sheet 盖在应用之上时是独立 webview，与主 App 的 cookie /
 * localStorage 隔离、默认未登录。这里在容器内（`window.ylf` 注入）且未登录时，
 * 用 `@yunlefun/sso` 取回会话并写入 userStore，使 `$api` 的 `Authorization: Bearer` 生效。
 *
 * 与各子应用共用同一套登录入口（`@yunlefun/sso`）；登录逻辑抽到
 * `~/utils/jsapiBootstrapLogin` 便于单测。非阻塞：不拖慢详情页首屏。
 */
import { isInYunleApp } from '@yunlefun/sso'
import { bootstrapJsapiLogin } from '~/utils/jsapiBootstrapLogin'

export default defineNuxtPlugin(() => {
  if (!import.meta.client || !isInYunleApp())
    return

  // fire-and-forget：后台换登录态，避免阻塞首屏
  void bootstrapJsapiLogin(useUserStore())
})
