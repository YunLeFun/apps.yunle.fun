/**
 * 全量引入 too large
 */
// import cloudbase from '@cloudbase/js-sdk'

/**
 * 按需引入 类型有问题
 * https://docs.cloudbase.net/api-reference/webv3/initialization#%E6%96%B9%E5%BC%8F%E4%BA%8C%E6%8C%89%E9%9C%80%E5%BC%95%E5%85%A5%E5%8A%9F%E8%83%BD%E6%A8%A1%E5%9D%97
 */
// 内核
// import cloudbase from '@cloudbase/js-sdk/app'
// 登录模块
// import { registerAuth } from '@cloudbase/js-sdk/auth'

/**
 * https://docs.cloudbase.net/api-reference/webv3/authentication#%E7%B3%BB%E7%BB%9F%E5%86%85%E7%BD%AE%E4%B8%89%E6%96%B9%E5%88%97%E8%A1%A8
 */
const providerId: 'wx_open' | 'wx_mp' = 'wx_mp'
const providerRedirectUri = 'http://localhost:8001/mobile/wx/login/confirm'
const state = 'wx_open'
const otherParams = {
  // sign_out_uri: 'test_sign_out_uri',
}

// 注册功能模块
// registerAuth(cloudbase)

/**
 * @deprecated
 * https://docs.cloudbase.net/api-reference/webv3/authentication#%E7%AC%AC%E4%B8%89%E6%96%B9%E5%B9%B3%E5%8F%B0%E7%99%BB%E5%BD%95%E7%9B%B8%E5%85%B3
 */
export function useCloudBase() {
  // const { onLoaded } = useScript('https://static.cloudbase.net/cloudbase-js-sdk/2.12.1/cloudbase.full.js')
  // onLoaded(() => {})

  // @ts-expect-error cloudbase import
  const app = cloudbase.init({
    env: 'yunlefun-2g70u1n789fdeb60',
    // clientId
  })

  const auth = app.auth({
    persistence: 'local',
  })

  /**
   * 获取第三方平台授权页地址（如微信授权）
   * 并跳转
   */
  async function goToRedirectUrl() {
    const { uri } = await auth.genProviderRedirectUri({
      provider_id: providerId,
      provider_redirect_uri: providerRedirectUri,
      redirect_uri: providerRedirectUri,
      state,
      other_params: otherParams,
    })

    if (!uri) {
      console.error('获取 uri 失败')
      return
    }

    location.href = uri
  }

  /**
   *
   * @param providerCode url 中获取
   */
  async function signIn(providerCode: string) {
    const { provider_token } = await auth.grantProviderToken({
      provider_id: providerId,
      provider_redirect_uri: providerRedirectUri,
      provider_code: providerCode,
    })

    // login
    await auth.signInWithProvider({
      provider_token,
    })
  }

  return {
    goToRedirectUrl,
    signIn,
  }
}
