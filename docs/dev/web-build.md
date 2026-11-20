# 工坊 AI 制作网页

创作和投稿在 iOS 工坊完成。工坊入口向已验证手机号且账号正常的有效云乐坊会员开放。「我的应用」中的 AI 网页可返回原生编辑器，服务端会先核对会员状态。可用性、项目列表、项目详情、生成、修改、发布、停用和投稿均通过 `account-api` 核对当前账号的会员有效期。发布后的作品可匿名访问。

作者登录并通过会员和手机号验证后，可以在编辑器发布作品并分享 `https://build.yunle.app/site/:id`。访客可以直接打开已发布的作品链接。送审地址为 `https://build.yunle.app/site/:id/:releaseId.html`，市场继续使用获批快照中的固定地址。

## 发布和访问

1. Apps 服务校验作者和草稿版本。腾讯文本审核通过后，将受控组件和纯文本渲染为一个 HTML 文件。
2. Apps 服务用受控的服务端凭证上传该文件到作品 Worker。每次发布按项目、草稿版本和字节摘要生成固定对象键。同一对象只能写入一次，相同字节的重试可以成功。
3. 上传完成后，Apps 在 CloudBase 事务中登记摘要和发布指针。上传失败或草稿版本已变化时，原有链接继续使用原发布状态。尚未登记的对象无公开访问入口。
4. Worker 每次访问读取公开发布清单，再直接返回 R2 中的 HTML 文件。清单只包含版本 ID 和摘要。文件目录为私有，作者停用和运营封禁会同时关闭分享地址和所有版本直链。作者重新发布会恢复以前的已发布版本。市场条目由现有后台同步暂停或下架。
5. 投稿沿用市场短名、审核队列和已批准版本指针。后台对受管作品核对作者、发布记录、固定地址和实际 HTML 响应摘要；常规应用沿用原域名和归属规则。

## 项目协作

- 所有者在「项目协作」可以邀请互关好友或生成邀请码。受邀好友在「我 → 消息」查看卡片并加入。也可从「我的网页 → 加入项目协作」输入邀请码。邀请有效期为 24 小时。卡片显示到期时间，到期后自动移除「加入项目」并显示「邀请已失效」。已加入的项目可从「我的网页」打开。
- 一个项目最多 8 人，包含所有者。每位成员都要登录有效会员账号并验证手机号。成员可查看共享草稿和项目最近 50 条聊天或修改消息，在项目聊天中发送消息或应用网页修改。首个邀请码生成前的个人提示词仅所有者可见。
- 项目编辑和成员变更通过事务保存。多个成员提交基于同一版本的修改时，先保存的修改生效，其他成员收到刷新提示并保留输入。发布、停用、投稿和管理邀请仅由所有者操作。移除成员会使当前尚未接受的邀请失效。

## 部署

