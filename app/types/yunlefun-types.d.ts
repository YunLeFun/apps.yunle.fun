/**
 * @yunlefun/types 的本仓增补声明。
 * 单一真相源在 YunLeFun/ylf 的 packages/types：新字段先在此增补占位避免阻塞，
 * 待包发版收编后删除对应声明。
 */
import type {} from '@yunlefun/types'

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
     * 开发者标识（对应 CloudBase apps 集合 `ownerLogin`，通常为 GitHub 登录名）。
     *
     * 用于「开发者主页」与「该开发者的其他 App」聚合；内置快照可能缺省，
     * 运行时从集合拉取后由 recordToAppInfo 回填。
     */
    developer?: string

    /**
     * 开发者展示名（中文名等）。缺省回退 GitHub 资料的 name，再回退 developer 登录名。
     * 待 @yunlefun/types 收编后删除此处声明。
     */
    developerName?: string

    /**
     * 应用截图 URL 列表，用于详情页预览区展示真实截图；缺省回退占位面板。
     * 待 @yunlefun/types 收编后删除此处声明。
     */
    screenshots?: string[]

    /**
     * 评分人数（已发布评论数），与 rating 同为评论聚合缓存。
     * 列表据此判断是否有真实评分（为 0 / 缺省则不展示评分）。
     * 待 @yunlefun/types 收编后删除此处声明。
     */
    ratingCount?: number
  }
}
