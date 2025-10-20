/**
 * @param message
 * @param color
 */
export async function showIonicToast(message: string, color: 'success' | 'danger' = 'success') {
  const toast = await toastController.create({
    message,
    duration: 3000,
    position: 'top',
    color,
    buttons: [
      {
        text: '关闭',
        role: 'cancel',
      },
    ],
  })
  await toast.present()
}
