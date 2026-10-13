export const config = {
  apiBaseURL: 'https://api.yunle.fun',

  wx: {
    redirectUri: 'https://api.yunle.fun/wx/redirect_uri',
  },

  /**
   * App Store 配置
   * Apple App ID: https://apps.apple.com/app/id6759859441
   */
  appStore: {
    id: '6759859441',
    get url() {
      return `https://apps.apple.com/app/id${this.id}`
    },
  },

  /**
   * 法律文档在线链接
   */
  legal: {
    terms: 'https://www.yunle.fun/docs/terms-of-service',
    privacy: 'https://www.yunle.fun/docs/privacy-policy',
  },
}
