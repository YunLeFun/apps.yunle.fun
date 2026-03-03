# Ionic + Konsta UI 设计实践

## 核心原则

1. **优先使用 Ionic / Konsta UI 组件**，避免用 HTML + CSS 重造轮子
2. **禁止硬编码颜色值**，统一使用 Ionic CSS 变量或 `color` prop
3. **样式复用**：公共样式放 `override.scss`
4. **遵循 iOS HIG**：大标题、分组列表、圆角方块图标、语义化颜色

## 组件分层

| 层级       | 使用框架     | 组件示例                                             |
| ---------- | ------------ | ---------------------------------------------------- |
| 路由/导航  | Ionic Vue    | `IonPage`, `IonHeader`, `IonTabs`, `IonRouterOutlet` |
| 内容区域   | Konsta UI    | `kList`, `kListItem`, `kBlock`, `kButton`            |
| 自定义组件 | Vue + UnoCSS | `AppGrid`, `AppDock`, `AppFeatured`                  |

**选择指南：**

- 页面骨架 → **Ionic**
- 页面内容 → **Konsta UI**
- 以上都不覆盖 → Vue + UnoCSS

## App Shell 结构

```vue
<k-provider theme="parent" :dark="isDark">
  <IonApp>
    <IonRouterOutlet />
  </IonApp>
</k-provider>
```

`theme="parent"` 让 Konsta 继承 Ionic 的 `.ios` / `.md` 主题模式。

## 页面模板

### 标准页面（带大标题）

```vue
<IonPage>
  <IonHeader :translucent="true">
    <IonToolbar>
      <IonTitle>页面标题</IonTitle>
    </IonToolbar>
  </IonHeader>

  <IonContent :fullscreen="true">
    <IonHeader collapse="condense">
      <IonToolbar>
        <IonTitle size="large">页面标题</IonTitle>
      </IonToolbar>
    </IonHeader>
    <!-- 内容 -->
  </IonContent>
</IonPage>
```

## 颜色规范

| 语义 | Ionic color prop | CSS 变量              | iOS 值    |
| ---- | ---------------- | --------------------- | --------- |
| 主色 | `primary`        | `--ion-color-primary` | `#007AFF` |
| 成功 | `success`        | `--ion-color-success` | `#34C759` |
| 警告 | `warning`        | `--ion-color-warning` | `#FF9500` |
| 危险 | `danger`         | `--ion-color-danger`  | `#FF3B30` |
| 次要 | `medium`         | `--ion-color-medium`  | `#8E8E93` |

## 暗色模式

- Konsta UI：`KonstaProvider` 的 `:dark` prop
- Ionic：`.ion-palette-dark` CSS class
- 统一由 `@nuxtjs/color-mode` 管理
