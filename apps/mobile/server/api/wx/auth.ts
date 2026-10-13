/**
 * 微信授权代理接口
 * 通过服务端代理微信授权请求，避免在客户端暴露敏感信息
 */
export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const { code } = query

  if (!code) {
    return {
      success: false,
      msg: '缺少授权码',
      data: null,
    }
  }

  try {
    // 通过服务端请求外部 API
    const response = await $fetch<{
      success: boolean
      msg: string
      data: {
        openid: string
        nickname: string
        headimgurl: string
        unionid?: string
      }
    }>('https://api.yunle.fun/wx/auth', {
      method: 'GET',
      query: {
        code,
      },
    })

    // 如果授权成功，设置用户会话
    if (response.success && response.data) {
      await setUserSession(event, {
        user: {
          id: response.data.openid,
          login: response.data.openid,
          nickname: response.data.nickname,
          avatar: response.data.headimgurl,
          unionid: response.data.unionid,
        },
        loggedInAt: Date.now(),
      })
    }

    return response
  }
  catch (error: any) {
    console.error('微信授权失败:', error)
    return {
      success: false,
      msg: error.message || '授权失败',
      data: null,
    }
  }
})
