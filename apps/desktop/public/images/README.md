# 桌面探索素材

「今天，吃点什么？」精选横幅使用 Image Gen 生成的装饰性插画，发布到 COS 的公共 HTTPS 对象地址，横幅二进制不进入 Git 或桌面安装包。图片不包含文字、按钮或其他界面控件；标题和打开操作由 Vue 实现。

媒体地址统一在 `apps/desktop/shared/editorial-media.ts` 的 `COOK_FEATURE_IMAGE_URL` 配置。上线前验证对象可以匿名读取，使用无签名查询参数的固定地址。留空或无效时不加载图片；网络失败时隐藏装饰，保留橙色背景、文案和打开按钮。浏览器请求不发送 Referer，只有该固定 Origin 获得 shell CSP 的 `img-src` 许可。

当前使用现有公共内容桶 `yunlefun-cos-1253292018`（`ap-shanghai`），对象键为 `desktop/banners/cook-feature.png`；[永久公开地址](https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/desktop/banners/cook-feature.png) 已验证匿名读取为 200。对象设置 `Content-Type: image/png` 和一小时缓存，替换该对象后无需重新发布客户端；默认源图尺寸 2172 × 724。该桶已有的 COS 图片瘦身会优化传输 PNG，未改变图片尺寸或视觉内容。

替换同一 COS 对象可更新横幅；若对象路径或 CDN Origin 改变，需要修改共享地址并重新构建验证。原生 ICNS／ICO、favicon／PWA 等品牌图标继续保留在仓库，按现有构建脚本生成和打包。

横幅仅在当前目录允许打开 `cook` 时展示。应用列表继续使用真实目录的名称与 emoji，产品标志来自现有云乐坊图标。
