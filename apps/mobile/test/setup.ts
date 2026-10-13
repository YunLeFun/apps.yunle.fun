import { config } from '@vue/test-utils'
import { vi } from 'vitest'
import { computed as vueComputed, ref as vueRef } from 'vue'

// Mock Nuxt auto-imports - 使用真实的 Vue ref 和 computed
globalThis.ref = vueRef
globalThis.computed = vueComputed
globalThis.onMounted = vi.fn()
globalThis.onUnmounted = vi.fn()
globalThis.watch = vi.fn()
globalThis.watchEffect = vi.fn()

// Mock console methods
globalThis.consola = {
  log: vi.fn(),
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  success: vi.fn(),
}

// Mock CloudBase SDK
globalThis.cloudbase = {
  init: vi.fn(() => ({
    auth: vi.fn(() => ({
      getVerification: vi.fn(),
      verify: vi.fn(),
      signInWithSms: vi.fn(),
      signUp: vi.fn(),
      getLoginState: vi.fn(),
    })),
  })),
}

// Configure Vue Test Utils
config.global.mocks = {
  $api: vi.fn(),
}
