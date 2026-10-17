# 原生扫码与链接接收

> 2026-10-16：原生相机 / 相册扫码、结果页面和应用 / 工坊链接路由已实现。iOS 27 与 iOS 18.6 的系统相册和 URL 接收旅程已通过；真机测试被本机开发签名配置阻止，实景相机与 Universal Link 安装分发仍未验收。

## 页面与行为

云居提供“扫一扫”，工坊和手动编号输入页提供“扫描工坊二维码”。使用 NavigationStack、List、系统按钮、原生照片选择器和 Safari 页面。扫描内容先显示识别结果，用户选择后进入应用 / 工坊详情，或打开外部网址。普通文本可选择复制、分享；识别不会自动加入工坊、登录、授权、购买或打开外部网站。

工坊扫码只接受工坊编号或本应用的工坊链接。通用扫码支持公开应用链接、工坊链接、HTTP(S) 外部网址和普通文本。多二维码图片列出多个结果供选择，不用首条结果代替用户选择。无二维码、无法读取、图片过大、无效 / 非工坊链接有独立反馈，允许重新选择同一张照片。

相机未授权时先说明用途，用户选择“启用相机”后请求权限；拒绝时提供系统设置入口，受限或无相机时保留相册和手动输入。相机预览、捕获会话与手电筒使用 AVFoundation；配置、启动、停止和设备锁定统一在串行队列执行。进入相册、应用失活、退出页面或识别出结果时停止采集并关闭手电筒。旧相机回调、迟到的权限结果和取消后的图片解码不能替换新页面状态。

预览在 iOS 17+ 使用 AVCaptureDevice.RotationCoordinator 提供的原生补偿角度，iOS 16 使用系统视频方向接口。实景画面、横竖屏、会话中断 / 恢复、实际手电筒和从设置修改权限仍待真机检查。

## 相册与图像处理

使用 PhotosPicker，只访问用户选中的图片，不申请整个照片库权限。选择器取消会返回扫码页；图片导出与解码显示进度，退出后丢弃迟到结果。图片只在本机处理，不上传、不写入业务数据、不记录二维码原文。

ImageIO 先读取尺寸并处理 EXIF 方向，再按 1536 / 4096 / 8192 最大边长逐级识别。输入限制为 60 MiB 与 100 百万像素，超过时提示裁剪二维码区域。低分辨率未识别到内容时才扩大解码尺寸，避免直接常驻完整原图像素。

Vision 与 Core Image 的原生 QR 识别结果合并去重。本轮实际运行发现，iOS 27 模拟器的默认 Vision 推理上下文不可用；选择其报告支持的 CPU 后，仍可能没有有效结果。因此保留 Core Image 本机后备解码，并用实际生成的 PNG、旋转 JPEG、中文文本、多二维码和无二维码图片验证整个解码器。不能把这些测试写成“Vision 在所有设备已验证”。真机默认使用平台计算设备，完整硬件表现仍待验。

## 路由与身份边界

应用二维码只把 apps.yunle.fun 的 /app/:key 解析为原生应用入口。只按正式记录 ID 或唯一 marketShortName 解析真实公开目录，不把私人空间的旧 slug 当作全局应用身份。外部网址中出现 /app/123 仍属于外部网址，先展示地址，再由用户选择使用系统 Safari 页面打开。

工坊链接只提取经过校验的 6 位编号，再交给原有工坊权限接口；链接不能授予坊客资格或其他权益。带 URL 凭据、不支持的 scheme、非标准端口、额外路径及含 query / fragment 的第一方扫描链接会被拒绝。现有含追踪参数链接的兼容与归因需要单独梳理，不能把当前严格解析视为全部旧链接已经迁移。

AppRoot 统一接收 URL 与浏览器用户活动，支持 https://apps.yunle.fun/app/:key、/w/:id，以及 yunlefun://app/:key、yunlefun://w/:id 和既有 yunlefun://workshop/:id。接收后导航到工坊 Tab 中的对应原生页。OAuth 回调不交给该导航解析器，继续属于系统认证会话；钱包返回、/ulink 等其余已有链接仍随对应功能迁移，尚未完成。

