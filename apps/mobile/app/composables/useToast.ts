import { reactive, toRefs } from 'vue'

export interface ToastState {
  opened: boolean
  message: string
  type: 'success' | 'error' | 'warning' | 'info'
  copyText: string
}

// 全局单例状态，所有 useToast() 共享
const state = reactive<ToastState>({
  opened: false,
  message: '',
  type: 'info',
  copyText: '',
})

let closeTimer: ReturnType<typeof setTimeout> | null = null

function show(message: string, type: ToastState['type'], duration = 2000, copyText = '') {
  if (closeTimer) {
    clearTimeout(closeTimer)
    closeTimer = null
  }
  state.message = message
  state.type = type
  state.copyText = copyText
  state.opened = true
  closeTimer = setTimeout(() => {
    state.opened = false
    state.copyText = ''
    closeTimer = null
  }, duration)
}

function close() {
  if (closeTimer) {
    clearTimeout(closeTimer)
    closeTimer = null
  }
  state.opened = false
  state.copyText = ''
}

export function useToast() {
  const showSuccess = (message: string) => show(message, 'success')
  const showError = (message: string, copyText = message) => show(message, 'error', 6000, copyText)
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
