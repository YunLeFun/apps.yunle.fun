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
      ignores: ['ios', 'android', '.codebuddy/**/*.md', 'CODEBUDDY.md'],
    },
  ),
)
