import { toastController } from '@ionic/vue'

export interface ToastOptions {
  message: string
  duration?: number
  color?: 'primary' | 'secondary' | 'tertiary' | 'success' | 'warning' | 'danger' | 'light' | 'medium' | 'dark'
  position?: 'top' | 'bottom' | 'middle'
}

export function useToast() {
  const showToast = async (options: ToastOptions) => {
    const toast = await toastController.create({
      message: options.message,
      duration: options.duration ?? 3000,
      color: options.color ?? 'primary',
      position: options.position ?? 'top',
    })
    await toast.present()
  }

  const showSuccess = async (message: string) => {
    await showToast({ message, color: 'success' })
  }

  const showError = async (message: string) => {
    await showToast({ message, color: 'danger' })
  }

  const showWarning = async (message: string) => {
    await showToast({ message, color: 'warning' })
  }

  const showInfo = async (message: string) => {
    await showToast({ message, color: 'primary' })
  }

  return {
    showToast,
    showSuccess,
    showError,
    showWarning,
    showInfo,
  }
}
