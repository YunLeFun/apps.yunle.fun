# Design 桌面适配

桌面 renderer 使用已发布的 `@yunlefun/ui@0.0.6` CSS tokens，加载顺序为 `@yunlefun/ui/css`、`app/assets/main.css`。品牌、语义状态、间距、动效和表面高光来自 [YunLeFun/design](https://github.com/YunLeFun/design)；桌面适配层定义中性背景、控件密度和窗口布局，继续使用系统字体。

| 范围                               | 采用方式                                                   |
| ---------------------------------- | ---------------------------------------------------------- |
| 导航、链接、打开按钮、键盘焦点     | Design 品牌蓝、soft／hover／active tokens                  |
| 错误、目录提示、正在使用指示       | Design danger／info／success 语义色                        |
| 列表组、搜索框、工具栏、关于页     | 中性表面配合 Design highlight／control／inset shadow       |
| 内容留白、列表间距、圆角、交互过渡 | Design space／radius／duration／ease tokens                |
| 原生窗口与 Web 应用工作区          | 216px 侧栏、52px 工具栏、隔离 WebContentsView 布局保持稳定 |

没有引入未发布的 Editor CSS、Sass SFC 库或远程字体。标题沿用共享系统 heading 字体；正文系统字体优先。减少动态效果偏好继续生效，点击控件保留清晰的 hover、active、disabled 和键盘 focus 状态。

此适配保留 App Store 式探索页与原生窗口层次。品牌样式集中于导航和控件，嵌入应用使用完整内容区域。媒体维护与正式品牌优先策略见[应用目录图标](./desktop-app-icons.md)。

验收覆盖深浅外观、800 × 600 和 1280 × 840 窗口、键盘焦点、搜索与长标题、空列表、关于页、在线／离线目录和原生 guest 的打开／隐藏／继续／销毁；证据见[视觉验收](https://github.com/YunLeFun/apps.yunle.fun/blob/main/apps/desktop/design-qa.md)。
