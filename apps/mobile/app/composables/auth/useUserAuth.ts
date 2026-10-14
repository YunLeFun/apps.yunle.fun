export function useUserAuth() {
  const userStore = useUserStore()

  /**
   * 登录并保存 token 和用户信息
   */
  function login(accessToken: string, userInfo: any) {
    userStore.login(accessToken, userInfo)
  }

  /**
   * 登出
   */
  function logout() {
    userStore.logout()
  }

  return {
    isLoggedIn: userStore.isLoggedIn,
    accessToken: userStore.accessToken,
    userInfo: userStore.userInfo,
    login,
    logout,
  }
}
