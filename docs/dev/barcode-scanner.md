# 扫码功能

## 功能概述

云乐坊应用集成了条码/二维码扫描功能，支持在移动端和 Web 端使用。

## 功能特性

- 支持二维码和条形码扫描
- 原生移动端支持（iOS/Android）
- Web 端相机预览支持
- 自动识别 URL 链接
- 应用链接快速跳转

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
  video: { facingMode: 'environment' },
})
```

## 使用方式

### Composable

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

### 组件

```vue
<template>
  <BarcodeScanner
    :is-visible="showScanner"
    :show-flashlight="true"
    @cancel="showScanner = false"
    @result="handleResult"
  />
</template>
```

## 权限要求

| 平台    | 配置                                           |
| ------- | ---------------------------------------------- |
| iOS     | `Info.plist` 中添加 `NSCameraUsageDescription` |
| Android | `AndroidManifest.xml` 中添加 `CAMERA` 权限     |
| Web     | 浏览器自动请求相机权限，需 HTTPS 环境          |
