import { randomUUID } from 'node:crypto'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ref } from 'vue'
import { useCloudbaseOAuth } from '~/composables/auth/useCloudbaseOAuth'
import { useCloudbaseOtp } from '~/composables/auth/useCloudbaseOtp'

const mocks = vi.hoisted(() => ({
  begin: vi.fn(() => ({ id: 'attempt-1' })),
  bind: vi.fn(),
  record: vi.fn(async () => {}),
  capture: vi.fn(),
  resume: vi.fn(async () => {}),
  dispose: vi.fn(),
  native: vi.fn(() => false),
  browserOpen: vi.fn(async () => {}),
}))

vi.mock('~/composables/auth/useAppsAcquisition', () => ({
  useAppsAuthAcquisition: () => ({
    beginAuthentication: mocks.begin,
    bindOAuthState: mocks.bind,
    recordAfterAuthentication: mocks.record,
    resume: mocks.resume,
    dispose: mocks.dispose,
  }),
  useAppsAcquisitionStorage: () => ({ captureEntry: mocks.capture }),
}))

vi.mock('@capacitor/core', async (importOriginal) => {
  const original = await importOriginal<typeof import('@capacitor/core')>()
  return { ...original, Capacitor: { ...original.Capacitor, isNativePlatform: mocks.native } }
})

vi.mock('@capacitor/browser', () => ({ Browser: { open: mocks.browserOpen, close: vi.fn() } }))

vi.mock('@cloudbase/js-sdk', () => ({
  default: { init: () => ({ auth: () => ({ onAuthStateChange: vi.fn() }) }) },
}))

function core() {
  const auth = {
    signInWithOtp: vi.fn(async () => ({ data: { verifyOtp: vi.fn() }, error: null })),
    signUp: vi.fn(async () => ({ data: { verifyOtp: vi.fn() }, error: null })),
    signInWithPassword: vi.fn(async () => ({ error: null })),
    signInWithOAuth: vi.fn(async () => ({ data: { url: 'https://github.com/login/oauth/authorize?state=returned-state' }, error: null })),
    grantProviderToken: vi.fn(async () => ({ provider_token: 'provider-token' })),
    signInWithIdToken: vi.fn(async () => ({ error: null })),
    linkIdentity: vi.fn(async () => ({ error: null })),
  }
  const state = {
    auth,
    loading: ref(false),
    error: ref<string | null>(null),
    user: ref({ id: 'uid-1', nickname: 'tester', login: 'tester' }),
    toast: { showSuccess: vi.fn(), showError: vi.fn() },
    router: { replace: vi.fn(async () => {}) },
    fetchUser: vi.fn(async () => ({ id: 'uid-1' })),
  }
  return { state, typed: state as unknown as ReturnType<typeof useCloudbaseAuthCore> }
}

