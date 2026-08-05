package `fun`.yunle.apps

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.getcapacitor.JSObject
import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID

/** Android's platform-native WebView adapter for HostRuntime. */
class HostWebViewActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private lateinit var toolbar: LinearLayout
    private lateinit var backButton: Button
    private lateinit var titleView: TextView
    private lateinit var closeButton: Button
    private lateinit var progressView: ProgressBar

    private var initialUrl = ""
    private var customTitle = ""
    private var displayMode = "titlebar"
    private var externalLinkMode = "safari-view"
    private var toolbarColor: String? = null
    private var appInfo = JSObject()
    private var extraTrustedHosts = emptySet<String>()
    private var documentStartBridgeInstalled = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingAuthorizations = mutableMapOf<String, PendingAuthorization>()
    private var systemAuthorization: SystemAuthorization? = null
    private var systemAuthorizationWasPaused = false

    val sessionKey: String
        get() = appInfo.getString("id")?.takeIf { it.isNotBlank() } ?: initialUrl

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val rawOptions = intent.getStringExtra(EXTRA_OPTIONS)
        val options = runCatching { JSObject(rawOptions ?: "{}") }.getOrElse { JSObject() }
        if (!readOptions(options)) {
            finish()
            return
        }

        buildNativeChrome()
        configureWebView()
        HostRuntimePlugin.instance()?.attach(this)
        webView.loadUrl(initialUrl)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        })
    }

    /** Reuse the current Android session when HostRuntime.open is called again. */
    internal fun canReuseFor(url: String): Boolean =
        HostNavigationPolicy.hasSameOrigin(initialUrl, url, isDebuggable())

    /** Reuse the current Android session when HostRuntime.open is called again. */
    internal fun applyOptions(options: JSObject) {
        val previousUrl = initialUrl
        if (!readOptions(options)) return
        updateNativeChrome()
        if (::webView.isInitialized && previousUrl != initialUrl) webView.loadUrl(initialUrl)
    }

    internal fun updateAppInfo(patch: JSObject?) {
        if (patch == null) return
        val keys = patch.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            appInfo.put(key, patch.opt(key))
        }
    }

    internal fun sessionInfo(): JSObject = JSObject()
        .put("id", appInfo.getString("id") ?: "")
        .put("key", sessionKey)
        .put("name", appInfo.getString("name") ?: customTitle.ifBlank { initialUrl })
        .put("emoji", appInfo.getString("emoji") ?: "")
        .put("logo", appInfo.getString("logo") ?: "")
        .put("themeColor", appInfo.getString("themeColor") ?: "")
        .put("url", initialUrl)
        .put("title", customTitle)
        .put("displayMode", displayMode)

    internal fun resolveAuthorization(
        requestId: String,
        result: JSObject?,
        error: String?,
    ): Boolean {
        val pending = pendingAuthorizations.remove(requestId) ?: return false
        mainHandler.removeCallbacks(pending.timeout)
        if (systemAuthorization?.requestId == requestId) systemAuthorization = null
        if (error != null) {
            replyError(pending.messageId, pending.replyProxy, error)
        } else {
            replySuccess(pending.messageId, pending.replyProxy, result ?: JSObject())
        }
        return true
    }

    internal fun beginOtherAccountAuthorization(requestId: String): Boolean {
        if (systemAuthorization != null) return false
        val pending = pendingAuthorizations[requestId] ?: return false
        val request = readSystemAuthorizationRequest(pending.request) ?: return false
        val state = randomBase64Url()
        val authorizationUrl = runCatching {
            Uri.parse(HostSsoProtocol.buildAuthorizationUrl(request, state))
        }.getOrNull() ?: return false

        val launched = runCatching {
            CustomTabsIntent.Builder()
                .setShowTitle(true)
                .build()
                .launchUrl(this, authorizationUrl)
        }.isSuccess
        if (!launched) return false

        mainHandler.removeCallbacks(pending.timeout)
        val timeout = Runnable {
            resolveAuthorization(requestId, null, "HOST_AUTH_FAILED")
        }
        pendingAuthorizations[requestId] = pending.copy(timeout = timeout)
        mainHandler.postDelayed(timeout, SYSTEM_AUTHORIZATION_TIMEOUT_MS)
        systemAuthorization = SystemAuthorization(requestId, state, request)
        systemAuthorizationWasPaused = false
        return true
    }

    internal fun deliverSystemAuthorizationCallback(uri: Uri) {
        val active = systemAuthorization ?: return
        when (val result = HostSsoProtocol.readCallback(uri.toString(), active.state, active.request)) {
            is HostSsoProtocol.Result.Success -> resolveAuthorization(
                active.requestId,
                JSObject()
                    .put("ok", true)
                    .put("code", result.code)
                    .put("issuer", result.issuer),
                null,
            )
            HostSsoProtocol.Result.Denied ->
                resolveAuthorization(active.requestId, null, "HOST_AUTH_DENIED")
            null -> return
        }
    }

    internal fun notifyHostIdentityChanged() {
        val host = Uri.parse(webView.url ?: initialUrl).host?.lowercase()
        if (host !in IDENTITY_AWARE_HOSTS) return
        webView.evaluateJavascript(
            "window.dispatchEvent(new CustomEvent('ylf:host-identity-changed'))",
            null,
        )
    }

    private fun readOptions(options: JSObject): Boolean {
        val url = options.getString("url")?.trim().orEmpty()
        if (!isSupportedUrl(url, isDebuggable())) return false
        initialUrl = url
        customTitle = options.getString("title") ?: ""
        // Android keeps a native exit anchor until its draggable capsule reaches
        // feature parity with iOS. Pages can detect the titlebar result via getEnv.
        displayMode = "titlebar"
        externalLinkMode = options.getString("externalLinkMode")
            ?.takeIf { it == "default-browser" || it == "safari-view" }
            ?: "safari-view"
        toolbarColor = options.getString("toolbarColor")
        options.getJSObject("app")?.let { appInfo = it }

        val hosts = mutableSetOf<String>()
        val rawHosts = options.optJSONArray("trustedHosts")
        if (rawHosts != null) {
            for (index in 0 until rawHosts.length()) {
                normalizeTrustedHost(rawHosts.optString(index))?.let(hosts::add)
            }
        }
        extraTrustedHosts = hosts
        return true
    }

    private fun buildNativeChrome() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }

        toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(8), 0)
        }
        backButton = Button(this).apply {
            text = "‹"
            textSize = 28f
            contentDescription = "返回"
            minWidth = 0
            minHeight = 0
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        }
        titleView = TextView(this).apply {
            textSize = 17f
            gravity = Gravity.CENTER
            maxLines = 1
        }
        closeButton = Button(this).apply {
            text = "关闭"
            contentDescription = "关闭"
            isAllCaps = false
            minWidth = 0
            minHeight = 0
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { finish() }
        }
        toolbar.addView(backButton, LinearLayout.LayoutParams(dp(56), dp(56)))
        toolbar.addView(titleView, LinearLayout.LayoutParams(0, dp(56), 1f))
        toolbar.addView(closeButton, LinearLayout.LayoutParams(dp(64), dp(56)))

        progressView = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
        }
        webView = WebView(this)

        root.addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)))
        root.addView(progressView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)))
        root.addView(webView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            WindowInsetsCompat.CONSUMED
        }
        ViewCompat.requestApplyInsets(root)
        updateNativeChrome()
    }

    private fun updateNativeChrome() {
        if (!::toolbar.isInitialized) return
        toolbar.visibility = View.VISIBLE
        titleView.text = customTitle.ifBlank { appInfo.getString("name") ?: "云乐坊" }
        val color = parseColor(
            appInfo.getString("themeColor")
                ?: toolbarColor,
        )
        val backgroundColor = color ?: Color.WHITE
        val foregroundColor = if (ColorUtils.calculateLuminance(backgroundColor) > 0.55) {
            Color.BLACK
        } else {
            Color.WHITE
        }
        toolbar.setBackgroundColor(backgroundColor)
        backButton.setTextColor(foregroundColor)
        titleView.setTextColor(foregroundColor)
        closeButton.setTextColor(foregroundColor)
    }

    @Suppress("SetJavaScriptEnabled")
    private fun configureWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            mediaPlaybackRequiresUserGesture = true
            userAgentString = "$userAgentString YunleApp/Android"
        }
        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, false)
        }

        installSecureMessageBridge()
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressView.progress = newProgress
                progressView.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }

            override fun onReceivedTitle(view: WebView?, title: String?) {
                if (customTitle.isBlank() && !title.isNullOrBlank()) titleView.text = title
            }
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val target = request.url
                val scheme = target.scheme?.lowercase()
                if (scheme != "http" && scheme != "https") {
                    openExternal(target, true)
                    return true
                }
                if (scheme == "http" &&
                    !HostNavigationPolicy.isSupportedUrl(target.toString(), isDebuggable())
                ) {
                    openExternal(target, true)
                    return true
                }
                if (request.isForMainFrame && request.hasGesture() && isCrossSite(target)) {
                    openExternal(target, externalLinkMode == "default-browser")
                    return true
                }
                return false
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                cancelPendingAuthorizations("authorization cancelled by navigation")
            }

            override fun onPageFinished(view: WebView, url: String?) {
                if (!documentStartBridgeInstalled) view.evaluateJavascript(BRIDGE_SCRIPT, null)
            }
        }
    }

    /**
     * WebViewCompat supplies an unforgeable sourceOrigin and main-frame bit.
     * Never replace this with addJavascriptInterface: it lacks the per-message
     * origin boundary required by authorization and clipboard capabilities.
     */
    private fun installSecureMessageBridge() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        val allowedOrigins = HostNavigationPolicy.allowedOriginRules(initialUrl, isDebuggable())
        if (allowedOrigins.isEmpty()) return

        WebViewCompat.addWebMessageListener(
            webView,
            "ylfHost",
            allowedOrigins,
        ) { _, message, sourceOrigin, isMainFrame, replyProxy ->
            handleHostMessage(message, sourceOrigin, isMainFrame, replyProxy)
        }

        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(webView, BRIDGE_SCRIPT, allowedOrigins)
            documentStartBridgeInstalled = true
        }
    }

    private fun handleHostMessage(
        message: WebMessageCompat,
        sourceOrigin: Uri,
        isMainFrame: Boolean,
        replyProxy: JavaScriptReplyProxy,
    ) {
        val payload = runCatching { JSObject(message.data ?: "") }.getOrNull()
        val messageId = payload?.getString("id").orEmpty()
        if (!isMainFrame) {
            replyError(messageId, replyProxy, "forbidden: main frame only")
            return
        }
        val method = payload?.getString("method").orEmpty()
        if (messageId.isEmpty() || method.isEmpty()) {
            replyError(messageId, replyProxy, "bad request: missing method")
            return
        }

        val trusted = isTrustedOrigin(sourceOrigin)
        val access = JSAPI_REGISTRY[method]
        if (access == null) {
            replyError(messageId, replyProxy, "unknown method: $method")
            return
        }
        if (access == JsapiAccess.TRUSTED && !trusted) {
            replyError(messageId, replyProxy, "permission denied: $method requires trusted host")
            return
        }

        val params = payload?.getJSObject("params") ?: JSObject()
        when (method) {
            "canIUse" -> {
                val requestedAccess = JSAPI_REGISTRY[params.getString("method")]
                replySuccess(
                    messageId,
                    replyProxy,
                    requestedAccess == JsapiAccess.OPEN ||
                        (requestedAccess == JsapiAccess.TRUSTED && trusted),
                )
            }
            "getEnv" -> replySuccess(
                messageId,
                replyProxy,
                JSObject()
                    .put("platform", "android")
                    .put("appId", appInfo.getString("id") ?: "")
                    .put("displayMode", displayMode)
                    .put("trusted", trusted)
                    .put("capsuleVisible", false)
                    .put("titleBarVisible", true)
                    .put(
                        "safeAreaInsets",
                        JSObject().put("top", 0).put("bottom", 0).put("left", 0).put("right", 0),
                    )
                    .put(
                        "capsuleRect",
                        JSObject().put("x", 0).put("y", 0).put("width", 0).put("height", 0),
                    ),
            )
            "setCapsuleVisible" -> replySuccess(messageId, replyProxy, JSONObject.NULL)
            "close" -> {
                replySuccess(messageId, replyProxy, JSONObject.NULL)
                mainHandler.post { finish() }
            }
            "setClipboard" -> {
                val text = params.getString("text")
                if (text == null) {
                    replyError(messageId, replyProxy, "bad request: missing text")
                } else {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("云乐坊", text))
                    replySuccess(messageId, replyProxy, JSONObject.NULL)
                }
            }
            "authorize" -> beginAuthorization(messageId, replyProxy, sourceOrigin, params)
        }
    }

    private fun beginAuthorization(
        messageId: String,
        replyProxy: JavaScriptReplyProxy,
        sourceOrigin: Uri,
        request: JSObject,
    ) {
        val plugin = HostRuntimePlugin.instance()
        if (plugin == null) {
            replyError(messageId, replyProxy, "authorization broker unavailable")
            return
        }
        val requestId = UUID.randomUUID().toString().lowercase()
        val timeout = Runnable {
            resolveAuthorization(requestId, null, "authorization timed out")
        }
        pendingAuthorizations[requestId] = PendingAuthorization(
            messageId,
            replyProxy,
            timeout,
            request,
        )
        mainHandler.postDelayed(timeout, AUTHORIZATION_TIMEOUT_MS)
        plugin.requestAuthorization(
            requestId,
            exactOrigin(sourceOrigin),
            appInfo.getString("id") ?: "",
            request,
        )
    }

    private fun isTrustedOrigin(origin: Uri): Boolean {
        val host = origin.host?.lowercase() ?: return false
        val local = host == "localhost" || host == "127.0.0.1"
        if (origin.scheme?.lowercase() != "https" && !local) return false
        return (FIRST_PARTY_HOSTS + extraTrustedHosts).any {
            host == it || host.endsWith(".$it")
        }
    }

    private fun exactOrigin(origin: Uri): String {
        val scheme = origin.scheme?.lowercase() ?: "https"
        val host = origin.host?.lowercase().orEmpty()
        val port = origin.port
        val defaultPort = port == -1 || (scheme == "https" && port == 443) ||
            (scheme == "http" && port == 80)
        return "$scheme://$host${if (defaultPort) "" else ":$port"}"
    }

    private fun replySuccess(messageId: String, proxy: JavaScriptReplyProxy, result: Any) {
        proxy.postMessage(
            JSObject()
                .put("id", messageId)
                .put("ok", true)
                .put("result", result)
                .toString(),
        )
    }

    private fun replyError(messageId: String, proxy: JavaScriptReplyProxy, error: String) {
        proxy.postMessage(
            JSObject()
                .put("id", messageId)
                .put("ok", false)
                .put("error", error)
                .toString(),
        )
    }

    private fun cancelPendingAuthorizations(reason: String) {
        systemAuthorization = null
        val pending = pendingAuthorizations.values.toList()
        pendingAuthorizations.clear()
        pending.forEach {
            mainHandler.removeCallbacks(it.timeout)
            replyError(it.messageId, it.replyProxy, reason)
        }
    }

    private fun openExternal(uri: Uri, defaultBrowser: Boolean) {
        runCatching {
            if (defaultBrowser || (uri.scheme != "http" && uri.scheme != "https")) {
                startActivity(Intent(Intent.ACTION_VIEW, uri))
            } else {
                CustomTabsIntent.Builder().build().launchUrl(this, uri)
            }
        }
    }

    private fun isCrossSite(target: Uri): Boolean {
        val targetHost = target.host?.lowercase() ?: return false
        val appHost = Uri.parse(initialUrl).host?.lowercase() ?: return false
        return registrableDomain(targetHost) != registrableDomain(appHost)
    }

    private fun registrableDomain(host: String): String {
        val labels = host.split('.')
        if (labels.size <= 2) return host
        val lastTwo = labels.takeLast(2).joinToString(".")
        val count = if (lastTwo in SECOND_LEVEL_SUFFIXES) 3 else 2
        return labels.takeLast(count).joinToString(".")
    }

    private fun normalizeTrustedHost(raw: String?): String? {
        val host = raw?.trim()?.trim('.')?.lowercase().orEmpty()
        if (host.isEmpty() || host.contains('/') || host.contains(':')) return null
        return host.takeIf { TRUSTED_HOST_PATTERN.matches(it) }
    }

    private fun parseColor(raw: String?): Int? = runCatching {
        raw?.takeIf { it.startsWith('#') }?.let(Color::parseColor)
    }.getOrNull()

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun isDebuggable(): Boolean =
        applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    override fun onPause() {
        if (systemAuthorization != null) systemAuthorizationWasPaused = true
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        val active = systemAuthorization
        if (active != null && systemAuthorizationWasPaused) {
            mainHandler.postDelayed({
                if (systemAuthorization === active) {
                    resolveAuthorization(active.requestId, null, "HOST_AUTH_DENIED")
                }
            }, SYSTEM_AUTHORIZATION_RETURN_GRACE_MS)
        }
    }

    override fun onDestroy() {
        cancelPendingAuthorizations("browser is gone")
        HostRuntimePlugin.instance()?.detach(this)
        if (::webView.isInitialized) {
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }

    private data class PendingAuthorization(
        val messageId: String,
        val replyProxy: JavaScriptReplyProxy,
        val timeout: Runnable,
        val request: JSObject,
    )

    private data class SystemAuthorization(
        val requestId: String,
        val state: String,
        val request: HostSsoProtocol.Request,
    )

    private enum class JsapiAccess { OPEN, TRUSTED }

    companion object {
        const val EXTRA_OPTIONS = "fun.yunle.apps.host_runtime_options"
        private const val AUTHORIZATION_TIMEOUT_MS = 30_000L
        private const val SYSTEM_AUTHORIZATION_TIMEOUT_MS = 5 * 60_000L
        private const val SYSTEM_AUTHORIZATION_RETURN_GRACE_MS = 750L

        private val FIRST_PARTY_HOSTS = setOf("yunle.fun", "yunyoujun.cn")
        private val IDENTITY_AWARE_HOSTS = setOf(
            "play.yunle.fun",
            "cms.yunle.fun",
            "wenta.yunle.fun",
        )
        private val SECOND_LEVEL_SUFFIXES = setOf(
            "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
            "co.uk", "org.uk", "co.jp", "com.hk", "com.tw", "com.au",
        )
        private val TRUSTED_HOST_PATTERN = Regex("^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$")
        private val JSAPI_REGISTRY = mapOf(
            "canIUse" to JsapiAccess.OPEN,
            "getEnv" to JsapiAccess.OPEN,
            "setCapsuleVisible" to JsapiAccess.OPEN,
            "close" to JsapiAccess.OPEN,
            "authorize" to JsapiAccess.TRUSTED,
            "setClipboard" to JsapiAccess.TRUSTED,
        )

        private val BRIDGE_SCRIPT = """
            (function () {
              if (window.top !== window || window.ylf || !window.ylfHost) { return }
              var pending = Object.create(null)
              var sequence = 0
              window.ylfHost.onmessage = function (event) {
                var response
                try { response = JSON.parse(event.data) } catch (_) { return }
                var callback = pending[response.id]
                if (!callback) { return }
                delete pending[response.id]
                if (response.ok) { callback.resolve(response.result) }
                else { callback.reject(new Error(response.error || 'host call failed')) }
              }
              function invoke(method, params) {
                return new Promise(function (resolve, reject) {
                  var id = String(++sequence) + '-' + String(Date.now())
                  pending[id] = { resolve: resolve, reject: reject }
                  window.ylfHost.postMessage(JSON.stringify({
                    id: id,
                    method: method,
                    params: params || {}
                  }))
                })
              }
              window.ylf = {
                version: 5,
                inYunleApp: true,
                invoke: invoke,
                canIUse: function (method) { return invoke('canIUse', { method: method }) },
                authorize: function (params) { return invoke('authorize', params) },
                getEnv: function () { return invoke('getEnv') },
                hideCapsule: function () { return invoke('setCapsuleVisible', { visible: false }) },
                showCapsule: function () { return invoke('setCapsuleVisible', { visible: true }) },
                hideTitleBar: function () { return invoke('setTitleBarVisible', { visible: false }) },
                showTitleBar: function () { return invoke('setTitleBarVisible', { visible: true }) },
                closeBrowser: function () { return invoke('close') },
                setClipboard: function (text) { return invoke('setClipboard', { text: text }) }
              }
            })()
        """.trimIndent()

        fun isSupportedUrl(raw: String, allowLocalHttp: Boolean = false): Boolean =
            HostNavigationPolicy.isSupportedUrl(raw, allowLocalHttp)
    }

    private fun readSystemAuthorizationRequest(request: JSObject): HostSsoProtocol.Request? {
        val scopes = request.optJSONArray("scope") ?: return null
        if (scopes.length() != 1) return null
        return HostSsoProtocol.Request(
            clientId = request.getString("clientId") ?: return null,
            codeChallenge = request.getString("codeChallenge") ?: return null,
            nonce = request.getString("nonce") ?: return null,
            redirectUri = request.getString("redirectUri") ?: return null,
            scope = scopes.optString(0),
        )
    }

    private fun randomBase64Url(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}
