import { config } from '../../config'

/**
 * 尤其注意：由于授权操作安全等级较高，所以在发起授权请求时，微信会对授权链接做正则强匹配校验，如果链接的参数顺序不对，授权页面将无法正常访问
 * @see https://developers.weixin.qq.com/doc/offiaccount/OA_Web_Apps/Wechat_webpage_authorization.html#%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97
 * #wechat_redirect 无论直接打开还是做页面302重定向时候，必须带此参数
 * https://open.weixin.qq.com/connect/oauth2/authorize?appid=wx807d86fb6b3d4fd2&redirect_uri=http%3A%2F%2Fdevelopers.weixin.qq.com&response_type=code&scope=snsapi_userinfo&state=STATE#wechat_redirect
 * - 重定向后会带上state参数，开发者可以填写a-zA-Z0-9的参数值，最多128字节
 */
export function generateUserAuthLink(options: {
  appid?: string

  redirect_uri?: string
  scope?: 'snsapi_base' | 'snsapi_userinfo'
}) {
  const { redirect_uri = config.wx.redirectUri, scope = 'snsapi_base' } = options
  // 开发者可以填写 a-zA-Z0-9 的参数值，最多128字节
  const state = 'LOGIN'

  // 返回的是会带 code 和 state 参数的链接，所以需要删除掉重定向的 code 和 state 参数
  const redirectUrl = new URL(redirect_uri)
  redirectUrl.searchParams.delete('code')
  redirectUrl.searchParams.delete('state')

  const url = new URL('https://open.weixin.qq.com/connect/oauth2/authorize')
  url.searchParams.set('appid', options.appid || '')
  url.searchParams.set('redirect_uri', redirectUrl.toString())
  url.searchParams.set('response_type', 'code')
  url.searchParams.set('scope', scope)
  url.searchParams.set('state', state)
  url.hash = 'wechat_redirect'
  return url.toString()
}
