import type { DesktopState, GuestCommand } from '../../shared/desktop'
import { onMounted, onUnmounted, readonly, shallowRef } from 'vue'

export function useDesktop() {
  const state = shallowRef<DesktopState>()
  const error = shallowRef('')
  const available = shallowRef(false)
  let unsubscribe: (() => void) | undefined
  let requestSequence = 0
  let eventRevision = 0
  let disposed = false
  async function request(action: () => Promise<DesktopState>): Promise<DesktopState | undefined> {
    if (disposed)
      return undefined
    const sequence = ++requestSequence
    const revision = eventRevision
    error.value = ''
    try {
      const result = await action()
      if (disposed)
        return undefined
      // A newer request or push may have arrived while the invoke was pending.
      if (sequence === requestSequence && revision === eventRevision)
        state.value = result
      return state.value
    }
    catch {
      if (!disposed && sequence === requestSequence)
        error.value = '操作暂时无法完成，请刷新应用目录后重试'
      return undefined
    }
  }
  onMounted(async () => {
    const bridge = window.desktop
    if (!bridge)
      return
    available.value = true
    unsubscribe = bridge.onState((value) => {
      if (disposed)
        return
      eventRevision++
      state.value = value
    })
    await request(bridge.getState)
  })
  onUnmounted(() => {
    disposed = true
    unsubscribe?.()
  })
  return {
    state: readonly(state),
    error: readonly(error),
    available: readonly(available),
    openApp: (appId: string) => window.desktop && request(() => window.desktop!.openApp(appId)),
    refreshCatalog: () => window.desktop && request(() => window.desktop!.refreshCatalog()),
    command: (command: GuestCommand) => window.desktop && request(() => window.desktop!.command(command)),
  }
}
