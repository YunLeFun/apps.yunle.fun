/**
 * @yunlefun/types 的本仓增补声明。
 * 单一真相源在 YunLeFun/ylf 的 packages/types：新字段先在此增补占位避免阻塞，
 * 待包发版收编后删除对应声明。
 */
import type {} from '@yunlefun/types'
import type { AppIconAssets } from './app'

declare module '@yunlefun/types' {
  interface YlfAppInfo {
    /**
     * 内嵌浏览器展示形态声明（iOS 自定义容器）。
     *
     * 缺省跟随用户全局设置；用户全局选「手机内置」时整体退出自定义容器，声明不生效。
     * 声明 immersive 的应用需经核验已适配胶囊避让（getEnv().capsuleRect），
     * 见 docs/dev/in-app-browser.md。
     */
    displayMode?: 'immersive' | 'titlebar'

    /**
     * 允许调用授信 JSAPI 的可注册域名列表（子域自动匹配）。
     * 仅对人工核验过的应用配置；服务端仍需同步配置 JSAPI 登录白名单。
     */
    trustedHosts?: string[]

    /**
     * 官方认证标记：true 时在详情页 / 列表的应用名旁展示蓝色认证标（✓）。
     * 由平台核验背书，仅第一方 / 官方上架应用标记。
     */
    official?: boolean

    /** 启动器图标的完整图标 / 主体图标与可选深色资源。 */
    iconAssets?: AppIconAssets

    // developer / developerName / screenshots / ratingCount 已随 @yunlefun/types@0.2.0 收编，移除增补。
    // displayMode / trustedHosts 仍为 apps 专属（内嵌浏览器），保留于此。
  }
}
