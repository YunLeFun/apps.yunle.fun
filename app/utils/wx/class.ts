import { ofetch } from 'ofetch'

export const openUrl = 'https://open.weixin.qq.com'
export const wxFetch = ofetch.create({
  baseURL: 'https://api.weixin.qq.com',
})

/**
 * 微信公众号开发接口
 */
export class WxOffAccountApi {
  constructor() {

  }

  // 在服务端调用
  /**
   * 获取用户信息
   * @example
   * {
  "openid": "OPENID",
  "nickname": NICKNAME,
  "sex": 1,
  "province":"PROVINCE",
  "city":"CITY",
  "country":"COUNTRY",
  "headimgurl":"https://thirdwx.qlogo.cn/mmopen/g3MonUZtNHkdmzicIlibx6iaFqAc56vxLSUfpb6n5WKSYVY0ChQKkiaJSgQ1dZuTOgvLLrhJbERQQ4eMsv84eavHiaiceqxibJxCfHe/46",
  "privilege":[ "PRIVILEGE1" "PRIVILEGE2"     ],
  "unionid": "o6_bmasdasdsad6_2sgVt7hMZOPfL"
}
   */
  async getUserInfo() {
    const res = await wxFetch<{
      openid: string
      nickname: string
      city: string
      country: string
      headimgurl: string
      privilege: string[]
      unionid: string
    }>('/sns/userinfo', {
      method: 'GET',
      query: {
        access_token: '',
        openid: '',
        // lang: 'zh_CN',
      },
    })
    return res
  }
}
