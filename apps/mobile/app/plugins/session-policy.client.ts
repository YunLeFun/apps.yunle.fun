import { hostEnvironment, HostRuntime } from '~/host-runtime'

/** Keeps the native WebView pool aligned with membership and the persisted preference. */
export default defineNuxtPlugin(() => {
  if (!hostEnvironment.isNative() || !hostEnvironment.hasRuntime())
    return

  const settingsStore = useSettingsStore()
  const { isMember } = useCoin()

  watch(
    [() => settingsStore.sessionLimitPreference, isMember],
    ([preference, member]) => {
      void HostRuntime.configureSessionPolicy({
        isMember: member,
        preferredLimit: preference === 'auto' ? undefined : preference,
      }).catch(() => {
        // Older native builds do not expose session policy configuration.
      })
    },
    { immediate: true },
  )
})
