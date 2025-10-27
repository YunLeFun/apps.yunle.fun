import type { CapacitorConfig } from '@capacitor/cli'

const wxOpenAppId = {
  ylf: 'wx925d6e320d64f30a',
}

const config: CapacitorConfig = {
  appId: 'apps.yunle.fun',
  appName: '云乐坊',
  webDir: 'dist',

  /**
   * @see https://github.com/xu-li/cordova-plugin-wechat/issues/606
   */
  // cordova: {
  //   preferences: {
  //     WECHATAPPID: 'wx925d6e320d64f30a',
  //   },
  // },

  /**
   * @see https://github.com/TomPengCN/capacitor-ionic-plugin-wechat
   */
  plugins: {
    WechatSDK: {
      // mchid: '1234567890', // 商户id, 如无微信支付功能可忽略此参数
      wechatAppId: wxOpenAppId.ylf, // 微信应用id: 从微信开放平台官方网站申请到的合法AppId
      wechatUniversalLink: 'https://www.yunle.fun/ulink/', // UniversalLink 仅针对于iOS
    },
  },
}

export default config
