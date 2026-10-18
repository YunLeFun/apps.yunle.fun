# 开发笔记

开发过程中的技术笔记和经验记录。

## 目录

- [客户端工作区与部署](./monorepo) — `apps/mobile`／`apps/desktop`、构建入口和部署路径
- [iOS 原生改造 Goal](./ios-native-migration) — iOS 优先、SwiftUI 界面、功能迁移清单与分阶段验收
- [iOS 原生接口盘点](./ios-native-api-audit) — HTTP 接口、账号边界与待补能力
- [原生云居同步契约](./ios-home-sync) — 鉴权、修订冲突、离线保存与旧数据兼容边界
- [原生宿主授权接入](./ios-host-authorization) — 注册策略、原生登录回跳、取消与账号隔离
- [原生扫码与链接接收](./ios-scanner) — 系统相册、相机状态、结果路由与真机签名待办
- [原生个人工坊](./ios-workshops) — 创建 / 管理 / 加入、坊客权限、分享和真实联调边界
- [原生应用管理与发布](./ios-publishing) — 本人作品、原生编辑、本机草稿、市场状态与待验范围
- [原生图标资产](./ios-icon-assets) — 公开云图标、深色变体、SVG 解码、缓存与线上资产缺陷
- [原生助手与受管账号验证](./ios-assistant) — 原生 SSE、会员与身份隔离、真实账号验证及部署边界
- [原生应用获取](./ios-acquisition) — 会员 / 云币 / 已购核对、原生确认与账号边界
- [原生钱包与会员](./ios-wallet) — 账户接口、StoreKit 2、购买归属、恢复与 Sandbox 待验范围
- [原生评价与举报](./ios-community) — 原生列表 / 表单、审核状态、账号代次与接口验证
- [iOS 首轮性能基线](./ios-performance-baseline) — 同设备启动样本、公开旅程、测量代码与待验边界
- [桌面构建与私有内测](./desktop-build) — 本机打包、构建记录、SHA256 与单平台 CI
- [Electron 桌面架构](./desktop-electron-architecture) — 安全 preload、内嵌应用与产品接入范围
- [认证](./auth) — Universal Link、微信登录配置
- [扫码功能](./barcode-scanner) — Capacitor 扫码集成
- [沉浸式内嵌浏览器](./in-app-browser) — 胶囊视觉规范与页面 JSAPI（window.ylf）
- [短信登录](./sms-login) — CloudBase 短信验证码登录
- [Home Screen 拖拽排序](./home-screen-drag) — SortableJS 拖拽架构与踩坑记录
- [负一屏 AI Agent](./ai-agent-screen) — 会员对话检索应用方案(CloudBase Web SDK + Agent 工具卡片）
