# 云乐坊桌面图标

`source.png` 是唯一主源：复制自移动端的
`apps/mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png`，
实际尺寸为 1024 × 1024，保留黑底白色云乐坊标志，不重新绘制。

在 macOS 上从仓库根目录重新导出：

```sh
node apps/desktop/scripts/build-icons.mjs
```

脚本使用系统 `sips` 缩放 PNG、`iconutil` 编译 ICNS，以及 Node.js 封装标准 PNG-entry ICO。
它检查源图和导出图的 PNG 尺寸、ICNS 容器及 ICO 的目录、偏移和各帧尺寸。
更新主源后重新执行命令，并提交所有导出文件；Windows 和 Linux 构建直接使用这些文件，
无需安装 macOS 工具或在打包时重新生成。

| 文件              | 用途                                                       |
| ----------------- | ---------------------------------------------------------- |
| `icon.icns`       | macOS 应用和 DMG 图标，包含标准尺寸及 Retina 帧            |
| `icon.ico`        | Windows 应用和安装器图标，包含 16、32、48、256 像素 PNG 帧 |
| `icon.png`        | Linux 图标，512 × 512                                      |
| `icon-{size}.png` | 16、32、48、64、128、256、512、1024 像素导出图             |

同一次导出会更新桌面 `public/` 内的 favicon、180 像素 Apple touch icon、
192/512 像素 PWA icon 和 512 像素 maskable icon。它们保留相同标志与留白，
不使用模板的 Nuxt 或 Vite 图标。
