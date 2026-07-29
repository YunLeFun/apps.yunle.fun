# 个人市场与个人工坊

## 三个目录表面

| 表面     | 可见内容                               | 版本来源                                    |
| -------- | -------------------------------------- | ------------------------------------------- |
| 公共市场 | 管理员已批准并上架的公开应用           | `public_market_listings.approvedRevisionId` |
| 个人市场 | 坊主当前发布的公开应用                 | `apps.currentRevisionId`                    |
| 个人工坊 | 坊主及有效坊客可见的公开、坊客专属应用 | `apps.currentRevisionId`                    |

应用身份和当前状态只保存在 `apps`。`app_submissions` 保存不可变 revision，
`public_market_listings` 只保存公共市场审核指针，不复制名称、链接等应用资料。

## 可见范围

- `public`：个人市场可见，也可以投稿公共市场；坊客同样可见。
- `workshop`：仅坊主和有效坊客可见。
- `owner`：仅坊主自己的应用管理视图可见。

平台保护的是目录元数据与列表接口。坊客打开自定义 HTTPS URL 或纯静态站点后，
目标站点内部的鉴权由应用开发者负责。

## 加入与访问

- 个人工坊默认使用 `approval`，扫码或打开固定链接后由用户明确提交申请。
- `open` 允许获得链接的正式登录用户直接加入；启用时界面显示风险提示。
- `closed` 暂停接受新坊客。
- 策略切换不改变已有坊客状态。
- 非坊客只收到工坊名称、坊主资料、简介、状态和加入策略，不返回 App 元数据或 URL。
- 工坊停用后成员关系保留，但所有坊客暂时失去作品列表访问权。

所有工坊与成员接口都由服务端验证 CloudBase Bearer 身份。相关集合使用
`ADMINONLY`，浏览器不能直接读取或写入；成员状态与审计事件在同一事务中提交。

## 上线顺序

1. 在 `admin` 仓库执行 `pnpm provision:app-review -- --apply --confirm-env=<EnvId>`，
   创建集合、私有规则和索引。
2. 执行 `pnpm migrate:workshop-distribution` 预览迁移计划。
3. 核对预览后，再执行
   `pnpm migrate:workshop-distribution -- --apply --confirm-env=<EnvId>`。
4. 部署 `admin` 与 `apps.yunle.fun`。

资源脚本和迁移脚本默认不会写入；只有同时传入 `--apply` 和精确 EnvId 才会修改线上数据。
