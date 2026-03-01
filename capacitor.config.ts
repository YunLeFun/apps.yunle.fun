import type { CapacitorConfig } from '@capacitor/cli'

const ylfApp = {
  appId: 'wx925d6e320d64f30a',
  appName: '云乐坊',
  universalLink: 'https://www.yunle.fun/app/',
}

const config: CapacitorConfig = {
  appId: 'apps.yunle.fun',
  appName: '云乐坊',
  webDir: '.output/public',

  /**
   * @see https://github.com/xu-li/cordova-plugin-wechat/issues/606
   *
   * Capacitor/Ionic + cordova-plugin-wechat
   * @see https://github.com/byteee-fund/cordova-plugin-wechat-ionic7-demo
   */
  cordova: {
    preferences: {
      WECHATAPPID: ylfApp.appId,
      UNIVERSALLINK: ylfApp.universalLink,
    },
  },
  ios: {
    cordovaLinkerFlags: ['-ObjC', '-all_load'],
  },

  plugins: {
    Keyboard: {
      // 键盘不自动调整 WebView 大小，避免布局跳动
      resize: 'none',
      // 跟随系统深色/浅色模式
      style: 'DEFAULT',
    },
  },
}

export default config
