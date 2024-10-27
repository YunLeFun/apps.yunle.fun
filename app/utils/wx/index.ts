import { config } from '~/config'

const { wx } = config

/**
 * 尤其注意：由于授权操作安全等级较高，所以在发起授权请求时，微信会对授权链接做正则强匹配校验，如果链接的参数顺序不对，授权页面将无法正常访问
 */
export function generateUserAuthLink(options: {
  redirect_uri?: string
  scope: 'snsapi_base' | 'snsapi_userinfo'
}) {
  const { redirect_uri } = options
  return `https://open.weixin.qq.com/connect/oauth2/authorize?appid=${wx.appId}&redirect_uri=${redirect_uri}&response_type=code&scope=${options.scope}&state=STATE#wechat_redirect`
}
