# JSAPI 接入（window.ylf）

你的网页应用在云乐坊 App 内（iOS 沉浸/标题栏模式）打开时，容器会向页面注入
`window.ylf` 对象，可借此控制宿主：隐藏右上角胶囊、读取安全区与胶囊位置、
关闭浏览器返回云乐坊等。

所有方法均返回 Promise；在普通浏览器中 `window.ylf` 不存在，
请始终以特性检测包裹。

## 环境检测

```js
if (window.ylf?.inYunleApp) {
  // 运行在云乐坊 App 内嵌浏览器内
}
```

## 展示形态

内嵌浏览器形态由应用声明或用户设置决定（沉浸为官方应用专属，普通应用走标题栏 / 手机内置），
页面通过 `getEnv().displayMode` 区分：

- `titlebar` 标题栏模式（默认）：顶部为宿主固定导航栏（套用应用主题色，应用标题 +
  右上角「更多」菜单按钮），页面视口从栏下开始（`safeAreaInsets.top` 为 0），无需避让，
  底部仍铺满到屏幕最底；
- `immersive` 沉浸模式（官方应用声明启用）：网页全屏平铺（顶部直达状态栏），右上角悬浮胶囊，
  页面需按 `safeAreaInsets` / `capsuleRect` 自行避让。

旧版本 App 的 `getEnv()` 无 `displayMode` 字段，按 `immersive` 处理即可。

### 标题栏模式下请求沉浸

标题栏模式下，页面可调用 `hideTitleBar()` 收起顶部导航栏，
临时退化为沉浸姿态（网页铺满到屏顶，右上角「更多」菜单按钮转为悬浮按钮作为退出入口）：

```js
const env = await window.ylf.getEnv()
if (env.titleBarVisible) {
  await window.ylf.hideTitleBar()
  // 收起后视口与胶囊位置都变了，重新读取再做避让
  const next = await window.ylf.getEnv()
  layout(next.safeAreaInsets, next.capsuleRect)
}
```

- 沉浸模式（无标题栏）下 `hideTitleBar()` / `showTitleBar()` 为 no-op，照常 resolve；
- 切换在会话内持久，**不随页内导航重置**（胶囊始终在，不会把用户困住）；
- 不提供切到标题栏模式的能力——标题栏是宿主的信任锚（应用名 + 胶囊），
  只支持「请求更沉浸」这一个方向。用 `canIUse('setTitleBarVisible')` 探测旧版本。

## 快速上手

```js
if (window.ylf?.inYunleApp) {
  const env = await window.ylf.getEnv()
  if ((env.displayMode ?? 'immersive') === 'immersive') {
    // 自绘顶栏时给胶囊留位
    topbar.style.paddingRight = `${innerWidth - env.capsuleRect.x}px`

    // 完全沉浸：隐藏胶囊，并自行提供退出入口
    await window.ylf.hideCapsule()
    document.querySelector('#exit-btn').onclick = () => window.ylf.closeBrowser()
  }
}
```

::: warning 隐藏胶囊后请务必提供退出入口
胶囊是用户关闭浏览器的默认途径。调用 `hideCapsule()` 的页面必须自行放置
退出按钮并调用 `closeBrowser()`。作为保护，胶囊隐藏仅对当前文档生效，
跳转新页面后会自动恢复显示；标题栏模式下顶栏不允许页面隐藏，
`hideCapsule()` 静默无效果。
:::

## API 参考

| 方法                      | 级别 | 说明                                                         |
| ------------------------- | ---- | ------------------------------------------------------------ |
| `invoke(method, params?)` | —    | 通用调用通道，所有方法的底层入口                             |
| `canIUse(method)`         | 公开 | 能力探测：方法存在**且当前页面有权调用**才返回 `true`        |
| `getEnv()`                | 公开 | 宿主环境信息（含展示形态、`trusted` 标记、安全区、胶囊位置） |
| `hideCapsule()`           | 公开 | 隐藏胶囊（仅沉浸模式、仅当前文档生效，跳转新页面自动恢复）   |
| `showCapsule()`           | 公开 | 恢复显示胶囊                                                 |
| `hideTitleBar()`          | 公开 | 收起标题栏退化为沉浸姿态（仅标题栏模式，会话内持久）         |
| `showTitleBar()`          | 公开 | 恢复标题栏                                                   |
| `closeBrowser()`          | 公开 | 关闭浏览器，返回云乐坊                                       |
| `authorize(params)`       | 授信 | 为精确注册的第一方客户端申请短时、单次 SSO code              |
| `setClipboard(text)`      | 授信 | 写入系统剪贴板（如复制兑换码）                               |

