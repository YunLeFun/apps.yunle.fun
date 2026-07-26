# 隐私政策核对清单

> 上架 App Store / 国内应用商店之前必须确认隐私政策页面覆盖以下披露项。
> 对照 <https://www.yunle.fun/docs/privacy-policy> 逐条勾选。
>
> 2026-07-26 的代码—线上政策逐项结果见
> [privacy-release-audit.md](./privacy-release-audit.md)。线上政策 P0 披露已发布；
> App Store Connect 隐私标签和首次启动同意评审仍须在公开上架前完成。

## 必须覆盖的披露项（按 App Store 隐私问卷分类）

### 1. 联系信息 / Contact Info

- [x] **手机号**：登录时收集（CloudBase OTP 短信验证）
  - 用途：账号身份识别 / 登录
  - 留存期：账户存续期间
  - 是否分享给第三方：仅传 CloudBase
- [x] **电子邮件**：登录时可选收集（CloudBase Email OTP）
  - 同上
- [x] **微信 OpenID / UnionID**：微信登录时收集
  - 用途：账号身份识别
  - 留存期：账户存续期间

### 2. 标识符 / Identifiers

- [x] **用户 ID（CloudBase uid）**：服务端自动生成
- [x] **设备 ID**：腾讯 RUM Aegis `aid`（localStorage 随机标识；当前没有证据表明采集 IDFA/IDFV）
- [x] **RUM 用户标识 uin**：错误监控按用户聚合（登录后为 CloudBase uid）

### 3. 使用数据 / Usage Data

- [x] **应用使用日志**：用户打开了哪些云应用、何时打开（云居"最近使用"）
- [x] **产品交互**：搜索关键词、安装应用、提交工坊作品
- [x] **用户生成内容**：工坊应用、评论、评分、举报理由/详情
- [x] **AI 内容**：提示词、上下文、回复、会话与运行标识
- [x] **购买历史**：StoreKit product ID、transaction ID、会员/云币流水
- [x] **崩溃日志 / 性能数据**：腾讯云 RUM 自动采集
  - Web Vitals（LCP、FID、CLS、INP）
  - JS 异常 / unhandledrejection
  - 网络请求耗时

### 4. 第三方 SDK 清单（必列）

- [x] **腾讯 CloudBase JS SDK**：数据库 / 认证 / 文件存储
- [x] **腾讯云 RUM (aegis-web-sdk)**：错误与性能监控
- [x] **腾讯云 AI Bot / 模型服务**：AI 对话与工具调用
- [x] **腾讯云文本内容安全 TMS**：评论、举报等文本审核
- [x] **Apple StoreKit / App Store Server API**：IAP 购买、恢复与交易核验
- [x] **Capacitor 8**：iOS 原生壳
  - `@capacitor/app` `@capacitor/browser` `@capacitor/keyboard` `@capacitor/status-bar` `@capacitor/haptics` `@capacitor/barcode-scanner`
- [x] **微信 SDK (cordova-plugin-wechat)**：iOS 微信登录
- [x] **GitHub OAuth**：仅 Web，不在 iOS 端启用

### 5. 数据存储位置

- [x] 明确声明：**腾讯云 CloudBase 上海**（业务/认证数据）和 **腾讯云 RUM 广州**（监控数据）
- [x] 核心业务和监控数据境内存储；Apple、GitHub 等第三方可能涉及的跨境处理已单独披露

### 6. 用户权利

- [x] **如何注销账号**：联系 `i@yunle.fun` 或在应用内「设置 → 账号 → 注销」
- [x] **如何导出 / 删除数据**：联系 `i@yunle.fun`
- [x] **如何申诉**：`i@yunle.fun` / 工单
- [x] **儿童保护**：明确说明本应用不面向 14 岁以下用户

### 7. Cookie / 本地存储

- [x] localStorage 项清单（至少按用途归类，详细键见专项审计）：
  - `ylf:homescreen-apps` 主屏幕配置
  - `ylf:dock-apps` Dock 应用
  - `ylf:recent-apps-v2` 最近使用
  - `ylf:dock-visible` Dock 显示开关
  - `ylf:cloud-sync-enabled` 云同步开关
  - `ylf_theme_mode` 浅/深色偏好
  - `app_create_draft` 工坊草稿
  - `ylf_access_token` / `ylf_user_info` 登录态镜像
  - `ylf_saved_accounts` / `ylf_last_phone` 登录便利信息（手机号仅 Base64 混淆，不是加密）
  - Aegis `aid` 监控设备标识
- [x] cookie：`ylf_access_token` JWT token 与 `ylf_user_info`（31 天有效期）

### 8. 必备元信息

- [x] 文档生效日期
- [x] 最近更新日期
- [x] 数据控制者：海州区云乐坊信息技术工作室
- [x] 联系方式：`i@yunle.fun`

---

## 服务条款核对（<https://www.yunle.fun/docs/terms-of-service>）

- [ ] 用户行为规范（禁止上传违规云应用：色情、赌博、钓鱼、版权侵权）
- [ ] 工坊应用提交规则（需审核，详见 [cloudbase-rules.md](./cloudbase-rules.md)）
- [ ] 违规处理：警告 → 下架应用 → 封号
- [ ] 知识产权（应用作者保留，平台仅展示）
- [ ] 平台免责（云应用内容由开发者负责，平台不承担连带责任）
- [ ] 服务变更 / 终止条款
- [ ] 争议解决（适用法律、管辖法院）
- [ ] 联系方式

---

## 检查方法

1. 打开两个 URL（已用 `open` 帮你打开）
2. 按 `Cmd+F` 在页面里搜上面每条加粗的关键词，确认有相关段落
3. 缺哪条就回 `docs` 站源码补一段；建议交付前打个 prod 版预览
4. 都齐了，把这两个 URL 填到 App Store Connect「App 隐私」字段

## 如果有遗漏

需要在 `www.yunle.fun` 那个仓库（不是本 App 仓库）的 docs 目录下，找到 `privacy-policy.md` 和 `terms-of-service.md` 补充对应段落。

最低限度的合规模板：参考 [Apple 官方示例](https://www.apple.com/legal/privacy/data/zh/apple-id/) 或 [Notion 隐私政策模板](https://www.notion.so/privacy)。
