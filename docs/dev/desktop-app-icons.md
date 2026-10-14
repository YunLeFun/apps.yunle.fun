# 桌面应用目录图标

更新日期：2026-10-14。桌面应用目录的 28 个默认缩略图覆盖当前 25 个在线应用与 19 个离线白名单的并集。品牌审计后，17 个保留正式品牌，11 个使用新的桌面变体；原先生成的 16 个素材均保留可追溯记录，其中 5 个不再作为默认。应用名称、公开策略和打开入口仍由实际目录提供。

## 设计与导出

参考 [Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) 的简单主体、居中构图、充分留白、小尺寸辨识和跨外观一致性。新绘缩略图使用单一物件、克制的材质与内部光影；不将应用名称、界面截图或细碎说明放进图标。空调、风扇、字符画、色轮、画笔和复古手柄沿用用户选定参考的视觉含义。

这里交付的是 Web 应用目录内的静态缩略图。新绘原图保留方形全幅、不预烘外部圆角，显示层统一提供 56px 尺寸与 12px 圆角；正式品牌资产保留既有标识。深浅主题使用相同主体，避免更换元素后难以识别。

源文件统一导出 1024 × 1024 PNG，列表使用 256 × 256 WebP（质量 90）。16 个新图分别使用内置 Image Gen 生成；原始生成尺寸为 1254 × 1254，导出阶段用 `sips` 确定性缩放。正式 SVG 用 `rsvg-convert` 栅格化，PNG 保留图像内容后缩放，再用 `cwebp` 压缩；透明的 Give Me Money 金币标志补暖浅色底。当前 28 个默认缩略图合计 138,668 字节，最大单图 15,480 字节。

