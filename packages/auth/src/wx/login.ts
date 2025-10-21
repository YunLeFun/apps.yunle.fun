/**
 * 网站应用微信登录
 * @see https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Wechat_Login.html
 */
export function createWxLogin(options: {
  /**
   * 应用唯一标识
   */
  appid: string
  /**
   * 请使用urlEncode对链接进行处理
   */
  redirectUri: string
  /**
   * 用于保持请求和回调的状态，授权请求后原样带回给第三方。该参数可用于防止csrf攻击（跨站请求伪造攻击），建议第三方带上该参数，可设置为简单的随机数加session进行校验
   */
  state?: string
  /**
   * 界面语言，支持cn（中文简体）与en（英文），默认为cn
   * @default 'cn'
   */
  lang?: 'cn' | 'en'
}) {
  /**
   * 第一步：请求CODE
   *
   * 生成微信授权链接
   */
  function getQrconnectUrl() {
    const url = new URL('https://open.weixin.qq.com/connect/qrconnect')
    url.searchParams.set('appid', options.appid)
    url.searchParams.set('redirect_uri', options.redirectUri)
    url.searchParams.set('response_type', 'code')
    /**
     * 应用授权作用域，拥有多个作用域用逗号（,）分隔，网页应用目前仅填写snsapi_login
     */
    url.searchParams.set('scope', 'snsapi_login')

    if (options.state) {
      url.searchParams.set('state', options.state)
    }
    if (options.lang) {
      url.searchParams.set('lang', options.lang)
    }
    url.hash = 'wechat_redirect'
    return url.toString()
  }

  return {
    getQrconnectUrl,
  }
}

export interface WxOauth2AccessTokenResponse {
  /**
   * 接口调用凭证
   */
  access_token: string
  /**
   * access_token接口调用凭证超时时间，单位（秒）
   */
  expires_in: number
  /**
   * 用户刷新access_token
   */
  refresh_token: string
  /**
   * 授权用户唯一标识
   */
  openid: string
  /**
   * 用户授权的作用域，使用逗号（,）分隔
   */
  scope: string
  /**
   * 当且仅当该网站应用已获得该用户的userinfo授权时，才会出现该字段。
   */
  unionid?: string
}

/**
 * 第二步：通过code获取access_token
 *
 * @example
 * ```json
 * {
 *   "access_token":"ACCESS_TOKEN",
 *   "expires_in":7200,
 *   "refresh_token":"REFRESH_TOKEN",
 *   "openid":"OPENID",
 *   "scope":"SCOPE",
 *   "unionid": "o6_bmasdasdsad6_2sgVt7hMZOPfL"
 * }
 * ```
 */
export async function getAccessToken(options: {
  /**
   * 应用唯一标识，在微信开放平台提交应用审核通过后获得
   */
  appid: string
  /**
   * 应用密钥AppSecret，在微信开放平台提交应用审核通过后获得
   */
  secret: string
  /**
   * 填写第一步获取的code参数
   */
  code: string
}) {
  const url = new URL('https://api.weixin.qq.com/sns/oauth2/access_token')
  url.searchParams.set('appid', options.appid)
  url.searchParams.set('secret', options.secret)
  url.searchParams.set('code', options.code)
  url.searchParams.set('grant_type', 'authorization_code')

  // const res = await fetch(url.toString())
}

export interface WxLoginOptions {
  /**
   * true：手机点击确认登录后可以在 iframe 内跳转到 redirect_uri，false：手机点击确认登录后可以在 top window 跳转到 redirect_uri。默认为 false。
   */
  self_redirect?: boolean
  /**
   * 第三方页面显示二维码的容器id
   */
  id: string
  /**
   * 应用唯一标识，在微信开放平台提交应用审核通过后获得
   */
  appid: string
  /**
   * 应用授权作用域，拥有多个作用域用逗号（,）分隔，网页应用目前仅填写snsapi_login即可
   *
   * @default snsapi_login
   */
  scope?: string
  /**
   * 重定向地址，需要进行UrlEncode
   */
  redirect_uri: string
  /**
   * 用于保持请求和回调的状态，授权请求后原样带回给第三方。该参数可用于防止csrf攻击（跨站请求伪造攻击），建议第三方带上该参数，可设置为简单的随机数加session进行校验
   */
  state?: string
  /**
   * 提供"black"、"white"可选，默认为黑色文字描述。详见文档底部FAQ
   */
  style?: 'black' | 'white'
  /**
   * 自定义样式链接，第三方可根据实际需求覆盖默认样式，stylelite不为1时有效。详见文档底部FAQ
   */
  href?: string
  /**
   * 切换二维码登录样式，值为1时二维码登录将切换到新样式。详见文档底部FAQ。
   */
  stylelite?: 1
  /**
   * 启用或禁用快速登录功能，值为0时将禁用快速登录，如发现参数不生效可检查redirect_uri是否已经正确encode。
   */
  fast_login?: 0
  /**
   * 支持切换light或dark主题，值为"light"表示仅支持light主题，值为"dark"时表示仅支持dark主题，值为"auto"时表示跟随系统主题，不使用该参数将保持浏览器默认主题。
   */
  color_scheme?: 'light' | 'dark' | 'auto'
  /**
   * iframe页面是否加载成功的回调，isReady为true表示加载成功
   */
  onReady?: (isReady: boolean) => void
  /**
   * 二维码加载完成的回调
   */
  onQRcodeReady?: () => void
}

/**
 * 第二种方式
 *
 * 将微信登录二维码内嵌到自己页面
 */
// http://res.wx.qq.com/connect/zh_CN/htmledition/js/wxLogin.js
export function createEmbeddedWxLogin() {
  /**
   * 步骤1：在页面中先引入如下JS文件（支持https）
   */
  async function importWxLoginScript(options: {
    protocol?: 'http' | 'https'
  } = {
    protocol: 'http',
  }) {
    const wxLoginSrc = `${options.protocol || 'http'}://res.wx.qq.com/connect/zh_CN/htmledition/js/wxLogin.js`
    const script = document.createElement('script')
    script.src = wxLoginSrc
    document.head.appendChild(script)

    return new Promise((resolve, reject) => {
      script.onload = () => {
        resolve(true)
      }
      script.onerror = () => {
        reject(new Error('Failed to load wxLogin script'))
      }
    })
  }

  /**
   * 步骤2：在需要使用微信登录的地方实例以下JS对象
   */
  function newWxLogin(options: WxLoginOptions = {
    id: 'wx_login_container',
    appid: '',
    scope: 'snsapi_login',
    redirect_uri: '',
  }) {
    const WxLogin = (window as unknown as {
      // constructor
      WxLogin: new (options: WxLoginOptions) => void
    }).WxLogin
    const obj = new WxLogin({
      self_redirect: true,
      state: '',
      onReady: (isReady) => {
        // eslint-disable-next-line no-console
        console.log('isReady', isReady)
      },
      ...options,
      scope: 'snsapi_login',
    })
    return obj
  }

  /**
   * init
   *
   * @example
   *
   * ```ts
   * init({
   *   id: 'wx_login_container',
   *   appid: '',
   *
   * })
   * ```
   */
  async function init(options: WxLoginOptions) {
    await importWxLoginScript()
    newWxLogin(options)
  }

  return {
    importWxLoginScript,
    init,
  }
}
