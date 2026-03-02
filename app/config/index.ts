export const config = {
  apiBaseURL: 'https://api.yunle.fun',

  wx: {
    redirectUri: 'https://api.yunle.fun/wx/redirect_uri',
  },

  /**
   * App Store 配置
   * 上架后将 id 替换为真实 App ID
   */
  appStore: {
    id: '000000000',
    get url() {
      return `https://apps.apple.com/app/yunlefun/id${this.id}`
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
