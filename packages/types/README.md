# @yunlefun/types

云乐坊（Yunle.fun）跨端共享的 TypeScript 类型定义。

供 `apps.yunle.fun`（云居 App）与 `www.yunle.fun`（官网 / 支付）共用，
收敛两端都需要的核心类型：应用信息（`YlfAppInfo`）、平台账户与云币（`payment`）。

## 本地开发

apps 仓库通过 Nuxt alias 直接引用源码（`@yunlefun/types` → `packages/types/index.ts`），
无需预先构建。

## 发布

```bash
pnpm -C packages/types build   # tsc 产出 dist（js + d.ts）
cd packages/types && npm publish --access public
```

发布后，www 仓库可通过 `pnpm add @yunlefun/types` 依赖同一份类型，
消除两端类型副本漂移。