```ts
interface YlfJSAPI {
  /** 协议版本，新增能力时递增 */
  version: number
  /** 恒为 true，用于检测是否运行在云乐坊 App 沉浸式浏览器内 */
  inYunleApp: true
  invoke: (method: string, params?: Record<string, unknown>) => Promise<unknown>
  canIUse: (method: string) => Promise<boolean>
  getEnv: () => Promise<{
    platform: 'ios'
    appId: string
    /** 展示形态（旧版本 App 无此字段，按 immersive 处理） */
    displayMode?: 'immersive' | 'titlebar'
    /** 当前页面来源是否授信（可调用「授信」级方法） */
    trusted: boolean
    capsuleVisible: boolean
    /** 标题栏当前是否显示（沉浸模式恒为 false；hideTitleBar 后为 false） */
    titleBarVisible?: boolean
    /** 页面视口的安全区，单位 CSS px（标题栏显示时 top 为 0；收起后恢复为状态栏高度） */
    safeAreaInsets: { top: number, bottom: number, left: number, right: number }
    /**
     * 胶囊布局位置（视口坐标，CSS px），沉浸页面据此避让，类比 wx.getMenuButtonBoundingClientRect；
     * 标题栏显示时胶囊在视口上方（y 为负），按矩形避让自然判定无重叠
     */
    capsuleRect: { x: number, y: number, width: number, height: number }
  }>
  hideCapsule: () => Promise<void>
  showCapsule: () => Promise<void>
  hideTitleBar: () => Promise<void>
  showTitleBar: () => Promise<void>
  closeBrowser: () => Promise<void>
  authorize: (params: {
    clientId: string
    redirectUri: string
    scope: string[]
    nonce: string
    codeChallenge: string
    codeChallengeMethod: 'S256'
  }) => Promise<{ ok: true, code: string, issuer: string, expiresAt?: number }>
  setClipboard: (text: string) => Promise<void>
}
```

内嵌浏览器不转移登录会话。`authorize` 只为精确注册的第一方 SSO client 签发
绑定来源、nonce 与 PKCE 的短时单次 code；页面仍要在自己的 Origin/BFF 消费它。
宿主不会向页面传递 CloudBase access token 或 refresh token。当前注册项为：

- `https://admin.yunle.fun` / `admin-web` / `identity:bootstrap`
- `https://saier.yunle.fun` / `saier-web` / `identity:bootstrap`
- `https://play.yunle.fun` / `play-web` / `identity:bootstrap`
- `https://wenta.yunle.fun` / `wenta-web` / `identity:bootstrap`
- `https://cms.yunle.fun` / `cms-web` / `identity:bootstrap`

共享 `yunle.fun` 后缀不会自动获得授权；应用 id、Origin、client id、redirect URI
和 scope 必须同时精确匹配第一方注册表。

## 权限与授信

方法分两级：

- **公开**：无害 UI 控制能力，所有页面可直接调用。
- **授信**：敏感能力，仅授信域名下的页面可调用。要求页面通过 **https**
  访问，且域名经云乐坊人工核验后加入授信名单（含全部子域）。
  如需为你的应用开通，请联系云乐坊并提供应用域名。

未授信页面调用授信级方法时 Promise 会 reject，不会静默失败。
推荐用 `canIUse` 一次性探测「方法存在 + 有权调用」后再决定交互路径：

```js
if (await window.ylf.canIUse('setClipboard'))
  await window.ylf.setClipboard('COUPON-2026')
else
  showManualCopyDialog('COUPON-2026') // 旧版本 App 或未授信时降级
```

## 错误处理

调用失败时 Promise reject，`Error.message` 为以下之一：

- `unknown method: <name>` — 方法不存在（或用户的 App 版本过旧）；
- `permission denied: <name> requires trusted host` — 授信级方法 + 来源未授信；
- `forbidden: main frame only` — 在 iframe 中调用（JSAPI 仅注入主文档）；
- `bad request: ...` — 缺少必要参数。

## 调试

- **真机调试**：Mac Safari「开发」菜单 → 选择设备 → 选中云乐坊的沉浸式
  WebView，在控制台直接调用 `window.ylf.*` 验证。
- **本机调试**：`http://localhost` / `http://127.0.0.1` 豁免 https 要求，
  但调用授信级方法仍需宿主侧将 `localhost` 加入会话授信名单。

## 兼容性

- 目前仅 iOS App 的「沉浸模式」「标题栏模式」注入 `window.ylf`（手机内置模式、
  Android、Web 端均无）；Android 未来将实现同名接口，页面代码无需改动。
- 新增能力时 `version` 递增；跨版本兼容请依赖 `canIUse` 探测而非版本号判断。

> 容器内部实现（鉴权模型、新增方法流程）见 [沉浸式内嵌浏览器](/dev/in-app-browser)。
