import { IonicVue } from '@ionic/vue'

export default defineNuxtPlugin((nuxtApp) => {
  nuxtApp.vueApp.use(IonicVue, { mode: 'ios', backButtonText: '返回' })
  // Ionic outlets render the matched view directly, without NuxtPage's route sync.
  nuxtApp.$router.afterEach((_to, _from, failure) => {
    if (!failure)
      nuxtApp._route.sync?.()
  })
})
