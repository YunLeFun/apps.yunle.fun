# 扫码功能使用说明

## 功能概述

云乐坊应用集成了条码/二维码扫描功能，支持在移动端和 Web 端使用。

## 功能特性

- ✅ 支持二维码和条形码扫描
- ✅ 原生移动端支持（iOS/Android）
- ✅ Web 端相机预览支持
- ✅ 自动识别 URL 链接
- ✅ 应用链接快速跳转
- ✅ 优雅的扫描界面

## 使用方式

### 在首页使用

1. 点击右上角的 `+` 按钮
2. 在下拉菜单中选择「扫一扫」
3. 对准二维码/条形码进行扫描
4. 自动识别并处理扫描结果

### 扫描结果处理

- **应用链接**：自动跳转到应用详情页
- **普通 URL**：询问是否在浏览器中打开
- **其他内容**：显示扫描结果

## 技术实现

### 移动端（Capacitor）

使用 `@capacitor/barcode-scanner` 插件：

```typescript
import { BarcodeScanner } from '@capacitor/barcode-scanner'

const result = await BarcodeScanner.startScan()
if (result.hasContent) {
  console.log('扫码结果:', result.content)
}
```

### Web 端

使用浏览器的 `getUserMedia` API：

```typescript
const stream = await navigator.mediaDevices.getUserMedia({
  video: { facingMode: 'environment' }
})
```

## 权限要求

### iOS

在 `Info.plist` 中添加相机权限说明：

```xml
<key>NSCameraUsageDescription</key>
<string>需要使用相机进行扫码</string>
```

### Android

在 `AndroidManifest.xml` 中添加相机权限：

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### Web

浏览器会自动请求相机权限，用户需要允许访问。

## 开发指南

### 使用 Composable

```vue
<script setup>
import { useBarcodeScan } from '~/composables/useBarcodeScan'

const { startScan, stopScan, isScanning } = useBarcodeScan()

async function handleScan() {
  const result = await startScan()
  if (result?.content) {
    console.log('扫码结果:', result.content)
  }
}
</script>
```

### 使用组件

```vue
<script setup>
const showScanner = ref(false)

function handleResult(content: string) {
  console.log('扫码结果:', content)
  showScanner.value = false
}
</script>

<template>
  <BarcodeScanner
    :is-visible="showScanner"
    :show-flashlight="true"
    @cancel="showScanner = false"
    @result="handleResult"
  />
</template>
```

## 注意事项

1. **HTTPS 要求**：Web 端扫码需要在 HTTPS 环境下使用
2. **权限处理**：首次使用需要用户授权相机权限
3. **浏览器兼容性**：部分旧版浏览器可能不支持相机 API
4. **性能优化**：扫码完成后记得停止相机流以节省资源

## 未来计划

- [ ] 集成条码识别库（如 @zxing/library）
- [ ] 支持手电筒功能
- [ ] 支持从相册选择图片识别
- [ ] 支持生成二维码
- [ ] 支持扫码历史记录

## 相关文件

- `app/composables/useBarcodeScan.ts` - Capacitor 扫码 Composable
- `app/composables/useWebBarcodeScan.ts` - Web 扫码 Composable
- `app/components/scanner/BarcodeScanner.vue` - 扫码界面组件
- `app/pages/tabs/home.vue` - 首页集成示例
