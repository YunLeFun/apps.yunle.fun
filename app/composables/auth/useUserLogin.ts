import { createEmbeddedWxLogin } from '@yunlefun/auth'
import { isInWxBrowser } from '@yunlefun/toolkit'
import { consola } from 'consola'

export function useUserLogin() {
  const wxLoginLoading = ref(false)

  /**
   * 通过微信登录
   */
  async function loginByWechat() {
    consola.info('通过微信登录')

    if (isInWxBrowser()) {
      wxLoginLoading.value = true
      // 在微信浏览器中，直接跳转到微信授权页面
      // 授权成功后会重定向回来，在 login.vue 中处理成功后跳转到用户信息页面
      window.location.href = generateUserAuthLink({
        scope: 'snsapi_userinfo',
        redirect_uri: window.location.href,
      })
    }
    else {
      // 在非微信浏览器中，调用微信扫码登录
      // 1. 获取二维码
      // 2. 轮询扫码状态
      // 3. 获取用户信息

      // 进入微信扫码登录页面
      // router.push('/wx/login')

      const { init } = createEmbeddedWxLogin()
      init({
        id: 'wx_login_container',
        // appid: '',
        /**
         * https://open.weixin.qq.com/
         * me@yunyoujun.cn
         */
        appid: import.meta.env.NUXT_WX_OPEN_APP_ID,
        redirect_uri: 'https://www.yunle.fun',
        /**
         * 新样式
         */
        stylelite: 1,
        color_scheme: 'auto',
      })
      consola.info('初始化内嵌微信登录')
    }
  }

  return {
    wxLoginLoading,
    loginByWechat,
  }
}
