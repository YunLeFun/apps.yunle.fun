# @yunlefun/capacitor-storekit

云乐坊 iOS App Store 内购（StoreKit 2）Capacitor 插件（本地包，不发 npm）。

## 集成方式

- **JS 侧**：经 `nuxt.config.ts` 的 alias 直接引用 TS 源码（同 `@yunlefun/auth`）
- **iOS 侧**：`ios/App/Podfile` 手动挂载本地 pod（非 npm 包，`cap sync` 不会自动管理）：

  ```ruby
  pod 'YunlefunCapacitorStorekit', :path => '../../packages/capacitor-storekit'
  ```

## 设计原则

购买成功后**不在客户端 finish 交易**：JS 侧把 `transactionId` 交给服务端
（www 仓库 `functions/iap-order`）经 App Store Server API 校验入账，成功后再调
`finishTransaction`。杀进程 / 网络失败的交易保留在 `Transaction.unfinished`，
由 `getUnfinishedTransactions` / `restorePurchases` 补单，权益不会丢。

商品映射的唯一事实源在 `@yunlefun/types` 的 `iap.ts`
（`IAP_COIN_PRODUCTS` / `IAP_MEMBER_PRODUCTS`），与服务端
`functions/wxpay-order/lib/plans.js` 的 `IAP_PRODUCTS` 保持同步。

## 本地测试

Xcode 中将 `ios/App/Products.storekit` 配置到 scheme（Edit Scheme → Run →
Options → StoreKit Configuration），模拟器即可走通购买流。
