# Ionic 8 + Konsta UI 设计实践

## 升级概要

项目从 Ionic 7 升级至 Ionic 8，并集成 Konsta UI 5 增强 iOS 原生体验。

## 核心原则

1. **优先使用 Ionic / Konsta UI 组件**，避免自行用 HTML + CSS 重造轮子
2. **禁止硬编码颜色值**（如 `#007AFF`、`text-[#8E8E93]`），统一使用 Ionic CSS 变量或 Ionic `color` prop
3. **样式复用**：公共样式放 `override.scss`，页面中不写重复的 scoped 样式
4. **遵循 iOS HIG**：大标题、分组列表、圆角方块图标、语义化颜色

## 架构模式

### 组件分层原则

| 层级       | 使用框架     | 组件示例                                                                         |
| ---------- | ------------ | -------------------------------------------------------------------------------- |
| 路由/导航  | Ionic Vue    | `IonPage`, `IonHeader`, `IonToolbar`, `IonContent`, `IonTabs`, `IonRouterOutlet` |
| 内容区域   | Konsta UI    | `kList`, `kListItem`, `kBlock`, `kBlockTitle`, `kButton`, `kRadio`               |
| 自定义组件 | Vue + UnoCSS | `AppGrid`, `AppDock`, `AppFeatured`                                              |

**选择指南：**

- 页面骨架（Page / Header / Content / Footer / Tabs）→ **Ionic**
- 页面内容（列表、卡片、按钮、表单控件）→ **Konsta UI**
- Ionic 和 Konsta UI 都不覆盖的场景 → Vue + UnoCSS

### App Shell 结构

```vue
<k-provider theme="parent" :dark="isDark">
  <IonApp>
    <IonRouterOutlet />
  </IonApp>
</k-provider>
```

- `theme="parent"` 让 Konsta 继承 Ionic 的 `.ios` / `.md` 主题模式（**不要用** `theme="ios"`）
- `:dark` 绑定 `@nuxtjs/color-mode` 的暗色状态

## 页面模板规范

### 标准页面（带大标题）

iOS 规范中，Tab 根页面和设置类页面应使用 **Large Title**（折叠大标题）：

```vue
<IonPage>
  <IonHeader :translucent="true">
    <IonToolbar>
      <IonTitle>页面标题</IonTitle>
    </IonToolbar>
  </IonHeader>

  <IonContent :fullscreen="true">
    <!-- 折叠大标题：必须在 IonContent 内部 -->
    <IonHeader collapse="condense">
      <IonToolbar>
        <IonTitle size="large">页面标题</IonTitle>
      </IonToolbar>
    </IonHeader>

    <!-- 页面内容 -->
  </IonContent>
</IonPage>
```

**关键要求：**

- `IonHeader` 设置 `:translucent="true"`
- `IonContent` 设置 `:fullscreen="true"`
- 内部 `IonHeader` 设置 `collapse="condense"` + `IonTitle size="large"`
- 两个 `IonTitle` 文本必须一致

### 子页面（带返回按钮）

```vue
<IonPage>
  <IonHeader :translucent="true">
    <IonToolbar>
      <IonButtons slot="start">
        <IonBackButton default-href="/tabs/me" text="返回" />
      </IonButtons>
      <IonTitle>子页面标题</IonTitle>
    </IonToolbar>
  </IonHeader>

  <IonContent :fullscreen="true">
    <!-- 子页面也可加 condense 大标题 -->
  </IonContent>
</IonPage>
```

## 颜色规范

### 禁止硬编码

```vue
<!-- ❌ 错误：硬编码颜色 -->
<IonIcon class="text-[#007AFF]" />
<div class="bg-[#007AFF]">...</div>
<span style="color: #8E8E93">次要文本</span>

<!-- ✅ 正确：Ionic color prop -->
<IonIcon color="primary" />
<IonIcon color="medium" />

<!-- ✅ 正确：全局 CSS class (定义在 override.scss) -->
<span class="ios-primary-text">主色文本</span>
<span class="ios-secondary-text">次要文本</span>
<div class="ios-avatar-bg">...</div>
```

### Ionic 语义色映射

| 语义       | Ionic color prop | Ionic CSS 变量            | iOS 值    |
| ---------- | ---------------- | ------------------------- | --------- |
| 主色       | `primary`        | `--ion-color-primary`     | `#007AFF` |
| 成功       | `success`        | `--ion-color-success`     | `#34C759` |
| 警告       | `warning`        | `--ion-color-warning`     | `#FF9500` |
| 危险/破坏  | `danger`         | `--ion-color-danger`      | `#FF3B30` |
| 次要/辅助  | `medium`         | `--ion-color-medium`      | `#8E8E93` |

### IonIcon 颜色

对于 Ionic 原生组件，使用 `color` prop：

```vue
<IonIcon :icon="settings" color="primary" />
<IonIcon :icon="person" color="medium" />
```

## iOS 风格列表图标

iOS 设置 App 中，列表项前的图标使用 **29×29 圆角方块背景 + 白色图标**。