原生 macOS App Icon 使用另一条构建流程，见[桌面构建](./desktop-build.md#图标来源)。要提供系统原生分层、深色或 tinted 外观，需要按 [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) 准备独立图层并由系统施加掩膜和效果；静态目录缩略图不代表已完成该原生图层交付。

## 资源与更新

- 公共桶：`yunlefun-cos-1253292018`，地域 `ap-shanghai`。
- 列表对象：`desktop/app-icons/v1/{slug}.webp`。
- 1024px PNG 源图：`desktop/app-icons/masters/v1/{slug}.png`。
- 固定 URL 清单：`apps/desktop/shared/app-icons.ts`，从 `YunLeFun/icons` 的 `assets/catalog/app-assets.json` 显式同步。资源与横幅使用相同 HTTPS Origin，无新增 CSP 来源。
- 上传时逐项确认目标不存在，未覆盖已有对象；所有缩略图已匿名读取为 200、`image/webp`，响应字节与本地优化文件一致。
- 图标使用 `Cache-Control: public, max-age=31536000, immutable`。新版本使用新路径并更新清单，不覆盖已声明 immutable 的对象。

本地原图、PNG 源图、优化文件和校验记录保存在 `apps/desktop/.media/app-icons/v1/`，由 Git 忽略，且不在 Forge 打包白名单内。Git 和安装包只携带 URL 与显示逻辑。正式品牌图标的源仓库继续作为设计权威；新的目录素材后续可通过相同 URL 供 Web／移动端复用。

`AppIcon` 只根据固定 slug 清单选择资源，不接收远端目录的任意图片 URL。请求使用 `no-referrer`、异步解码与懒加载；未知 slug 或网络失败时回退目录 emoji，保持同一尺寸。source 切换清除失败状态，旧图片节点的迟到错误不能影响新图片。

## 新图提示词与主体

以下是生成素材的归档记录，并不表示每个应用都采用新图作为正式品牌。做菜、FC、Web Resume、Everything Generator 与 Pixi Painter／Saier 的新图在统一预览中列为候选；桌面默认保留其专属品牌。

共同提示词：单个方形全幅不透明应用图标；主体光学居中，约占 65–70% 画布，保留呼吸空间；macOS 风格的简洁轮廓、细腻低浮雕材质、上左柔光和克制内部阴影，56px 下可辨识。无名称、非必要文字、商标、界面截图、外边框、预烘圆角、外部投影、透明留白或复杂场景。参考图只提供风格，不作为整页编辑目标。

| slug                 | 单个资产的主体与配色                         |
| -------------------- | -------------------------------------------- |
| cook                 | 陶土橙底，象牙白碗、绿色叶菜与一片番茄       |
| air-conditioner      | 晴空蓝底，象牙白壁挂空调与深蓝出风口         |
| electric-fan         | 薄荷绿底，象牙白三叶转子与中心轴             |
| char-dust            | 炭灰底，以清晰象牙白像素块构成 A             |
| color-dust           | 珍珠浅底，大色轮与清晰中孔                   |
| pixi-painter         | 暖白底，深色画笔与一条连续彩色笔触           |
| fc                   | 珊瑚红底，象牙白复古手柄、方向键与两颗红按钮 |
| chat-generator       | 晴空蓝底，两枚重叠浅色对话气泡               |
| web-resume           | 浅灰蓝底，简洁纸页、头像和三条信息线         |
| birthday             | 桃粉底，白色蛋糕与三支短蜡烛                 |
| augma                | 桃橙底，原创象牙白 AR 头带与青色镜片         |
| explosions           | 深紫底，珊瑚橙爆裂轮廓与暖黄中心             |
| everything-generator | 深蓝底，两枚简洁蓝白棱面宝石                 |
| sponsors             | 暖奶油底，单个珊瑚粉心形                     |
| wc-github-corners    | 浅青底，折角纸片与原创猫头剪影               |
| star-markdown-css    | 靛蓝底，纸页、金色星形与两条信息线           |

## 正式品牌来源

| slug          | 已发布的正式来源                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------- |
| give-me-money | [金币标志](https://gmm.yunle.fun/give-me-money-app-icon.svg)                                                  |
| go-far-away   | [Go Far Away](https://go-far-away.yyj.moe/img/go-far-away-app-icon.svg)                                       |
| yunjian       | [CMS 图标](https://github.com/YunLeFun/icons/blob/main/packages/icons/svg/cms-app-icon.svg)，目录名称沿用云栈 |
| wenta         | [问 TA](https://wenta.yunle.fun/brand/wenta-app-icon.svg)                                                     |
| play          | [云乐坊间](https://play.yunle.fun/assets/play-app-icon-v1.svg)                                                |
| smap          | [SMAP](https://smap.yunle.fun/smap-app-icon.svg)                                                              |
| advjs-studio  | [ADV.JS Studio](https://advjs.yunle.fun/brand/advjs-studio-app-icon.svg)                                      |
| ai-sfc        | [AI 春联](https://ai-sfc.yunle.fun/brand/ai-sfc-logo-256.png)                                                 |
| paper-star    | [星纸](https://assets.play.yunle.fun/games/paper-star/runtime/v2/icon.png)                                    |
| pachinko      | [云乐弹珠](https://play.yunle.fun/games/pachinko/icon-512.png)                                                |
| dayun-kicker  | [暴力电驴](https://dayun-kicker.yunle.fun/icon-512.png)                                                       |
| ak-ui         | [AK UI](https://ak-ui.yyj.moe/ak-ui-app-icon.svg)                                                             |

SMAP 和星纸在目录中曾出现失效的旧图片地址，本轮使用已验证的正式资源；客户端不会从失效地址回退到另一个未验证 Origin。

## 品牌审计与统一预览

不能从应用目录 `logo` 为空推断应用没有图标。对 16 个新绘素材逐项检查当前项目源码和 favicon／PWA 声明后：

- 5 项有明确专属品牌：cook、fc、web-resume、everything-generator、pixi-painter（项目现名 Saier）。它们的正式源图按固定源码 commit 导出到 `desktop/app-icons/v2/{slug}.webp`，旧 `v1` 生成版本留作候选。
- 9 项已有旧 favicon、选用的通用图形、标记或插图。新图只作为桌面目录变体，不据此覆盖其站点或安装图标；AUGMA 的 A 标记和来源未证实的旧 PNG 尤其需要原图对照。
- 2 项缺少独立正式图标：Explosions 使用 Nuxt 默认图，WC GitHub Corners 使用 GitHub favicon。新设计可用来建立自身识别，统一预览提供采用建议与源图。

`YunLeFun/icons` 的外部媒体目录记录名称、采用状态、原有身份、候选图、固定源码路径和资源摘要。PNG／WebP 留在 COS，SVG／Iconify 集合仍只接受真正的矢量源，不把 PNG 嵌入伪 SVG。上传成功、桌面采用、应用官网正式发布是不同状态；本轮没有部署这些应用的 favicon 或 PWA 改动。

显式同步固定快照：

```bash
pnpm --dir apps/desktop icons:sync --source /path/to/YunLeFun/icons
pnpm --dir apps/desktop icons:sync --source /path/to/YunLeFun/icons --check
```

同步只读取选定的 `desktopAsset.thumbnail`，验证固定公开 Origin、slug、无凭据或查询参数、256px WebP 与 SHA-256，再生成 URL 清单与中央清单摘要。正常构建、CI 和运行不需要兄弟仓库或在线读取图标清单。

桶的 [自动极智压缩](https://cloud.tencent.com/document/product/436/88711) 会改变公开 PNG 响应字节；源图 SHA-256 对应存储对象，不能用普通 GET 的压缩结果假装核验原稿。上传以 Content-MD5 和对象 ETag 校验原始字节；公开响应另验格式、1024px 尺寸并记录响应摘要。256px WebP 的公开响应与固定本地文件字节一致。