- Cloudflare 保留 `yunle.app` 现有租户通配路由，用 `build.yunle.app/*` 精确路由接入 `apps/web-build-runtime/wrangler.jsonc`。在该托管账号创建私有 R2 桶 `yunle-web-build`，关闭桶的公开入口。上线前同时检查其他租户域名仍按原路由响应。
- 用同一个随机 64 位小写十六进制密钥配置 Worker 的 `WEB_BUILD_WRITE_TOKEN` 和 Apps Nitro 的 `NUXT_WEB_BUILD_WRITE_TOKEN`。作品站不承载登录、支付或 SSO，不加入 JSAPI 或跨域授信名单。HTTP 响应使用 CSP 禁止脚本、表单、外部资源和嵌入，并关闭共享缓存。
- 在目标 CloudBase 环境建立 `web_builds` 集合，应用同名 `ADMINONLY` 规则。为「我的网页」建立 `ownerUid` 升序和 `updatedAt` 降序的联合索引。后台与 Apps 服务使用同一环境。
- 上线协作前，为 `web_builds` 建立 `collaborator_updated_at` 联合索引，按顺序包含 `collaboratorUids` 升序和 `updatedAt` 降序。先部署 Apps API，再分发含协作功能的客户端。已有个人草稿在首次启用协作时补齐房间字段。
- 好友邀请使用同环境的私有 `user_notifications` 集合。先部署支持 `checkWebBuildInvitePeer` 和 `listRoomInvites.includeWebBuild` 的 account-api，再部署 Apps API。邀请仅对收件人可见，卡片显示项目标题和有效期。入房通过 Web Build API 检查身份、互关关系、邀请和名额。
- 生成端使用云乐坊 AI Runtime 的 `/ai/v1/chat`，应用 ID 为 `web-build`。配置 `NUXT_WEB_BUILD_RUNTIME_ORIGIN`，并在 Apps 和 Runtime 分别注入同一枚独立签名密钥 `NUXT_WEB_BUILD_RUNTIME_SIGNING_SECRET` 和 `WEB_BUILD_APP_SIGNING_SECRET`。Runtime 使用平台预算承担当次调用费用。账号每日限额为 8 次生成和 12 次发布审核，按上海时区计日。
- 部署托管 Worker、Apps API 和审核后台，并配置腾讯文本审核。首次开放前保持 `NUXT_WEB_BUILD_ENABLED=false`，通过 `NUXT_WEB_BUILD_PILOT_UID` 仅放行指定的已验证手机号的会员。验收登录生成、发布、获取分享链接及未登录访问已发布作品，并核对不符合资格的账号无法进入编辑器或调用创作接口。验收通过后在 Apps 生产部署中设置 `NUXT_WEB_BUILD_ENABLED=true`，清空验收账号配置。停止开放时关闭全量开关并清空验收账号配置。

## TestFlight 协作验收

使用两位已验证手机号、互相关注的有效会员。受管账号的虚拟手机号验收会话只覆盖个人网页流程。

也可使用 Admin 专门为 Web Build 准备的两个生产受管会员，通过真实用户名密码登录。Apps 服务端启用 `NUXT_WEB_BUILD_COLLABORATION_TEST_ENABLED` 并存在有效的 `synthetic_collaboration` 记录时，两号可以模拟手机号验证并在 30 分钟内互发好友邀请卡。模拟号码只存在于 Web Build 私有验收记录中。两号都须处于就绪状态并持有有效会员权益。验收账号可在配对内协作并发布测试作品，无法使用通用邀请码或向市场投稿。

1. 所有者在对话中发起网页制作，在「项目协作」向好友发送卡片。好友从「我 → 消息」核对发件人、项目标题和到期时间，再加入项目。
2. 两人核对共享聊天。好友提交网页修改后，两人都从「我的网页」重新打开项目并核对草稿。确认发布入口只对所有者显示。
3. 所有者发布并分享测试作品，用未登录窗口打开链接。验收后由所有者停用作品，并核对链接已关闭。

## 受管测试账号验收

生产会员入口关闭时，服务端可用临时验收会话为单个 `ready` 的生产受管测试账号开放生成、发布和停用。测试账号仍使用正常登录和有效会员权益。虚拟号码保存在 `web_builds` 的私有验收记录里，CloudBase 的用户资料和手机号验证结果沿用正常认证流程。

验收记录使用 `synthetic_pilot_<会话密钥的 SHA-256>` 作为文档 ID，记录 `kind: 'synthetic-pilot'`、`uid`、Admin 的 `identityId`、`virtualPhone`，以及毫秒时间戳 `issuedAt` 和 `expiresAt`。时长最多 30 分钟。虚拟号码使用 `+12025550100` 至 `+12025550199` 的保留号码段。验收程序同时发送正常 Bearer 和 `X-Yunle-Web-Build-Test-Session`。匿名验收已发布作品时不带凭据。验收后停用测试作品并将会话记录的 `expiresAt` 更新为当前时间。[NANPA 保留号码](https://nanpa.com/numbering/555-line-numbers)