### 使用方式

样式已定义在 `app/styles/scss/override.scss`，全局可用：

```vue
<k-list-item link title="设置">
  <template #media>
    <span class="ios-icon-box ios-icon-gray">
      <IonIcon :icon="settings" />
    </span>
  </template>
</k-list-item>
```

### 可用颜色 class

| Class             | 对应色   | 用途示例     |
| ----------------- | -------- | ------------ |
| `ios-icon-blue`   | primary  | 常规功能     |
| `ios-icon-gray`   | medium   | 设置/通用    |
| `ios-icon-red`    | danger   | 退出/删除    |
| `ios-icon-orange` | warning  | 身份/安全    |
| `ios-icon-green`  | success  | 验证/完成    |
| `ios-icon-purple` | —        | 特殊功能     |
| `ios-icon-teal`   | —        | 信息/通知    |

### 用户头像占位

```vue
<div class="ios-icon-avatar">
  <span class="text-xl text-white font-semibold">云</span>
</div>
```

## 破坏性操作样式

退出登录等破坏性按钮使用全局 class：

```vue
<k-list-item
  link
  title="退出登录"
  class="k-list-item-destructive"
  @click="handleLogout"
>
  <template #media>
    <span class="ios-icon-box ios-icon-red">
      <IonIcon :icon="logOut" />
    </span>
  </template>
</k-list-item>
```

## Ionic 8 迁移要点

### Step Color Token

```css
/* 旧 (Ionic 7) */
border-color: var(--ion-color-step-200);

/* 新 (Ionic 8) - 背景用途 */
border-color: var(--ion-background-color-step-200);

/* 新 (Ionic 8) - 文字用途 (数值反转: 1000 - N) */
color: var(--ion-text-color-step-800); /* 原 step-200 */
```

### Dark Palette

通过 CSS 文件导入，不再手写 `@media (prefers-color-scheme: dark)`:

```ts
// nuxt.config.ts css 数组
'@ionic/vue/css/palettes/dark.class.css'
```

配合 `@nuxtjs/color-mode` 的 `classPrefix: 'ion-palette-'` 实现三种模式切换。

### Dynamic Font

Ionic 8 默认启用动态字体缩放，无需额外配置。

## Konsta UI 集成

### CSS 加载顺序

Konsta UI 的样式通过 `app/styles/konsta.css` 加载：

```css
@import 'tailwindcss';
@import 'konsta/vue/theme.css';
```

`nuxt.config.ts` 中 CSS 加载顺序：

```ts
css: [
  '~/styles/css/index.css',        // 全局样式
  '~/styles/css/css-vars.css',     // CSS 变量
  '~/styles/scss/vars.scss',       // SCSS 变量
  '~/styles/scss/index.scss',      // 全局 SCSS
  '~/styles/scss/override.scss',   // Ionic + Konsta 覆盖样式
  '@ionic/vue/css/palettes/dark.class.css',
  '~/styles/ionic.css',            // Ionic 自定义变量
  '~/styles/konsta.css',           // Konsta UI + Tailwind
]
```

### Ionic Typography 兼容

Ionic 全局设置 `a { color: var(--ion-color-primary) }`，会覆盖 Konsta UI 组件内的链接颜色。修复已在 `konsta.css` 中：

```css
.k-list a,
.k-button a,
.k-link,
[class*='k-'] a {
  color: inherit;
}
```

### 自动导入配置

```ts
// nuxt.config.ts
imports: {
  imports: [
    { from: 'konsta/vue', name: 'kProvider', as: 'KonstaProvider' },
    { from: 'konsta/vue', name: 'kList', as: 'KList' },
    { from: 'konsta/vue', name: 'kListItem', as: 'KListItem' },
    // ... 更多组件
  ],
}
```

> 注意：由于 konsta/vue 不在 `@nuxtjs/ionic` 的自动导入范围内，需要手动在各页面 import 或通过上述配置注册。

## 暗色模式

- Konsta UI: 通过 `KonstaProvider` 的 `:dark` prop 控制
- Ionic: 通过 `.ion-palette-dark` CSS class 控制
- 两者通过 `@nuxtjs/color-mode` 统一管理

## 样式文件职责

| 文件                     | 职责                                   |
| ------------------------ | -------------------------------------- |
| `styles/ionic.css`       | Ionic CSS 变量覆盖（背景色、边框等）   |
| `styles/konsta.css`      | Konsta UI 主题 + Tailwind + 兼容修复   |
| `styles/scss/override.scss` | 公共复用样式（ios-icon-box 等）     |
| `styles/css/css-vars.css`| 全局 CSS 自定义属性                    |

## 参考链接

- [Ionic 8 升级指南](https://ionicframework.com/docs/updating/8-0)
- [Konsta UI + Ionic](https://konstaui.com/vue/ionic)
- [Konsta UI + Nuxt](https://konstaui.com/vue/nuxt)
- [@nuxtjs/ionic](https://ionic.nuxtjs.org/get-started/introduction)
- [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/)
