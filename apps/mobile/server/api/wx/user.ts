/**
 * @api {get} /wx/user 获取当前登录用户信息
 */
export default defineEventHandler(async (event) => {
  // 获取用户会话
  const session = await getUserSession(event)

  // 如果未登录，返回空数据
  if (!session.user) {
    return {
      nickname: '',
      headimgurl: '',
      openid: '',
      sex: 0,
      province: '',
      city: '',
      country: '',
      privilege: [],
      unionid: '',
    }
  }

  // 尝试从外部 API 获取完整用户信息
  try {
    const response = await $fetch<{
      success: boolean
      msg: string
      data: {
        openid: string
        nickname: string
        sex: 1 | 2 | 0
        province: string
        city: string
        country: string
        headimgurl: string
        privilege: string[]
        unionid?: string
      }
    }>('https://api.yunle.fun/wx/userinfo', {
      method: 'GET',
      query: {
        // openid: session.user.id,
      },
    })

    if (response.success && response.data) {
      return response.data
    }
  }
  catch (error) {
    console.error('获取用户详细信息失败:', error)
  }

  // 如果外部 API 失败，返回会话中的基本信息
  return {
    // nickname: session.user.nickname || '无名氏',
    // headimgurl: session.user.avatar || '',
    // openid: session.user.id || '',
    // sex: 0 as const,
    // province: '',
    // city: '',
    // country: '',
    // privilege: [],
    // unionid: session.user.unionid || '',
  }
})
