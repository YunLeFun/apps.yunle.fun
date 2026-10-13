import { useStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'

export type ApiEnvironment = 'production' | 'development'

export const useDeveloperStore = defineStore('developer', () => {
  const enabled = useStorage('ylf_developer_mode', false)
  const apiEnvironment = useStorage<ApiEnvironment>('ylf_api_environment', 'production')

  function enableDevMode() {
    enabled.value = true
  }

  function disableDevMode() {
    enabled.value = false
    apiEnvironment.value = 'production'
  }

  function setApiEnvironment(env: ApiEnvironment) {
    apiEnvironment.value = env
  }

  return {
    enabled,
    apiEnvironment,
    enableDevMode,
    disableDevMode,
    setApiEnvironment,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useDeveloperStore, import.meta.hot))
