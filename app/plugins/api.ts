export default defineNuxtPlugin((nuxtApp) => {
  const userStore = useUserStore()

  const api = $fetch.create({
    // baseURL: import.meta.env.DEV ? '/api' : 'https://api.yunle.fun',
    onRequest({ options }) {
      if (userStore.accessToken) {
        // note that this relies on ofetch >= 1.4.0 - you may need to refresh your lockfile
        options.headers.set('Authorization', `Bearer ${userStore.accessToken}`)
      }
    },
    async onResponseError({ response }) {
      if (response.status === 401) {
        await nuxtApp.runWithContext(() => navigateTo('/login'))
      }
    },
  })

  // Expose to useNuxtApp().$api
  return {
    provide: {
      api,
    },
  }
})
