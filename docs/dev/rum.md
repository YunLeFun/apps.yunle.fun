# 错误监控 / 前端性能监控（Tencent RUM）

> **结论**：用 [腾讯云 RUM（Real User Monitoring）](https://cloud.tencent.com/product/rum)，免费档 100k 上报/月，与本项目 CloudBase 同生态、同账号、同结算，是 Sentry 在国内最直接的替代。

## 选型对比

| 方案                             | 费用         | 国内访问             | 与 CloudBase 同账号 | 推荐度          |
| -------------------------------- | ------------ | -------------------- | ------------------- | --------------- |
| **腾讯云 RUM**                   | 免费 100k/月 | ✅ 上海 / 广州接入点 | ✅                  | ⭐⭐⭐⭐⭐ 首选 |
| 阿里 ARMS                        | 免费 60w/月  | ✅                   | ❌                  | ⭐⭐⭐⭐        |
| Sentry SaaS                      | 免费 5k/月   | ❌（国内偶尔抽风）   | ❌                  | ⭐⭐⭐          |
| Sentry 自部署                    | 服务器成本   | ✅                   | ❌                  | ⭐⭐            |
| 火眼 Aegis（腾讯，原小程序监控） | 已合并到 RUM | —                    | —                   | 不再单独推荐    |

## 获取 AppID

1. 打开 <https://console.cloud.tencent.com/rum>（用本项目 CloudBase 同账号）
2. 左上「项目管理」→ 右上「新建项目」
3. 填写：

   | 字段               | 值                                                                                             |
   | ------------------ | ---------------------------------------------------------------------------------------------- |
   | 项目名             | `yunle.fun`                                                                                    |
   | 项目类型           | **Web**                                                                                        |
   | 上报域名（白名单） | `yunle.fun`、`www.yunle.fun`、`dev.yunle.fun`、`fun.yunle.apps`（Capacitor 内 webview origin） |
   | 资源域名           | 留空（自动追踪）                                                                               |
   | 项目代号           | 自定义，用作 alias                                                                             |

4. 创建后在「项目详情」页面拿到 **AppID**（一串数字，例如 `L00000ABCD`）

## 接入步骤（代码端）

> 注：当前代码库已经预留 [`app/plugins/rum.client.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/plugins/rum.client.ts)，只需要补 AppID 即可启用。

### 1. 安装 SDK

```bash
pnpm add rum-mp-vue  # 等价于 Sentry browser SDK
```

> 或者 `pnpm add aegis-web-sdk` —— 腾讯历史名称，与 RUM 同一套，二选一。本项目推荐 `rum-mp-vue` 因为它原生支持 Vue 3 + Capture Pinia state。

### 2. 在 `nuxt.config.ts` `runtimeConfig.public` 加配置

> 已在仓库内完成，参考即可：

```ts
export default defineNuxtConfig({
  runtimeConfig: {
    public: {
      // 腾讯云 RUM AppID（留空则不上报）
      rumAppId: '',
      // 本地调试时改 true 可看到上报日志
      rumDebug: false,
    },
  },
})
```

### 3. 启用 plugin

打开 [`app/plugins/rum.client.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/plugins/rum.client.ts)，把 AppID 填到 `.env.production` 或直接环境变量：

```bash
# .env.production
NUXT_PUBLIC_RUM_APP_ID=L00000ABCD
```

plugin 检测到 `rumAppId` 非空就会自动启动上报。

## 上报内容（默认配置）

- ✅ JS 未捕获异常（含 unhandledrejection）
- ✅ 资源加载失败（4xx/5xx）
- ✅ 长任务（> 50ms）
- ✅ Web Vitals（LCP、FID、CLS、INP）
- ✅ PV / UV
- ✅ 用户操作链路（click → request → error）
- ⬜ 自定义业务埋点（登录失败、CloudBase 调用失败）—— 需要在业务代码中手动调 `rum.captureException()` 或 `rum.captureMessage()`

## 关键业务埋点建议

发版前至少补这几处（卡在登录是最高频流失点）：

| 位置                                                                                                                                             | 上报事件                 |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------ |
| [`composables/auth/useCloudbaseOtp.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/auth/useCloudbaseOtp.ts) 错误分支  | `auth.otp.failed`        |
| [`composables/auth/useCloudbaseOAuth.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/auth/useCloudbaseOAuth.ts) catch | `auth.oauth.failed`      |
| [`plugins/api.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/plugins/api.ts) 401 刷新失败分支                                    | `auth.refresh.failed`    |
| [`composables/useApps.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/useApps.ts) createApp / updateApp catch         | `cloudbase.write.failed` |
| Capacitor 扫码失败                                                                                                                               | `scan.failed`            |

## 验证清单

接入后：

1. 浏览器 DevTools Network 看到对 `aegis.qq.com` 的 POST 上报
2. 故意 `throw new Error('rum test')` 触发一次异常
3. 控制台 RUM 项目页 → 5 分钟内能看到上报记录

## iOS Capacitor 内的特殊处理

Capacitor WebView origin 是 `capacitor://localhost`（iOS）/`https://localhost`（部分版本），不在 RUM 白名单内会被拒。两种解决：

1. **推荐**：RUM 项目配置中关闭"严格 origin 校验"，或在白名单加 `capacitor://localhost`
2. 设置 `serverUrl: 'https://aegis.qq.com/...'` 强制走自定义上报地址

详见腾讯文档：<https://cloud.tencent.com/document/product/1464/63138>

## 后续

接入后下一步可考虑：

- 自定义性能埋点（自定义 timing）
- 错误聚合 + 告警接入企业微信
- Source Map 上传（让 stack trace 反编译）—— 已在 Nitro 构建产出 `.map` 文件，配合 RUM 上传工具即可
