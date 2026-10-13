import { alertController } from '@ionic/vue'
import consola from 'consola'

/**
 * 开发者模式业务逻辑
 * - 连续点击 5 次激活
 * - 5 秒超时重置计数
 * - 确认退出对话框
 */
export function useDeveloperMode() {
  const developerStore = useDeveloperStore()
  const { showSuccess, showInfo } = useToast()
  const router = useRouter()

  const clickCount = ref(0)
  const REQUIRED_CLICKS = 5
  const TIMEOUT_MS = 5000

  let resetTimer: ReturnType<typeof setTimeout> | null = null

  function resetClickCount() {
    clickCount.value = 0
    if (resetTimer) {
      clearTimeout(resetTimer)
      resetTimer = null
    }
  }

  function handleLogoClick() {
    if (developerStore.enabled) {
      showInfo('开发者模式已开启')
      return
    }

    clickCount.value++

    // 重置计时器
    if (resetTimer) {
      clearTimeout(resetTimer)
    }
    resetTimer = setTimeout(resetClickCount, TIMEOUT_MS)

    const remaining = REQUIRED_CLICKS - clickCount.value
    if (remaining > 0 && remaining <= 2) {
      showInfo(`再点击 ${remaining} 次进入开发者模式`)
    }

    if (clickCount.value >= REQUIRED_CLICKS) {
      developerStore.enableDevMode()
      resetClickCount()
      showSuccess('已进入开发者模式')
      consola.info('[Developer] 开发者模式已激活')
    }
  }

  async function confirmExitDevMode() {
    const alert = await alertController.create({
      header: '退出开发者模式',
      message: '退出后将恢复默认设置，确定要退出吗？',
      buttons: [
        {
          text: '取消',
          role: 'cancel',
        },
        {
          text: '确定',
          role: 'confirm',
          handler: () => {
            developerStore.disableDevMode()
            showSuccess('已退出开发者模式')
            consola.info('[Developer] 开发者模式已退出')
            router.replace('/tabs/me')
          },
        },
      ],
    })

    await alert.present()
  }

  return {
    clickCount,
    handleLogoClick,
    confirmExitDevMode,
  }
}
