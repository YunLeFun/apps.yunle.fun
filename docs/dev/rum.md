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

## 接入状态（已完成）

✅ 当前接入 SDK：`aegis-web-sdk@latest`（腾讯官方 Web 端 SDK）
✅ 默认 AppID 已写入 `nuxt.config.ts`：`nG8jRFK2e30nRrle5R`（线上 `yunle.fun` 项目）
✅ Plugin 已启用：[`app/plugins/rum.client.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/plugins/rum.client.ts)
✅ 自动绑定 `uin`：用户登录后自动用 `userStore.userInfo.id` 标记，便于按用户聚合错误

## 如果要切换 AppID（多环境）

通过环境变量覆盖默认值：

```bash
# .env.production —— 生产环境
NUXT_PUBLIC_RUM_APP_ID=nG8jRFK2e30nRrle5R

# .env.staging —— 灰度环境（建议新建独立项目避免污染线上数据）
NUXT_PUBLIC_RUM_APP_ID=<staging-app-id>

# 关闭上报
NUXT_PUBLIC_RUM_APP_ID=
```

## 本地开发

本地开发（`nuxt dev`）默认**不初始化、不上报**，避免消耗免费额度、污染线上数据。

需要在本地联调 RUM 本身时，可强制开启（同时会打印调试日志）：

```bash
NUXT_PUBLIC_RUM_DEBUG=true
```

## SDK 选型说明

| SDK                 | 状态        | 备注                                 |
| ------------------- | ----------- | ------------------------------------ |
| **`aegis-web-sdk`** | ✅ 当前使用 | 腾讯官方 Web SDK，最稳定，文档最全   |
| `rum-mp-vue`        | ⚪ 备选     | Vue 3 友好但社区更小，未来可考虑迁移 |
| `aegis-mp-sdk`      | ❌ 不适用   | 小程序专用                           |

## 上报内容（默认配置）

- ✅ JS 未捕获异常（含 unhandledrejection）
- ✅ 资源加载失败（4xx/5xx）
- ✅ 长任务（> 50ms）
- ✅ Web Vitals（LCP、FID、CLS、INP）
- ✅ PV / UV
- ✅ 用户操作链路（click → request → error）
- ✅ 用户头像加载失败（`ui.avatar.load_failed`）
- ⬜ 其他自定义业务埋点（登录失败、CloudBase 调用失败）

自定义客户端事件统一通过 `reportClientEvent()` 上报。它会同时写入 WebView
控制台与 RUM，并固定使用以下筛选维度：

| 字段   | 内容                                       |
| ------ | ------------------------------------------ |
| `ext1` | 页面或组件，例如 `tabs.me`、`user.profile` |
| `ext2` | 失败阶段，例如 `sign`、`load`              |
| `ext3` | 资源域名                                   |

完整资源路径、查询参数和临时签名不会上报，避免泄露用户标识与访问凭证。

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

Capacitor WebView origin 是 `capacitor://localhost`（iOS）/`https://localhost`（部分版本）。RUM 的页面维度面向 Web URL，直接使用该地址会导致原生壳 PV 无法与线上应用页面聚合。

[`app/plugins/rum.client.ts`](https://github.com/YunLeFun/apps.yunle.fun/blob/main/app/plugins/rum.client.ts) 会通过 SDK 的 `pageUrl` / `urlHandler` 把原生壳页面映射到公开 origin，并保留当前路由：

```text
capacitor://localhost/tabs/home
→ https://apps.yunle.fun/tabs/home
```

上报接口仍统一使用 `https://rumt-zh.com`。

## 后续

接入后下一步可考虑：

- 自定义性能埋点（自定义 timing）
- 错误聚合 + 告警接入企业微信
- Source Map 上传（让 stack trace 反编译）—— 已在 Nitro 构建产出 `.map` 文件，配合 RUM 上传工具即可
