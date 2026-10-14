import consola from 'consola'
import QRCode from 'qrcode'

/**
 * 二维码状态
 */
export type QrcodeStatus = 'normal' | 'success' | 'expired' | 'error'

/**
 * Wx Qrcode Login
 *
 * 加载并检查二维码 - loadAndCheckQrcode
 * 1. 获取登录凭证（ticket） - getLoginTicket
 * 2. 生成登录二维码（带有 ticket） - generateLoginQrcode (getLoginTicket)
 * 3. 轮询检查登录结果 - checkLoginResult
 */
export function useWxLogin(options: {
  onSuccess?: () => void
  onError?: () => void
}) {
  const qrcodeStatus = ref<QrcodeStatus>()
  const checkLoginInterval = ref<ReturnType<typeof setTimeout>>()
  const { showError } = useToast()

  /**
   * 登录凭证
   * 对应此次登录行为
   */
  const ticket = ref('')

  const { $api } = useNuxtApp()

  /**
   * 获取登录凭证
   */
  async function getLoginTicket() {
    const res = await $api<{
      code: number
      data: {
        /**
         * 二维码 登录凭证，与单次登录行为进行对应
         */
        ticket: string
      }
    }>('/wx/auth/login/ticket', {
      method: 'POST',
    })

    if (res.data?.ticket) {
      ticket.value = res.data.ticket
    }
    else {
      consola.error('获取登录凭证失败', res)
      await showError('获取登录凭证失败')
    }
  }

  /**
   * 检查登录结果
   * 轮询
   */
  async function checkLoginResult() {
    const res = await $api<{
      code: number
      data: {
        ticket: string
      }
    }>('/wx/auth/login/check', {
      method: 'POST',
    })
    if (!res) {
      return
    }

    switch (res.code) {
      case 0:
        // 成功
        qrcodeStatus.value = 'success'
        options.onSuccess?.()
        break
      case 1:
        // 手机端未确认，继续轮询
        return
      case 2:
        // 失败
        qrcodeStatus.value = 'error'
        options.onError?.()
        break
      // 过期
      case -1:
      default:
        // 其他情况
        qrcodeStatus.value = 'expired'
        break
    }
    clearInterval(checkLoginInterval.value)
  }

  /**
   * 加载并检查二维码
   */
  async function loadAndCheckQrcode() {
    qrcodeStatus.value = 'normal'
    clearInterval(checkLoginInterval.value)
    await getLoginTicket()
    await generateLoginQrcode()
    checkLoginInterval.value = setInterval(checkLoginResult, 1000)
  }

  const wxLoginConfirmQrcode = ref('')
  /**
   * 生成登录二维码
   */
  async function generateLoginQrcode() {
    const url = new URL(`${window.location.origin}/mobile/wx/login/confirm`)
    url.searchParams.set('ticket', ticket.value)
    consola.debug('生成登录二维码', url.toString())

    // 移动端微信登录确认页面
    wxLoginConfirmQrcode.value = await QRCode.toDataURL(url.toString(), {
      width: 250,
      margin: 3,
    })
  }

  onBeforeUnmount(() => {
    // 清除轮询
    clearInterval(checkLoginInterval.value)
  })

  return {
    ticket,
    qrcodeStatus,
    checkLoginInterval,
    wxLoginConfirmQrcode,

    generateLoginQrcode,
    getLoginTicket,
    checkLoginResult,
    loadAndCheckQrcode,
  }
}
