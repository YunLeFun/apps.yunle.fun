import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const browser = readFileSync(new URL('../../app/composables/useBrowser.ts', import.meta.url), 'utf8')
const contract = readFileSync(new URL('../../app/host-runtime/index.ts', import.meta.url), 'utf8')
const apiPlugin = readFileSync(new URL('../../app/plugins/api.ts', import.meta.url), 'utf8')
const loginPage = readFileSync(new URL('../../app/pages/login/index.vue', import.meta.url), 'utf8')
const userStore = readFileSync(new URL('../../app/stores/user.ts', import.meta.url), 'utf8')
const native = readFileSync(new URL('../../ios/App/App/WebViewController.swift', import.meta.url), 'utf8')
const nativePlugin = readFileSync(new URL('../../ios/App/App/InAppWebViewPlugin.swift', import.meta.url), 'utf8')
const androidPlugin = readFileSync(new URL('../../android/app/src/main/java/fun/yunle/apps/HostRuntimePlugin.kt', import.meta.url), 'utf8')
const androidWebView = readFileSync(new URL('../../android/app/src/main/java/fun/yunle/apps/HostWebViewActivity.kt', import.meta.url), 'utf8')
const androidManifest = readFileSync(new URL('../../android/app/src/main/AndroidManifest.xml', import.meta.url), 'utf8')
const androidDebugManifest = readFileSync(new URL('../../android/app/src/debug/AndroidManifest.xml', import.meta.url), 'utf8')
const manifest = JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8'))

describe('native WebView authorization boundary', () => {
  it('does not expose SSO or host credentials through window.ylf', () => {
    expect(native).not.toContain('getAuthCode')
    expect(native).not.toContain('authReady')
    expect(native).not.toContain('refreshToken')
    expect(browser).not.toContain('auth?:')
    expect(browser).not.toContain('resolveAuthContext')
    expect(contract).not.toContain('accessToken')
    expect(contract).not.toContain('refreshToken')
  })

  it('keeps the native test capability separate from the CloudBase API bearer token', () => {
    expect(userStore).toContain('NATIVE_TEST_SESSION_KEY')
    expect(userStore).toContain('nativeTestSession')
    expect(apiPlugin).toContain('userStore.accessToken')
    expect(apiPlugin).not.toContain('nativeTestSession')
    expect(apiPlugin).not.toContain('hostSession')
  })

  it('requires a leased challenge and one-time code for the native public test identity', () => {
    expect(loginPage).toContain('使用 @yunlefun 公共测试身份')
    expect(loginPage).toContain('nativeTestChallengeId')
    expect(loginPage).toContain('nativeTestCode')
    expect(loginPage).toContain('/api/auth/native-test-session/exchange')
    expect(loginPage).toContain('loginNativeTestSession(session)')
    expect(loginPage).toContain('不会获得云乐坊业务访问令牌')
    expect(loginPage).not.toContain('accessToken: session.hostSession')
  })

  it('removes the bespoke native authorization service', () => {
    expect(manifest.dependencies).not.toHaveProperty('@yunlefun/sso')
    expect(existsSync(new URL('../../server/utils/jsapi-auth.ts', import.meta.url))).toBe(false)
    expect(existsSync(new URL('../../server/api/jsapi/auth/code.post.ts', import.meta.url))).toBe(false)
    expect(existsSync(new URL('../../server/api/jsapi/auth/exchange.post.ts', import.meta.url))).toBe(false)
  })

  it('notifies kept-alive Wenta pages when the Apps identity changes', () => {
    expect(nativePlugin).toContain(`private static let identityAwareHosts: Set<String>`)
    expect(nativePlugin).toContain(`"wenta.yunle.fun"`)
    expect(nativePlugin).toContain(`return Self.identityAwareHosts.contains(host)`)
  })

  it('places the account consent prompt in the native plugin seam', () => {
    expect(contract).toContain('confirmAuthorization: (options:')
    expect(nativePlugin).toContain('CAPPluginMethod(name: "confirmAuthorization"')
    expect(nativePlugin).toContain('@objc func confirmAuthorization')
    expect(nativePlugin).toContain('UIAlertController(')
    expect(nativePlugin).toContain('call.resolve(["allowed": true, "choice": "current"])')
    expect(nativePlugin).toContain('call.resolve(["allowed": false, "choice": "cancel"])')
    expect(androidPlugin).toContain('AlertDialog.Builder(presenter)')
    expect(androidPlugin).toContain('.put("allowed", true)')
    expect(androidPlugin).toContain('.put("allowed", false)')
  })

  it('uses one protocol with platform-native adapters', () => {
    expect(contract).toContain('registerPlugin<HostRuntimePlugin>(\'HostRuntime\')')
    expect(nativePlugin).toContain('public let jsName = "HostRuntime"')
    expect(androidPlugin).toContain('@CapacitorPlugin(name = "HostRuntime")')
  })

  it('uses system authentication surfaces when another account is selected', () => {
    expect(contract).toContain('authorizeWithOtherAccount:')
    expect(nativePlugin).toContain('CAPPluginMethod(name: "authorizeWithOtherAccount"')
    expect(nativePlugin).toContain('@objc func authorizeWithOtherAccount')
    expect(nativePlugin).toContain('choice": "other"')
    expect(native).toContain('ASWebAuthenticationSession(')
    expect(androidPlugin).toContain('fun authorizeWithOtherAccount')
    expect(androidPlugin).toContain('.put("choice", "other")')
    expect(androidWebView).toContain('CustomTabsIntent.Builder()')
  })

  it('binds Android sensitive calls to an unforgeable main-frame source origin', () => {
    expect(androidWebView).toContain('WebViewCompat.addWebMessageListener(')
    expect(androidWebView).toContain('sourceOrigin: Uri')
    expect(androidWebView).toContain('isMainFrame: Boolean')
    expect(androidWebView).toContain('if (!isMainFrame)')
    expect(androidWebView).toContain('private fun isTrustedOrigin(origin: Uri)')
    expect(androidWebView).not.toContain('webView.addJavascriptInterface(')
    expect(androidWebView).not.toContain('setOf("*")')
  })

  it('disables Android cleartext traffic outside explicit debug builds', () => {
    expect(androidManifest).toContain('android:usesCleartextTraffic="false"')
    expect(androidDebugManifest).toContain('android:usesCleartextTraffic="true"')
  })

  it('keeps a native Android exit anchor until immersive chrome is implemented', () => {
    expect(androidWebView).toContain('displayMode = "titlebar"')
    expect(androidWebView).not.toContain('"setTitleBarVisible" to JsapiAccess.OPEN')
    expect(androidWebView).toContain('WindowInsetsCompat.Type.systemBars()')
  })
})
