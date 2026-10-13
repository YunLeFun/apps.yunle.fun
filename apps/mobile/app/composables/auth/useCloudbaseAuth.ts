/**
 * CloudBase Auth 统一入口 composable
 * 组合 Core + Otp + OAuth 模块，对外暴露扁平化 API
 */

export function useCloudbaseAuth() {
  const core = useCloudbaseAuthCore()
  const otp = useCloudbaseOtp(core)
  const oauth = useCloudbaseOAuth(core)

  return {
    // 核心状态
    user: readonly(core.user),
    loading: readonly(core.loading),
    error: readonly(core.error),
    isAuthenticated: core.isAuthenticated,

    // OTP
    ...otp,

    // OAuth
    ...oauth,

    // 通用
    logout: core.logout,
    fetchUser: core.fetchUser,
    checkAuthStatus: core.checkAuthStatus,
    ensureValidToken: core.ensureValidToken,
    refreshSession: core.refreshSession,
    clearAuth: core.clearAuth,
    updateUserInfo: core.updateUserInfo,
    getUserIdentities: core.getUserIdentities,
    resetPasswordWithOld: core.resetPasswordWithOld,
    changeEmail: core.changeEmail,
    verifyEmailBindOtp: core.verifyEmailOtp,
  }
}
