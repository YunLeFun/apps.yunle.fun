import type { WxUserInfo } from './types'

export interface YlfWxAuthResponse {
  access_token: string
  user: {
    id: string
    nickname: string
    avatar: string
    profile: WxUserInfo
  }
}

export const YLF_API_BASE_URL = 'https://api.yunle.fun'

/**
 * 验证 code
 */
export function createYlfVerifyWxCode() {
  async function verifyCode(params: {
    code: string
    state: string
  }) {
    const { code, state } = params
    const url = new URL(`${YLF_API_BASE_URL}/auth/wechat/callback`)
    url.searchParams.set('code', code)
    url.searchParams.set('state', state)

    const res = await fetch(url.toString(), {
      method: 'GET',
    }).then(res => res.json())
    return res
  }

  return {
    verifyCode,
  }
}
