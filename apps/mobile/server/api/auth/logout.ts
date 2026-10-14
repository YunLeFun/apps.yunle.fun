/**
 * 退出登录接口
 * 清除用户会话
 */
export default defineEventHandler(async (event) => {
  try {
    // 清除用户会话
    await clearUserSession(event)

    return {
      success: true,
      message: '退出登录成功',
    }
  }
  catch (error: any) {
    console.error('退出登录失败:', error)
    return {
      success: false,
      message: error.message || '退出登录失败',
    }
  }
})
