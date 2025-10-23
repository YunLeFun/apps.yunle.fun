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
    }
  }

  // 返回用户信息
  return {
    // nickname: session.user.nickname || '无名氏',
    // headimgurl: session.user.avatar || '',
    // openid: session.user.id,
  }
})