describe('apps direct authentication acquisition hooks', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.native.mockReturnValue(false)
    mocks.record.mockResolvedValue()
  })

  it('freezes phone OTP before dispatch and records only after successful verification and user refresh', async () => {
    const { state, typed } = core()
    const otp = useCloudbaseOtp(typed)
    await otp.sendPhoneOtp('+86-test')
    expect(mocks.begin).toHaveBeenCalledWith('phone_otp')
    expect(mocks.begin.mock.invocationCallOrder[0]).toBeLessThan(state.auth.signInWithOtp.mock.invocationCallOrder[0]!)
    const verifyOtp = vi.fn(async () => ({ error: null }))
    await otp.verifyPhoneOtp({ verifyOtp } as never, 'code')
    expect(state.fetchUser).toHaveBeenCalledOnce()
    expect(mocks.record).toHaveBeenCalledOnce()
    expect(state.fetchUser.mock.invocationCallOrder[0]).toBeLessThan(mocks.record.mock.invocationCallOrder[0]!)
    expect(state.router.replace).toHaveBeenCalledWith('/tabs/me')
  })

  it('covers email OTP and explicit phone signup', async () => {
    const { typed } = core()
    const otp = useCloudbaseOtp(typed)
    await otp.sendEmailOtp('test@example.com')
    expect(mocks.begin).toHaveBeenCalledWith('email_otp')
    await otp.verifyEmailOtp({ verifyOtp: async () => ({ error: null }) } as never, 'code')
    await otp.signUpWithPhone('+86-test')
    expect(mocks.begin).toHaveBeenCalledWith('phone_otp')
    await otp.verifySignUpOtp({ verifyOtp: async () => ({ error: null }) } as never, 'code')
    expect(mocks.record).toHaveBeenCalledTimes(2)
  })

  it('does not record a failed verification', async () => {
    const { state, typed } = core()
    const otp = useCloudbaseOtp(typed)
    await expect(otp.verifyPhoneOtp({ verifyOtp: async () => ({ error: { message: 'expired' } }) } as never, 'code')).rejects.toThrow('expired')
    expect(state.fetchUser).not.toHaveBeenCalled()
    expect(mocks.record).not.toHaveBeenCalled()
  })

  // Generate a disposable value so no static credential is stored in fixtures.
  const password = ` ${randomUUID()} `

  it.each([
    [{ username: ' test ' }, { username: 'test', password }],
    [{ email: ' test@example.com ' }, { email: 'test@example.com', password }],
    [{ phone: ' +86-test ' }, { phone: '+86-test', password }],
    [{ email: ' ', phone: '', username: 'test' }, { username: 'test', password }],
  ])('forwards a valid password identifier and records its authentication attempt: %j', async (identifier, credentials) => {
    const { state, typed } = core()
    await useCloudbaseOtp(typed).signInWithPassword({ ...identifier, password })
    expect(state.auth.signInWithPassword).toHaveBeenCalledWith(credentials)
    expect(mocks.begin).toHaveBeenCalledWith('unknown')
    expect(mocks.record).toHaveBeenCalledOnce()
  })

  it.each([
    {},
    { username: '' },
    { email: ' ', phone: '\t', username: '\n' },
  ])('rejects missing or empty password identifiers before contacting auth: %j', async (identifier) => {
    const { state, typed } = core()
    await expect(useCloudbaseOtp(typed).signInWithPassword({ ...identifier, password }))
      .rejects
      .toThrow('请输入用户名、邮箱或手机号')
    expect(state.auth.signInWithPassword).not.toHaveBeenCalled()
    expect(state.fetchUser).not.toHaveBeenCalled()
    expect(mocks.begin).not.toHaveBeenCalled()
    expect(mocks.record).not.toHaveBeenCalled()
    expect(state.toast.showError).toHaveBeenCalledWith('请输入用户名、邮箱或手机号')
    expect(state.loading.value).toBe(false)
  })

  it('rejects an empty password before contacting auth', async () => {
    const { state, typed } = core()
    await expect(useCloudbaseOtp(typed).signInWithPassword({ username: 'test', password: '' }))
      .rejects
      .toThrow('请输入密码')
    expect(state.auth.signInWithPassword).not.toHaveBeenCalled()
    expect(mocks.begin).not.toHaveBeenCalled()
    expect(mocks.record).not.toHaveBeenCalled()
    expect(state.loading.value).toBe(false)
  })

  it('binds Web OAuth to the actual SDK authorization URL state before navigation', async () => {
    const { state, typed } = core()
    const assign = vi.spyOn(window.location, 'assign').mockImplementation(() => {})
    await useCloudbaseOAuth(typed).loginWithGitHub()
    expect(mocks.begin).toHaveBeenCalledWith('github', expect.stringMatching(/^apps-github_/))
    expect(state.auth.signInWithOAuth).toHaveBeenCalledWith({ provider: 'github', options: { redirectTo: `${window.location.origin}/auth/callback`, state: expect.any(String), skipBrowserRedirect: true } })
    expect(mocks.bind).toHaveBeenCalledWith('attempt-1', 'returned-state')
    expect(mocks.bind.mock.invocationCallOrder[0]).toBeLessThan(assign.mock.invocationCallOrder[0]!)
    expect(mocks.record).not.toHaveBeenCalled()
    assign.mockRestore()
  })

  it('preserves Native OAuth state and records after the native provider-token exchange', async () => {
    mocks.native.mockReturnValue(true)
    const { state, typed } = core()
    const oauth = useCloudbaseOAuth(typed)
    await oauth.loginWithWeChat()
    expect(mocks.begin).toHaveBeenCalledWith('wx_open', expect.stringMatching(/^app-wx_open_/))
    expect(mocks.browserOpen).toHaveBeenCalledOnce()
    await oauth.handleNativeOAuthCallback('code', 'app-wx_open_own')
    expect(state.auth.grantProviderToken).toHaveBeenCalledWith({ provider_id: 'wx_open', provider_redirect_uri: 'https://www.yunle.fun/auth/callback', provider_code: 'code' })
    expect(state.auth.signInWithIdToken).toHaveBeenCalledWith({ token: 'provider-token' })
    expect(mocks.record).toHaveBeenCalledWith('app-wx_open_own')
  })

  it('does not create an acquisition attempt for provider binding', async () => {
    const { typed } = core()
    await useCloudbaseOAuth(typed).linkProvider('github')
    expect(mocks.begin).not.toHaveBeenCalled()
    expect(mocks.record).not.toHaveBeenCalled()
  })
})