原生工程加入 apps.yunle.fun 的 Associated Domains entitlement。线上 AASA 已只读确认 HTTP 200，包含现有正式 App ID 及 /app/_、/w/_、/ulink/\*。开发与 Benchmark 标识没有被添加到线上 AASA；XCTest 的指定应用 URL 启动不能替代正式签名安装后的 Universal Link 分发与冷 / 热启动完整验收。

云居显示条目和应用详情统一保留已保存的工坊修订来源，避免全局公开目录刷新把它替换成获批的公开版本。实际打开仍重新校验工坊权限，二维码和缓存均不能授予权限。

## 验证

新增 18 项原生单元测试，覆盖实际图片解码、路由来源 / 身份、重复或歧义键、工坊修订、相机与权限状态、相册取消、旧回调、图片失败和退出后的迟到结果。原生日常测试共 110 项通过（109 单元 + 1 UI）。

独立的 YunleFunBenchmarks Scheme 已在 iOS 27 / 18.6 运行以下真实 UI 旅程：

- 打开扫码页，确认无相机设备状态；系统照片选择器取消后可返回。
- 从系统照片库选择实际生成的应用二维码，解码后进入真实 AI 春联的原生详情；返回后再次选择同一张图片仍能识别。
- 工坊专用入口选择同一应用二维码，得到正确的非工坊提示，不跳转或提交加入。
- 通过 XCTest URL 启动进入公开应用；既有工坊 scheme 接收后显示当前不存在工坊的 HTTP 404 状态与重试，未伪造成功工坊。

iOS 27 同轮云空调打开 / 收起 / 恢复 / 结束旅程通过。所有这些旅程只读取公开服务，没有登录、发送验证码、写入真实工坊或更改购买状态。

运行相册旅程前，需要把二维码测试导出的 application.png 加到目标测试模拟器照片库，并显式设置 YLF_SCAN_PHOTO_JOURNEY=1；普通日常单元测试不依赖模拟器照片库。可选 YLF_EXPORT_SCAN_FIXTURES=1 导出实际生成的解码测试图片，文件保存在测试进程临时目录。测试工具输出的路径和截图记录于当前任务附件。

## 真机与待验

已只读确认配对 iPhone 可连接，且独立 Benchmark 标识未安装。尝试以 Benchmark 配置运行单元测试时，Xcode 在安装前报 No Accounts、缺少团队的 iOS Development 私钥 / 证书，以及现有 profile 缺少 Associated Domains。因此没有启动真机测试，也没有替换手机现有正式应用。需要在本机 Xcode 配置现有开发团队的账号、Apple Development 签名及带 Associated Domains 的 profile 后继续。

使用 Benchmark 配置运行包含 @testable import 的单元测试时，需要仅在验证命令中显式设置 ENABLE_TESTABILITY=YES；常规 Benchmark 性能配置不因此改变。未签名的 arm64 设备 SDK 测试构建已通过，最低 iOS 16，使用独立 Benchmark 标识；它只能证明编译，不代表设备运行或可分发候选版本。

可复现的本地设备编译命令（不安装、不签名）：

```sh
xcodegen generate --spec apps/ios/project.yml
xcodebuild build-for-testing \
  -project apps/ios/YunleFun.xcodeproj -scheme YunleFun \
  -configuration Benchmark -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/yunlefun-ios-device-validation \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

仍待实景相机 / 手电筒 / 权限矩阵、真实图片与 iCloud 选择、外部网址 / 文本 / 多码的完整 UI、iPad 与辅助字号 / VoiceOver / 深色 / 横屏、真实工坊分享接收、正式签名下的 Universal Link、真机内存及完整旧链接兼容。M3 / M4 及总 Goal 保持未完成。

## 官方依据

- [照片选择器与授权范围](<https://developer.apple.com/documentation/swiftui/view/photospicker(ispresented:selection:matching:preferreditemencoding:photolibrary:)>)
- [请求相机授权](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [捕获二维码类型](https://developer.apple.com/documentation/avfoundation/avcapturemetadataoutput/metadataobjecttypes)
- [原生预览旋转补偿](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator/videorotationangleforhorizonlevelpreview)
- [Vision 计算设备配置](<https://developer.apple.com/documentation/vision/vnrequest/setcomputedevice(_:for:)>)
