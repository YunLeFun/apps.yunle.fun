import { useAppsAcquisitionStorage, useAppsAuthAcquisition } from '~/composables/auth/useAppsAcquisition'

export default defineNuxtPlugin({
  name: 'apps-acquisition',
  enforce: 'pre',
  setup(nuxtApp) {
    const storage = useAppsAcquisitionStorage()
    storage.captureEntry(new URL(window.location.href), document.referrer)
    const router = useRouter()
    router.afterEach((to) => {
      storage.captureEntry(new URL(to.fullPath, window.location.origin), '', 'navigation')
    })
    nuxtApp.hook('app:mounted', () => {
      const core = useCloudbaseAuthCore()
      const recorder = useAppsAuthAcquisition(core)
      // Auth startup may restore a session later. Watch only to deliver an already frozen task.
      const stop = watch(() => core.user.value?.id, () => {
        void recorder.resume()
      }, { immediate: true })
      const online = () => {
        void recorder.resume()
      }
      window.addEventListener('online', online)
      window.addEventListener('pagehide', (event) => {
        if (event.persisted)
          return
        recorder.dispose()
        stop()
        window.removeEventListener('online', online)
      }, { once: true })
    })
  },
})
