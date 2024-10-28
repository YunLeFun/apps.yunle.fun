import consola from 'consola'

export default defineNuxtPlugin((nuxtApp) => {
  const { session } = useUserSession()

  const api = $fetch.create({
    baseURL: import.meta.env.DEV ? '/api' : 'https://api.yunle.fun',
    // eslint-disable-next-line unused-imports/no-unused-vars
    onRequest({ request, options, error }) {
      if (session.value?.token) {
        // note that this relies on ofetch >= 1.4.0 - you may need to refresh your lockfile
        options.headers.set('Authorization', `Bearer ${session.value?.token}`)
      }
      if (error?.message) {
        consola.error('Request Error:', error.message)
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
