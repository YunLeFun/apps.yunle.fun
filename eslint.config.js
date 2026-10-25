// @ts-check
import antfu from '@antfu/eslint-config'
import nuxt from './apps/mobile/.nuxt/eslint.config.mjs'

export default nuxt(
  antfu(
    {
      unocss: true,
      formatters: true,
      rules: {
        'vue/no-multiple-template-root': 'off',
        'vue/no-deprecated-slot-attribute': 'off',
      },
    },
    {
      // generated.ts 由 admin gen:apps-snapshot 生成，不参与 lint；
      // scripts/*iap*.mjs 为 App Store Connect 一次性运维脚本，不受应用 lint 约束
      ignores: ['**/ios/**', '**/android/**', '**/.media/**', 'apps/macos/build/**', 'apps/macos/DerivedData/**', '.codebuddy/**/*.md', 'CODEBUDDY.md', '**/app/constants/apps/generated.ts', 'packages/app-core/src/catalog/generated.ts', 'docs/product/app-reviews-moderation.md', '**/scripts/*iap*.mjs'],
    },
    {
      files: ['apps/desktop/**'],
      rules: {
        'unocss/order': 'off',
        'unocss/order-attributify': 'off',
      },
    },
  ),
)
