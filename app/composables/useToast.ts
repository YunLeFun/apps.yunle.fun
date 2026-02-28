import { reactive, toRefs } from 'vue'

export interface ToastState {
  opened: boolean
  message: string
  type: 'success' | 'error' | 'warning' | 'info'
}

// 全局单例状态，所有 useToast() 共享
const state = reactive<ToastState>({
  opened: false,
  message: '',
  type: 'info',
})

let closeTimer: ReturnType<typeof setTimeout> | null = null

function show(message: string, type: ToastState['type'], duration = 2000) {
  if (closeTimer) {
    clearTimeout(closeTimer)
    closeTimer = null
  }
  state.message = message
  state.type = type
  state.opened = true
  closeTimer = setTimeout(() => {
    state.opened = false
    closeTimer = null
  }, duration)
}

function close() {
  if (closeTimer) {
    clearTimeout(closeTimer)
    closeTimer = null
  }
  state.opened = false
}

export function useToast() {
  const showSuccess = (message: string) => show(message, 'success')
  const showError = (message: string) => show(message, 'error', 3000)
  const showWarning = (message: string) => show(message, 'warning')
  const showInfo = (message: string) => show(message, 'info')

  return {
    ...toRefs(state),
    showSuccess,
    showError,
    showWarning,
    showInfo,
    close,
  }
}
