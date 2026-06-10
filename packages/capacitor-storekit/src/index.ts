import type { StorekitPlugin } from './definitions'
import { registerPlugin } from '@capacitor/core'

/**
 * StoreKit 2 内购插件（仅 iOS 原生实现；Web 环境调用会抛
 * "not implemented"，调用方必须先用支付通道判定守卫）。
 */
export const Storekit = registerPlugin<StorekitPlugin>('Storekit')

export type { IapProduct, IapTransaction, StorekitPlugin } from './definitions'
