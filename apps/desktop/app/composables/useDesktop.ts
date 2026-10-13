import type { DesktopState, GuestCommand } from '../../shared/desktop'

export function useDesktop() {
  const state = shallowRef<DesktopState>()
  const error = shallowRef('')
  const available = shallowRef(false)
  let unsubscribe: (() => void) | undefined
  async function request(action: () => Promise<DesktopState>) {
    error.value = ''
    try {
      state.value = await action()
    }
    catch {
      error.value = '操作暂时无法完成，请刷新应用目录后重试'
    }
  }
  onMounted(async () => {
    const bridge = window.desktop
    if (!bridge)
      return
    available.value = true
    unsubscribe = bridge.onState((value) => {
      state.value = value
    })
    await request(bridge.getState)
  })
  onUnmounted(() => unsubscribe?.())
  return {
    state: readonly(state),
    error: readonly(error),
    available: readonly(available),
    openApp: (appId: string) => window.desktop && request(() => window.desktop!.openApp(appId)),
    refreshCatalog: () => window.desktop && request(() => window.desktop!.refreshCatalog()),
    command: (command: GuestCommand) => window.desktop && request(() => window.desktop!.command(command)),
  }
}
