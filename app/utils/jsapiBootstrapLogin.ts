import { requestSsoNative } from '@yunlefun/sso'

/** userStore 的最小契约：判断登录态 + 写入登录态（供 $api 的 Authorization: Bearer） */
export interface JsapiLoginTarget {
  isLoggedIn: boolean
  login: (token: string, user: { nickname: string, avatar: string }) => void
}

/**
 * 云乐坊原生容器内详情页的自举登录：经 `@yunlefun/sso` 取回会话
 * （`window.ylf` 一次性授权码 + 同源 `/api/jsapi/auth/exchange` 兑换），
 * 把 access_token + 用户快照写入 userStore，使 `$api` 的 Bearer 生效。
 *
 * 抽成纯函数（只依赖传入的 userStore）便于单测；与 `jsapi-auth.client.ts` 共用。
 *
 * @returns 是否完成了一次登录写入
 */
export async function bootstrapJsapiLogin(userStore: JsapiLoginTarget): Promise<boolean> {
  if (userStore.isLoggedIn)
    return false

  const res = await requestSsoNative({
    scope: ['profile', 'cloudbase:session'],
    // 同源兑换：详情页与 /api 同源（apps.yunle.fun），保持相对地址即可
    exchangeUrl: '/api/jsapi/auth/exchange',
  })
  if (!res.ok)
    return false

  const user = res.session.user as { nickname?: string, avatar?: string } | undefined
  if (!res.session.access_token || !user?.nickname)
    return false

  userStore.login(res.session.access_token, { nickname: user.nickname, avatar: user.avatar ?? '' })
  return true
}
