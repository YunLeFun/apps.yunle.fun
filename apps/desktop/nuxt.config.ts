export default defineNuxtConfig({
  ssr: false,
  compatibilityDate: '2026-10-13',
  modules: ['@nuxtjs/color-mode'],
  css: ['@yunlefun/ui/css', '~/assets/main.css'],
  colorMode: { classSuffix: '' },
  devServer: { host: '127.0.0.1', port: 3000 },
  devtools: { enabled: false },
  app: {
    head: {
      title: '云乐坊',
      meta: [{ name: 'description', content: '云乐坊桌面端，发现并打开云应用' }],
    },
  },
  nitro: { prerender: { crawlLinks: false, routes: ['/', '/about'] } },
})
