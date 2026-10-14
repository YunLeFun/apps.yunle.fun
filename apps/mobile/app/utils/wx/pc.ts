/**
 * PC OpenSDK 接入
 *
 * @see https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_PC_APIs/guideline.html
 */

const PC_OPEN_SDK_API_BASE = 'https://api.weixin.qq.com/cgi-bin/pcopensdk'

export function createPCOpenSDK() {
  /**
   * 第零步
   * 获取 access_token
   */
  // async function getAccessToken() {}

  /**
   * 第一步：
   * 获取 ticket
   */
  async function getTicket() {
    const ticketUrl = new URL(`${PC_OPEN_SDK_API_BASE}/ticket`)
    ticketUrl.searchParams.set('access_token', 'YOUR_ACCESS_TOKEN')
    const data = await fetch(ticketUrl.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ticket_type: 'pcopensdk',
      }),
    }).then(res => res.json())
    return data as {
      ticket: string
    }
  }

  /**
   * 第二步：
   * 在页面内嵌入 OpenSDK
   */
  async function embedOpenSDK() {
    const script = document.createElement('script')
    script.src = 'https://res.wx.qq.com/connect/zh_CN/htmledition/js/wxopensdk.js'
    document.body.appendChild(script)
  }

  /**
   * 第三步：调用网页 OpenSDK 接口
   */
  async function callOpenSDK(callback: () => void) {
    interface WxOpenSDK {
      ready: boolean
      onReady: (() => void) | null
    }
    const wxopensdk = (window as unknown as { wxopensdk: WxOpenSDK }).wxopensdk
    // 调用 OpenSDK 接口的示例代码
    if (wxopensdk.ready) {
      callback()
    }
    else {
      wxopensdk.onReady = callback
    }
  }

  return {
    getTicket,
    embedOpenSDK,
    callOpenSDK,
  }
}
