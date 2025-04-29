import { isInWxBrowser } from '@yunlefun/toolkit'
import { consola } from 'consola'

export function useUserLogin() {
  const router = useRouter()

  /**
   * @TODO 通过 QQ 登录
   * @see https://connect.qq.com/
   */
  function loginByQQ() {
    consola.info('通过 QQ 登录')
  }

  const wxLoginLoading = ref(false)

  /**
   * 通过微信登录
   */
  async function loginByWechat() {
    consola.info('通过微信登录')

    if (isInWxBrowser()) {
      wxLoginLoading.value = true
      // 在微信浏览器中，直接跳转到微信授权页面
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
      router.push('/wx/login')
    }
  }

  return {
    wxLoginLoading,

    loginByQQ,
    loginByWechat,
  }
}
