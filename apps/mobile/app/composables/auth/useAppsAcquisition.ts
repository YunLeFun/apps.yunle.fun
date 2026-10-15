import type { AppsAcquisitionSession } from '~/utils/apps-acquisition-recorder'
import type { AppsAcquisitionAuthMethod, AppsAcquisitionStorage } from '~/utils/apps-acquisition-storage'
import { Capacitor } from '@capacitor/core'
import { NATIVE_API_BASE_URL } from '~/constants/api'
import { createAppsAcquisitionRecorder, isTransientAppsAcquisitionError } from '~/utils/apps-acquisition-recorder'
import { createAppsAcquisitionStorage } from '~/utils/apps-acquisition-storage'
import { readNativeAuthorizationLogin } from '~/utils/native-authorization-login'

let acquisitionStorage: AppsAcquisitionStorage | undefined

/** Independent of the SSO broker: only direct Apps authentication invokes this recorder. */
export function useAppsAcquisitionStorage(): AppsAcquisitionStorage {
  if (!acquisitionStorage) {
    let local: Storage | undefined
    let session: Storage | undefined
    try {
      local = globalThis.localStorage
      session = globalThis.sessionStorage
    }
    catch {
      // Some embedded browsers deny persistent storage; use the in-memory fallback.
    }
    acquisitionStorage = createAppsAcquisitionStorage({ local, session })
  }
  return acquisitionStorage
}

type AcquisitionAuthCore = Pick<ReturnType<typeof useCloudbaseAuthCore>, 'auth' | 'user'>

export function useAppsAuthAcquisition(core: AcquisitionAuthCore) {
  const nuxtApp = useNuxtApp()
  const cached = nuxtApp._appsAuthAcquisition as ReturnType<typeof createRecorder> | undefined
  if (cached)
    return cached
  const recorder = createRecorder(core)
  nuxtApp._appsAuthAcquisition = recorder
  return recorder
}

function createRecorder(core: AcquisitionAuthCore) {
  const config = useRuntimeConfig()
  const storage = useAppsAcquisitionStorage()
  const packagedNative = import.meta.client && Capacitor.isNativePlatform() && window.location.hostname === 'localhost'
  const baseURL = config.public.apiBaseUrl || (packagedNative ? NATIVE_API_BASE_URL : undefined)
  const recorder = createAppsAcquisitionRecorder({
    storage,
    currentUserId: () => core.user.value?.id || null,
    async getSession() {
      const expectedUserId = core.user.value?.id
      const result = await core.auth.getSession()
      if (result.error && isTransientAppsAcquisitionError(result.error))
        throw result.error
      if (result.error || !result.data?.session?.access_token)
        return null
      if (!expectedUserId || expectedUserId !== core.user.value?.id)
        return null
      const session: AppsAcquisitionSession = {
        userId: expectedUserId,
        accessToken: result.data.session.access_token,
      }
      return session
    },
    async request(pending, session, signal) {
      // expectedUserId is an equality guard only. The BFF derives the write subject from this bearer.
      return await $fetch('/api/users/acquisition', {
        baseURL,
        method: 'POST',
        headers: { Authorization: `Bearer ${session.accessToken}` },
        body: { context: pending.context, authMethod: pending.authMethod, expectedUserId: pending.userId },
        signal,
        timeout: 1500,
        retry: 0,
        ignoreResponseError: true,
      })
    },
    log(outcome, attempts, statusCode) {
      // Operational counters are useful; identities, query values and raw exceptions are unnecessary.
      // eslint-disable-next-line no-console -- Structured delivery outcomes are operational telemetry.
      console.info('[acquisition]', { surface: 'apps', outcome, attempts, ...(statusCode ? { statusCode } : {}) })
    },
  })

  function beginAuthentication(authMethod: AppsAcquisitionAuthMethod, oauthState?: string) {
    const delegatedSso = Capacitor.isNativePlatform() && !!readNativeAuthorizationLogin()
    return storage.beginAuthentication(authMethod, oauthState, delegatedSso)
  }

  async function recordAfterAuthentication(oauthState?: string) {
    const userId = core.user.value?.id
    if (!userId)
      return
    storage.completeAuthentication(userId, oauthState)
    await recorder.resume()
  }

  return { beginAuthentication, bindOAuthState: storage.bindOAuthState, recordAfterAuthentication, resume: recorder.resume, dispose: recorder.dispose }
}
