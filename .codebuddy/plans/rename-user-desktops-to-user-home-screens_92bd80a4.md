---
name: rename-user-desktops-to-user-home-screens
overview: 将 CloudBase 集合名从 `user_desktops` 重命名为 `user_home_screens`，同步更新所有代码引用、文档内容、文档文件名，以及文档中已过时的 `source` 字段和类型定义。
todos:
  - id: update-code-and-tests
    content: 修改 useHomeScreen.ts 的 COLLECTION 常量和 homeScreen.ts 注释，同步更新 useHomeScreen.test.ts 中 3 处断言的集合名为 user_home_screens
    status: completed
  - id: rename-and-rewrite-doc
    content: 重命名 user-desktops.md 为 user-home-screens.md，全面更新内容：集合名、移除 source 字段、修正类型名和文件路径
    status: completed
  - id: update-related-docs
    content: 更新 index.md、home.md、concepts.md、tabs-architecture.md 中所有 user_desktops 引用为 user_home_screens
    status: completed
    dependencies:
      - rename-and-rewrite-doc
  - id: migrate-cloudbase-data
    content: 使用 [mcp:cloudbase] 登录环境，读取 user_desktops 数据，创建 user_home_screens 集合并迁移数据、设置安全规则和索引
    status: completed
---

## 用户需求

将数据库集合名 `user_desktops` 统一重命名为 `user_home_screens`，与 iOS 术语 Home Screen 保持一致；同时更新文档中已过时的 `source` 字段和旧类型名，并完成 CloudBase 线上数据迁移。

## 产品概述

这是一次命名规范化重构，将项目中所有对 `user_desktops` 的引用（代码、测试、文档）统一更名为 `user_home_screens`，并同步更新文档中与代码实际状态不符的内容（已移除的 `source` 字段、已更名的类型定义）。同时需要在 CloudBase 线上完成集合数据迁移。

## 核心功能

1. **代码层集合名重命名** — `useHomeScreen.ts` 中的 `COLLECTION` 常量、`homeScreen.ts` 类型注释
2. **测试断言更新** — 测试文件中所有 `'user_desktops'` 字符串替换
3. **文档全面更新** — 重命名 `user-desktops.md` 为 `user-home-screens.md`，更新集合名、移除 `source` 字段、修正类型名和文件路径引用
4. **关联文档更新** — `index.md`、`home.md`、`concepts.md`、`tabs-architecture.md` 中的集合名引用
5. **CloudBase 数据迁移** — 将 `user_desktops` 集合数据迁移到 `user_home_screens` 集合，同时清理已废弃的 `source` 字段

## 技术栈

- 框架：Nuxt 4（CSR 模式）
- 数据库：腾讯 CloudBase NoSQL
- 测试：Vitest
- 数据迁移：CloudBase MCP 工具（读写 NoSQL）

## 实现方案

### 整体策略

分为三个阶段执行：

1. **代码和测试更新** — 将 `COLLECTION` 常量从 `'user_desktops'` 改为 `'user_home_screens'`，同步更新测试断言
2. **文档更新** — 重命名文档文件，全面修正内容使其与代码实际状态对齐
3. **CloudBase 数据迁移** — 通过 MCP 工具在线上创建新集合、迁移数据、设置安全规则和索引

### 关键技术决策

**集合名选择 `user_home_screens`**：与代码中已有的 `homeScreen` 命名体系完全一致（`useHomeScreenStore`、`HomeScreenGrid`、`HomeScreenDock`、`HomeScreenConfig`），且 Home Screen 是 iOS 官方术语。

**数据迁移策略**：

- 使用 CloudBase MCP 工具 `readNoSqlDatabaseContent` 读取 `user_desktops` 全量数据
- 使用 `writeNoSqlDatabaseStructure` 创建 `user_home_screens` 集合
- 使用 `writeNoSqlDatabaseContent` 写入迁移数据，同时剔除 `source` 字段（如果旧数据中存在）
- 使用 `writeSecurityRule` 为新集合设置与旧集合相同的安全规则
- 迁移完成并验证后，保留旧集合一段时间作为备份

**兼容性考虑**：代码中 `COLLECTION` 是单一常量，改动后所有读写立即指向新集合，无需渐进迁移逻辑。但需确保数据迁移在代码部署前完成。

## 实现注意事项

- `useHomeScreen.ts` 第 5 行是唯一的集合名定义点，改动后所有 `db.collection(COLLECTION)` 调用自动生效
- 测试文件中有 3 处硬编码的 `'user_desktops'` 断言字符串需同步更新
- 文档 `user-desktops.md` 需要整体重写：除集合名外，`InstalledApp.source`、`RecentApp.source` 字段需移除，`DesktopConfig` → `HomeScreenConfig`，`UserDesktopRecord` → `UserHomeScreenRecord`，文件路径 `app/types/desktop.ts` → `app/types/homeScreen.ts`
- 迁移时需注意 CloudBase `_openid` 字段的处理：`add()` 会自动注入 `_openid`，手动写入时需确保字段值正确传递
- 服务端代码（`server/` 目录）无 `user_desktops` 引用，无需修改

## 架构设计

变更影响链路清晰且范围有限：

```
app/composables/useHomeScreen.ts (COLLECTION 常量)
       ↓ 使用
app/stores/homeScreen.ts (无直接引用集合名，无需改动)
       ↓
CloudBase NoSQL: user_desktops → user_home_screens
```

## 目录结构

```
app/
├── composables/
│   └── useHomeScreen.ts          # [MODIFY] 第 5 行 COLLECTION 常量 'user_desktops' → 'user_home_screens'
├── types/
│   └── homeScreen.ts             # [MODIFY] 第 3 行和第 34 行注释中 user_desktops → user_home_screens
docs/
├── database/
│   ├── index.md                  # [MODIFY] 第 9 行集合链接和说明：user_desktops → user_home_screens
│   ├── user-desktops.md          # [DELETE] 旧文档文件
│   └── user-home-screens.md      # [NEW] 重命名后的文档，内容全面更新：集合名、移除 source 字段、修正类型名、修正文件路径
├── product/
│   ├── home.md                   # [MODIFY] 第 39 行集合名引用
│   ├── concepts.md               # [MODIFY] 第 62 行集合名引用
│   └── tabs-architecture.md      # [MODIFY] 第 10 行和第 45 行集合名引用
test/
└── unit/
    └── useHomeScreen.test.ts     # [MODIFY] 第 303、330、400 行测试断言中的集合名
```

## Agent Extensions

### MCP

- **cloudbase**
- Purpose：登录 CloudBase 环境，读取 `user_desktops` 集合结构和数据，创建 `user_home_screens` 新集合，迁移数据，设置安全规则和索引
- Expected outcome：线上 `user_home_screens` 集合创建完成，数据完整迁移（剔除废弃的 `source` 字段），安全规则和索引配置正确，与旧集合保持一致