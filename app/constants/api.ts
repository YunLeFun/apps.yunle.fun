/**
 * 原生壳（Capacitor App）打包的是纯静态 Web 产物（.output/public），
 * 包内没有 Nitro server，相对路径 /api 会打到 capacitor://localhost 而失败，
 * 故 App 内默认把 API 指向产品域名 apps.yunle.fun（国内链路 EdgeOne/SCF，
 * 优于挂 Cloudflare 的 yunle.fun）。
 *
 * 注意：此地址会烧进 App 二进制陪旧版本活很多年，且 CORS preflight 不允许
 * 重定向，上架后不可更换；域名侧需把 /api/* 回源到跑 Nitro 的后端（SCF）。
 *
 * 构建时可用 NUXT_PUBLIC_API_BASE_URL 覆盖（如灰度包指向其他环境）。
 */
export const NATIVE_API_BASE_URL = 'https://apps.yunle.fun'
