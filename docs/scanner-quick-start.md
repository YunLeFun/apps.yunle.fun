# 扫码功能快速启动指南

## 🚀 快速开始

### 1. 安装依赖（已完成）

```bash
pnpm add @capacitor/barcode-scanner
pnpm run sync
```

### 2. 在首页使用

打开应用首页，点击右上角 `+` 按钮，选择「扫一扫」即可使用。

### 3. 测试页面

访问 `/test-scanner` 页面进行功能测试：

```bash
pnpm run dev
# 然后在浏览器中访问 http://localhost:3000/test-scanner
```

## 📱 在移动设备上测试

### iOS

```bash
# 1. 构建项目
pnpm run build

# 2. 同步到 iOS
pnpm run sync

# 3. 打开 Xcode
pnpm run open:ios

# 4. 在 Xcode 中运行到真机或模拟器
```

### Android

```bash
# 1. 构建项目
pnpm run build

# 2. 同步到 Android
pnpm run sync

# 3. 在 Android Studio 中打开项目
# 打开 android 目录

# 4. 运行到真机或模拟器
```

## 🌐 在浏览器中测试

```bash
# 启动开发服务器
pnpm run dev

# 访问 https://localhost:3000（需要 HTTPS）
# 或使用 ngrok 等工具创建 HTTPS 隧道
```

**注意**：浏览器扫码需要 HTTPS 环境（localhost 除外）。

## 💡 使用示例

### 基础用法

```vue
<script setup>
const showScanner = ref(false)

function handleResult(content: string) {
  console.log('扫码结果:', content)
  showScanner.value = false
}
</script>

<template>
  <IonButton @click="showScanner = true">
    扫一扫
  </IonButton>

  <BarcodeScanner
    :is-visible="showScanner"
    @cancel="showScanner = false"
    @result="handleResult"
  />
</template>
```

### 使用 Composable

```vue
<script setup>
const { startScan } = useBarcodeScan()

async function scan() {
  try {
    const result = await startScan()
    if (result?.content) {
      console.log('扫码结果:', result.content)
    }
  }
  catch (error) {
    console.error('扫码失败:', error)
  }
}
</script>

<template>
  <IonButton @click="scan">
    扫一扫
  </IonButton>
</template>
```

## 🔧 常见问题

### Q: Web 端无法使用相机？

A: 确保使用 HTTPS 协议，或在 localhost 环境下测试。

### Q: iOS 提示没有相机权限？

A: 检查 `Info.plist` 中是否添加了 `NSCameraUsageDescription`。

### Q: Android 无法扫码？

A: 检查 `AndroidManifest.xml` 中是否添加了相机权限。

### Q: 扫码后没有反应？

A: 检查是否正确处理了 `@result` 事件。

## 📚 更多文档

- [完整文档](./barcode-scanner.md)
- [实现总结](../SCANNER_IMPLEMENTATION.md)

## 🎯 下一步

1. 在真机上测试扫码功能
2. 集成条码识别库实现 Web 端实时识别
3. 添加扫码历史记录功能
4. 实现二维码生成功能

## 🆘 需要帮助？

如有问题，请查看：

- [Capacitor 文档](https://capacitorjs.com/docs)
- [Ionic 文档](https://ionicframework.com/docs)
- 项目 Issues
