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
    '@yunlefun/vue/nuxt',
    'nuxt-auth-utils',
    // '@prisma/nuxt',
    '@nuxt/test-utils/module',
    '@nuxtjs/ionic',
  ],

  css: [
    '~/styles/css/index.css',
    '~/styles/css/css-vars.css',

    '~/styles/scss/vars.scss',
    '~/styles/scss/index.scss',
    '~/styles/scss/override.scss',

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
      tailwindcss(),
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
      viewport: 'width=device-width,initial-scale=1',
      link: [
        // { rel: 'icon', href: '/favicon.ico', sizes: 'any' },
        { rel: 'icon', type: 'image/svg+xml', href: '/ylf.svg' },
        { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' },
      ],
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'description', content: appDescription },
        { name: 'apple-mobile-web-app-status-bar-style', content: 'black-translucent' },
      ],
    },
  },

  components: [
    {
      path: '~/components',
      pathPrefix: false,
    },
  ],

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
