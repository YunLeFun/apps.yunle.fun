# 隐私政策核对清单

> 上架 App Store / 国内应用商店之前必须确认隐私政策页面覆盖以下披露项。
> 对照 <https://www.yunle.fun/docs/privacy-policy> 逐条勾选。

## 必须覆盖的披露项（按 App Store 隐私问卷分类）

### 1. 联系信息 / Contact Info

- [ ] **手机号**：登录时收集（CloudBase OTP 短信验证）
  - 用途：账号身份识别 / 登录
  - 留存期：账户存续期间
  - 是否分享给第三方：仅传 CloudBase
- [ ] **电子邮件**：登录时可选收集（CloudBase Email OTP）
  - 同上
- [ ] **微信 OpenID / UnionID**：微信登录时收集
  - 用途：账号身份识别
  - 留存期：账户存续期间

### 2. 标识符 / Identifiers

- [ ] **用户 ID（CloudBase uid）**：服务端自动生成
- [ ] **设备 ID**：iOS IDFV（Capacitor 默认上报）
- [ ] **RUM 用户标识 uin**：错误监控按用户聚合（即 CloudBase uid）

### 3. 使用数据 / Usage Data

- [ ] **应用使用日志**：用户打开了哪些云应用、何时打开（云居"最近使用"）
- [ ] **产品交互**：搜索关键词、安装应用、提交工坊作品
- [ ] **崩溃日志 / 性能数据**：腾讯云 RUM 自动采集
  - Web Vitals（LCP、FID、CLS、INP）
  - JS 异常 / unhandledrejection
  - 网络请求耗时

### 4. 第三方 SDK 清单（必列）

- [ ] **腾讯 CloudBase JS SDK**：数据库 / 认证 / 文件存储
- [ ] **腾讯云 RUM (aegis-web-sdk)**：错误与性能监控
- [ ] **Capacitor 8**：iOS 原生壳
  - `@capacitor/app` `@capacitor/browser` `@capacitor/keyboard` `@capacitor/status-bar` `@capacitor/haptics` `@capacitor/barcode-scanner`
- [ ] **微信 SDK (cordova-plugin-wechat)**：iOS 微信登录
- [ ] **GitHub OAuth**：仅 Web，不在 iOS 端启用

### 5. 数据存储位置

- [ ] 明确声明：**腾讯云 CloudBase，上海机房**（环境 `yunlefun-8g7ybcxc7345c490`，region `ap-shanghai`）
- [ ] 不出境（符合《数据安全法》《个人信息保护法》境内存储要求）

### 6. 用户权利

- [ ] **如何注销账号**：联系 `kf@yunle.fun` 或在应用内「设置 → 账号 → 注销」
- [ ] **如何导出 / 删除数据**：联系 `kf@yunle.fun`
- [ ] **如何申诉**：`kf@yunle.fun` / 工单
- [ ] **儿童保护**：明确说明本应用不面向 14 岁以下用户

### 7. Cookie / 本地存储

- [ ] localStorage 项清单：
  - `ylf:home-screen` 主屏幕配置
  - `ylf:dock-apps` Dock 应用
  - `ylf:dock-visible` Dock 显示开关
  - `ylf:cloud-sync-enabled` 云同步开关
  - `ylf-color-mode` 浅/深色偏好
  - `app_create_draft` 工坊草稿
- [ ] cookie：JWT token（31 天有效期）

### 8. 必备元信息

- [ ] 文档生效日期
- [ ] 最近更新日期
- [ ] 数据控制者：云乐坊工作室
- [ ] 联系方式：`kf@yunle.fun` / `i@yunle.fun`

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
