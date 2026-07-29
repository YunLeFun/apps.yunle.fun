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

### 实时扫码

移动端与 Web 端统一由 `ScannerBarcode` 组件调用浏览器 `getUserMedia` 获取相机画面，再使用 `jsQR` 解码视频帧。

```typescript
const stream = await navigator.mediaDevices.getUserMedia({
  video: { facingMode: 'environment' },
})
```

### 从相册扫码

- Capacitor 原生端使用 `@capacitor/camera` 的 `Camera.chooseFromGallery()` 拉起系统相册。
- Web 端使用隐藏的 `<input type="file" accept="image/*">`。
- 图片先缩放到最长边 1280 像素后交给 `jsQR`；未识别且发生过缩放时，再使用原图重试。

```typescript
import { Camera, MediaTypeSelection } from '@capacitor/camera'

const { results } = await Camera.chooseFromGallery({
  mediaType: MediaTypeSelection.Photo,
  allowMultipleSelection: false,
})

const imageUrl = results[0]?.webPath
```

> Capacitor Camera 8.1 起应使用 `chooseFromGallery()`。不要改回已弃用的 `getPhoto({ source: CameraSource.Photos })`，否则原生相册入口可能直接失败。

## 使用方式

### Composable

```vue
<script setup>
const { scanFromAlbum } = useScanner()

async function handlePickAlbum() {
  const result = await scanFromAlbum()
  if (result)
    console.log('扫码结果:', result)
}
</script>
```

### 组件

```vue
<template>
  <ScannerBarcode
    :is-visible="showScanner"
    :show-flashlight="true"
    @cancel="showScanner = false"
    @result="handleResult"
  />
</template>
```

## 权限要求

| 平台    | 配置                                                                               |
| ------- | ---------------------------------------------------------------------------------- |
| iOS     | `Info.plist` 中添加 `NSCameraUsageDescription` 与 `NSPhotoLibraryUsageDescription` |
| Android | `AndroidManifest.xml` 中添加 `CAMERA` 权限                                         |
| Web     | 浏览器自动请求相机权限，需 HTTPS 环境                                              |
