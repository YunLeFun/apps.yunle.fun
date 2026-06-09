// @ts-check
import antfu from '@antfu/eslint-config'
import nuxt from './.nuxt/eslint.config.mjs'

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
      // generated.ts 由 admin gen:apps-snapshot 生成，不参与 lint
      ignores: ['ios', 'android', '.codebuddy/**/*.md', 'CODEBUDDY.md', 'app/constants/apps/generated.ts'],
    },
  ),
)
