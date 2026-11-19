# 工坊 AI 制作网页

创作和投稿在 iOS 工坊完成。工坊入口向已验证手机号且账号正常的有效云乐坊会员开放。「我的应用」中的 AI 网页可返回原生编辑器，服务端会先核对会员状态。可用性、项目列表、项目详情、生成、修改、发布、停用和投稿均通过 `account-api` 核对当前账号的会员有效期。发布后的作品可匿名访问。

公开分享地址为 `https://build.yunle.app/site/:id`。送审地址为 `https://build.yunle.app/site/:id/:releaseId.html`，市场继续使用获批快照中的固定地址。

## 发布和访问

1. Apps 服务校验作者和草稿版本。腾讯文本审核通过后，将受控组件和纯文本渲染为一个 HTML 文件。
2. Apps 服务用受控的服务端凭证上传该文件到作品 Worker。每次发布按项目、草稿版本和字节摘要生成固定对象键。同一对象只能写入一次，相同字节的重试可以成功。
3. 上传完成后，Apps 在 CloudBase 事务中登记摘要和发布指针。上传失败或草稿版本已变化时，原有链接继续使用原发布状态。尚未登记的对象无公开访问入口。
4. Worker 每次访问读取公开发布清单，再直接返回 R2 中的 HTML 文件。清单只包含版本 ID 和摘要。文件目录为私有，作者停用和运营封禁会同时关闭分享地址和所有版本直链。作者重新发布会恢复以前的已发布版本。市场条目由现有后台同步暂停或下架。
5. 投稿沿用市场短名、审核队列和已批准版本指针。后台对受管作品核对作者、发布记录、固定地址和实际 HTML 响应摘要；常规应用沿用原域名和归属规则。

## 部署

- Cloudflare 保留 `yunle.app` 现有租户通配路由，用 `build.yunle.app/*` 精确路由接入 `apps/web-build-runtime/wrangler.jsonc`。在该托管账号创建私有 R2 桶 `yunle-web-build`，关闭桶的公开入口。上线前同时检查其他租户域名仍按原路由响应。
- 用同一个随机 64 位小写十六进制密钥配置 Worker 的 `WEB_BUILD_WRITE_TOKEN` 和 Apps Nitro 的 `NUXT_WEB_BUILD_WRITE_TOKEN`。作品站不承载登录、支付或 SSO，不加入 JSAPI 或跨域授信名单。HTTP 响应使用 CSP 禁止脚本、表单、外部资源和嵌入，并关闭共享缓存。
- 在目标 CloudBase 环境建立 `web_builds` 集合，应用同名 `ADMINONLY` 规则。为「我的网页」建立 `ownerUid` 升序和 `updatedAt` 降序的联合索引。后台与 Apps 服务使用同一环境。
- 生成端使用云乐坊 AI Runtime 的 `/ai/v1/chat`，应用 ID 为 `web-build`。配置 `NUXT_WEB_BUILD_RUNTIME_ORIGIN`，并在 Apps 和 Runtime 分别注入同一枚独立签名密钥 `NUXT_WEB_BUILD_RUNTIME_SIGNING_SECRET` 和 `WEB_BUILD_APP_SIGNING_SECRET`。Runtime 使用平台预算承担当次调用费用。账号每日限额为 8 次生成和 12 次发布审核，按上海时区计日。
- 部署托管 Worker、Apps API 和审核后台，并配置腾讯文本审核。生产验收时保持 `NUXT_WEB_BUILD_ENABLED=false`，通过 `NUXT_WEB_BUILD_PILOT_UID` 仅放行指定的已验证手机号的会员。用该会员验收生成、发布和匿名分享，并核对访客及其他账号被拒绝。通过后开启 `NUXT_WEB_BUILD_ENABLED=true` 并清空验收账号配置。停止开放时同时关闭全量开关和清空验收账号配置。
