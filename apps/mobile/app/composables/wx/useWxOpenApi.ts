/**
 * 将微信登录二维码内嵌到自己页面
 *
 * https://open.weixin.qq.com/
 * 需要资质认证 暂时不加
 * @see https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Wechat_Login.html
 */
export function useWxOpenApi(options: {
  appid: string
  redirect_uri: string
}) {
  const { appid, redirect_uri } = options
  useScriptTag('https://res.wx.qq.com/connect/zh_CN/htmledition/js/wxLogin.js', () => {
  // @ts-expect-error wxLogin
    const _obj = new window.WxLogin({
      self_redirect: true,
      id: 'login_container',
      appid,
      scope: 'snsapi_login',
      redirect_uri,
      state: '',
      style: '',
      href: '',
      // 切换二维码登录样式，值为1时二维码登录将切换到新样式。详见文档底部FAQ。
      stylelite: 1,
    // 启用或禁用快速登录功能，值为0时将禁用快速登录，如发现参数不生效可检查redirect_uri是否已经正确encode。
    // fast_login:
    })
    return _obj
  })
}
