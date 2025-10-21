import { alertController } from '@ionic/vue'

/**
 * 退出登录 Composable
 * 提供退出登录功能和确认对话框
 */
export function useLogout() {
  const router = useRouter()
  const { showSuccess, showError } = useToast()
  const isLoggingOut = ref(false)

  /**
   * 退出登录
   */
  async function logout() {
    try {
      isLoggingOut.value = true

      // 调用退出登录接口
      const response = await $fetch<{
        success: boolean
        message: string
      }>('/api/auth/logout', {
        method: 'POST',
      })

      if (response.success) {
        await showSuccess('退出登录成功')

        // 跳转到登录页
        await router.push('/login')
      }
      else {
        await showError(response.message || '退出登录失败')
      }
    }
    catch (error: unknown) {
      console.error('退出登录失败:', error)
      const message = error instanceof Error ? error.message : '退出登录失败，请重试'
      await showError(message)
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
