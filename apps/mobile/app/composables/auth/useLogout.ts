import { alertController } from '@ionic/vue'

/**
 * 退出登录 Composable
 * 提供退出登录功能和确认对话框
 */
export function useLogout() {
  const { logout: logoutCloudbase } = useCloudbaseAuth()
  const isLoggingOut = ref(false)

  /**
   * 退出登录
   */
  async function logout() {
    try {
      isLoggingOut.value = true

      // Nuxt session 仅用于兼容微信网页登录；清理失败不能阻断
      // CloudBase SDK、本地 token 与用户状态的退出。
      try {
        const response = await $fetch<{
          success: boolean
          message: string
        }>('/api/auth/logout', {
          method: 'POST',
        })
        if (!response.success)
          console.warn('服务端会话清理失败:', response.message)
      }
      catch (error: unknown) {
        console.warn('服务端会话清理失败:', error)
      }

      await logoutCloudbase()
    }
    finally {
      isLoggingOut.value = false
    }
  }

  /**
   * 显示退出登录确认对话框
   */
  async function confirmLogout() {
    const alert = await alertController.create({
      header: '退出登录',
      message: '确定要退出登录吗？',
      buttons: [
        {
          text: '取消',
          role: 'cancel',
        },
        {
          text: '确定',
          role: 'confirm',
          handler: () => {
            logout()
          },
        },
      ],
    })

    await alert.present()
  }

  return {
    logout,
    confirmLogout,
    isLoggingOut,
  }
}
