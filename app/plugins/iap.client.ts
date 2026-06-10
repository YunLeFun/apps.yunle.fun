/**
 * IAP 交易更新监听（仅 iOS 原生壳）。
 *
 * 处理购买弹窗之外到账的交易：待批准（家长同意）完成、客服补单、
 * 其他设备购买等 —— 收到 transactionUpdated 后统一走补单链路
 * （服务端校验入账 → finish → 刷新余额）。
 */
import { Capacitor } from '@capacitor/core'
import { Storekit } from '@yunlefun/capacitor-storekit'
import consola from 'consola'

export default defineNuxtPlugin(() => {
  if (!Capacitor.isNativePlatform() || Capacitor.getPlatform() !== 'ios')
    return

  const { processUnfinished } = useIap()

  Storekit.addListener('transactionUpdated', async (tx) => {
    consola.info('[iap] 收到交易更新:', tx.transactionId, tx.productId)
    const settled = await processUnfinished()
    if (settled > 0)
      showIonicToast('购买已到账')
  }).catch((err) => {
    consola.warn('[iap] 注册交易监听失败:', err)
  })
})
