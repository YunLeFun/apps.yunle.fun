import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import { defineNuxtConfig } from 'nuxt/config'
import { appDescription } from './app/constants/index'

export default defineNuxtConfig({
  ssr: false,

  alias: {
    '@yunlefun/auth': path.resolve(__dirname, './packages/auth/src/index.ts'),
  },

  devServer: {
    port: 8001,
  },

  modules: [
    '@vueuse/nuxt',
    '@unocss/nuxt',
    '@pinia/nuxt',
    '@nuxtjs/color-mode',
    // '@vite-pwa/nuxt',
    '@nuxt/eslint',
    '@nuxt/icon',
    '@yunlefun/vue/nuxt',
    'nuxt-auth-utils',
    // '@prisma/nuxt',
    '@nuxt/test-utils/module',
    '@nuxtjs/ionic',
  ],

  icon: {
    // SSR false 模式下使用 client bundle 避免网络请求
    clientBundle: {
      scan: true,
      includeCustomCollections: true,
      sizeLimitKb: 256,
    },
  },

  css: [
    '~/styles/css/index.css',
    '~/styles/css/css-vars.css',

    '~/styles/scss/vars.scss',
    '~/styles/scss/index.scss',
    '~/styles/scss/override.scss',

    /**
     * Ionic 结构样式 — large title (collapse="condense") 等组件布局所需
     * 不引入 normalize/typography 以避免和 Tailwind 冲突
     */
    '@ionic/vue/css/core.css',
    '@ionic/vue/css/structure.css',

    /**
     * ionic dark mode
     * @see https://ionicframework.com/docs/theming/dark-mode#system
     */
    '@ionic/vue/css/palettes/dark.class.css',
    '~/styles/ionic.css',
    '~/styles/konsta.css',
  ],

  vite: {
    plugins: [
      tailwindcss() as any,
    ],
  },

  colorMode: {
    preference: 'system',
    fallback: 'light',
    classPrefix: 'ion-palette-',
    classSuffix: '',
    storage: 'localStorage',
    storageKey: 'ylf-color-mode',
  },

  future: {
    compatibilityVersion: 4,
  },

  compatibilityDate: '2025-10-20',

  experimental: {
    // when using generate, payload js assets included in sw precache manifest
    // but missing on offline, disabling extraction it until fixed
    payloadExtraction: false,
    renderJsonPayloads: true,
    typedPages: true,
  },

  nitro: {
    esbuild: {
      options: {
        target: 'esnext',
      },
    },
    prerender: {
      crawlLinks: false,
      routes: ['/', '/mobile/wx/login/confirm'],
      ignore: ['/hi'],
    },
  },

  app: {
    head: {
      link: [
        // { rel: 'icon', href: '/favicon.ico', sizes: 'any' },
        { rel: 'icon', type: 'image/svg+xml', href: '/ylf.svg' },
        { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' },
      ],
      meta: [
        { name: 'viewport', content: 'viewport-fit=cover, width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no' },
        { name: 'description', content: appDescription },
        { name: 'apple-mobile-web-app-status-bar-style', content: 'black-translucent' },
      ],
    },
  },

  // pwa,

  // prisma: {
  //   generateClient: false,
  // },

  devtools: {
    enabled: true,
  },

  // Ionic uses IonRouterOutlet, disable Nuxt layouts
  dir: {
    layouts: '',
  },

  features: {
    // For UnoCSS
    inlineStyles: false,
  },

  eslint: {
    config: {
      standalone: false,
    },
  },

  ionic: {
    css: {
      basic: false,
    },
    config: {
      backButtonText: '返回',
      mode: 'ios',
    },
  },

  runtimeConfig: {
    public: {
      tcbEnvId: '',
      cloudbaseRegion: '',
      cloudbaseAccessKey: '',

      wxOpenAppId: 'wx4489293d76593a67',
      // wxOpenRedirectUri: 'https://api.yunle.fun/wx/redirect_uri',
      wxOpenRedirectUri: 'https://www.yunle.fun/login/',
    },
  },
})
