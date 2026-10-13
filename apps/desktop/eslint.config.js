import workspaceConfig from '../../eslint.config.js'

export default [
  ...await workspaceConfig,
  { ignores: ['.nuxt/**', '.output/**', 'dist-electron/**', 'out/**', 'test-results/**', 'playwright-report/**'] },
  {
    rules: {
      'unocss/order': 'off',
      'unocss/order-attributify': 'off',
    },
  },
]
