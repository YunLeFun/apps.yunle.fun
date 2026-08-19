package `fun`.yunle.apps

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
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
    private lateinit var root: FrameLayout
    private lateinit var content: LinearLayout
    private lateinit var webView: WebView
    private lateinit var toolbar: LinearLayout
    private lateinit var backButton: Button
    private lateinit var titleView: TextView
    private lateinit var menuButton: Button
    private lateinit var floatingMenuButton: Button
    private lateinit var progressView: ProgressBar

    private var initialUrl = ""
    private var customTitle = ""
    private var displayMode = "titlebar"
    private var titleBarVisible = true
    private var systemBarInsets = Insets.NONE
    private var externalLinkMode = "safari-view"
    private var toolbarColor: String? = null
    private var appInfo = JSObject()
    private var extraTrustedHosts = emptySet<String>()
    private var documentStartBridgeInstalled = false
    private var localPageLaunchPending = false
    private var hostRuntimePlugin: HostRuntimePlugin? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingAuthorizations = mutableMapOf<String, PendingAuthorization>()
    private var systemAuthorization: SystemAuthorization? = null
    private var systemExternalAuthorization: SystemExternalAuthorization? = null
    private var systemAuthorizationWasPaused = false
    private var activityResumed = false
    private val resumeActions = mutableListOf<() -> Unit>()

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
        hostRuntimePlugin = HostRuntimePlugin.instance()?.also { it.attach(this) }
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
        if (systemExternalAuthorization?.requestId == requestId) systemExternalAuthorization = null
        if (error != null) {
            replyError(pending.messageId, pending.replyProxy, error)
        } else {
            replySuccess(pending.messageId, pending.replyProxy, result ?: JSObject())
        }
        return true
    }

    internal fun pauseAuthorizationTimeout(requestId: String): Boolean {
        val pending = pendingAuthorizations[requestId] ?: return false
        mainHandler.removeCallbacks(pending.timeout)
        val timeout = Runnable {
            resolveAuthorization(requestId, null, "authorization timed out")
        }
        pendingAuthorizations[requestId] = pending.copy(timeout = timeout)
        mainHandler.postDelayed(timeout, AUTHORIZATION_CONSENT_TIMEOUT_MS)
        return true
    }

    internal fun resumeAuthorizationTimeout(requestId: String): Boolean {
        val pending = pendingAuthorizations[requestId] ?: return false
        mainHandler.removeCallbacks(pending.timeout)
        val timeout = Runnable {
            resolveAuthorization(requestId, null, "authorization timed out")
        }
        pendingAuthorizations[requestId] = pending.copy(timeout = timeout)
        mainHandler.postDelayed(timeout, AUTHORIZATION_TIMEOUT_MS)
        return true
    }

    internal fun authorizationEvent(requestId: String): JSObject? {
        val pending = pendingAuthorizations[requestId] ?: return null
        return JSObject()
            .put("requestId", requestId)
            .put("sourceOrigin", pending.sourceOrigin)
            .put("appId", appInfo.getString("id") ?: "")
            .put("request", pending.request)
    }

    internal fun runWhenResumed(action: () -> Unit) {
        if (activityResumed) action() else resumeActions.add(action)
    }

    internal fun beginOtherAccountAuthorization(requestId: String): Boolean {
        if (systemAuthorization != null || systemExternalAuthorization != null) return false
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
        val external = systemExternalAuthorization
        if (external != null) {
            when (ExternalAuthProtocol.readCallback(uri.toString(), external.state)) {
                ExternalAuthProtocol.Status.SUCCESS -> resolveAuthorization(
                    external.requestId,
                    JSObject().put("ok", true).put("state", external.state),
                    null,
                )
                ExternalAuthProtocol.Status.DENIED ->
                    resolveAuthorization(external.requestId, null, "EXTERNAL_AUTH_DENIED")
                ExternalAuthProtocol.Status.ERROR ->
                    resolveAuthorization(external.requestId, null, "EXTERNAL_AUTH_FAILED")
                null -> return
            }
            return
        }
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
        webView.evaluateJavascript(
            "window.dispatchEvent(new CustomEvent('ylf:host-identity-changed'));" +
                "window.dispatchEvent(new CustomEvent('ylf:identityChanged'))",
            null,
        )
    }

    private fun readOptions(options: JSObject): Boolean {
        val url = options.getString("url")?.trim().orEmpty()
        if (!isSupportedUrl(url, isDebuggable())) return false
        initialUrl = url
        customTitle = options.getString("title") ?: ""
        // Android starts with the shared title bar. Trusted pages may request a
        // reversible immersive layout while a floating host menu remains visible.
        displayMode = "titlebar"
        titleBarVisible = true
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
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT

        root = FrameLayout(this).apply {
            setBackgroundColor(Color.WHITE)
        }
        content = LinearLayout(this).apply {
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
        menuButton = Button(this).apply {
            text = "•••"
            textSize = 17f
            contentDescription = "更多"
            isAllCaps = false
            minWidth = 0
            minHeight = 0
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { showAppMenu() }
        }
        floatingMenuButton = Button(this).apply {
            text = "•••"
            textSize = 17f
            contentDescription = "更多"
            isAllCaps = false
            minWidth = 0
            minHeight = 0
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(22).toFloat()
                setColor(Color.argb(184, 22, 25, 35))
                setStroke(dp(1), Color.argb(96, 255, 255, 255))
            }
            visibility = View.GONE
            elevation = dp(8).toFloat()
            setOnClickListener { showAppMenu() }
        }
        toolbar.addView(backButton, LinearLayout.LayoutParams(dp(56), dp(56)))
        toolbar.addView(titleView, LinearLayout.LayoutParams(0, dp(56), 1f))
        toolbar.addView(menuButton, LinearLayout.LayoutParams(dp(56), dp(56)))

        progressView = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
        }
        webView = WebView(this)

        content.addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)))
        content.addView(progressView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)))
        content.addView(webView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(
            content,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        root.addView(
            floatingMenuButton,
            FrameLayout.LayoutParams(dp(64), dp(44), Gravity.TOP or Gravity.END),
        )
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            systemBarInsets = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            applyChromeInsets()
            insets
        }
        ViewCompat.requestApplyInsets(root)
        updateNativeChrome()
    }

    private fun updateNativeChrome() {
        if (!::toolbar.isInitialized) return
        updateTitleBarVisibility()
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
        menuButton.setTextColor(foregroundColor)
    }

    private fun setTitleBarVisible(visible: Boolean) {
        if (titleBarVisible == visible) return
        titleBarVisible = visible
        updateTitleBarVisibility()
    }

    private fun updateTitleBarVisibility() {
        if (!::toolbar.isInitialized) return
        toolbar.visibility = if (titleBarVisible) View.VISIBLE else View.GONE
        floatingMenuButton.visibility = if (titleBarVisible) View.GONE else View.VISIBLE
        applyChromeInsets()
    }

    private fun applyChromeInsets() {
        if (!::content.isInitialized) return
        content.setPadding(
            if (titleBarVisible) systemBarInsets.left else 0,
            if (titleBarVisible) systemBarInsets.top else 0,
            if (titleBarVisible) systemBarInsets.right else 0,
            if (titleBarVisible) systemBarInsets.bottom else 0,
        )
        if (::floatingMenuButton.isInitialized) {
            val layout = floatingMenuButton.layoutParams as FrameLayout.LayoutParams
            layout.topMargin = systemBarInsets.top + dp(8)
            layout.rightMargin = systemBarInsets.right + dp(8)
            floatingMenuButton.layoutParams = layout
        }
    }

    private fun showAppMenu() {
        val currentUri = Uri.parse(webView.url ?: initialUrl)
        val currentUrl = currentUri.toString()
        val applicationName = appInfo.getString("name")
            ?.takeIf { it.isNotBlank() }
            ?: customTitle.ifBlank { currentUri.host ?: "云乐坊应用" }
        val applicationKey = (appInfo.getString("slug") ?: appInfo.getString("id"))
            ?.takeIf { it.isNotBlank() }
        AppMenuSheet(
            activity = this,
            content = AppMenuContent(
                applicationName = applicationName,
                applicationOrigin = exactOrigin(currentUri),
                applicationIconUrl = appInfo.getString("logo")?.takeIf { it.isNotBlank() },
                themeColor = appInfo.getString("themeColor")?.takeIf { it.isNotBlank() },
                description = appInfo.getString("description")?.takeIf { it.isNotBlank() },
                author = appInfo.getString("developer")?.takeIf { it.isNotBlank() },
                authorDisplayName = appInfo.getString("developerName")?.takeIf { it.isNotBlank() },
                detailsAvailable = applicationKey != null,
            ),
            onAction = { action ->
                when (action) {
                    AppMenuAction.DETAILS -> applicationKey?.let(::openAppDetails)
                    AppMenuAction.SHARE -> {
                        val share = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_SUBJECT, applicationName)
                            .putExtra(Intent.EXTRA_TEXT, currentUrl)
                        startActivity(Intent.createChooser(share, "分享 $applicationName"))
                    }
                    AppMenuAction.COPY_LINK -> {
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText(applicationName, currentUrl))
                        Toast.makeText(this, "链接已复制", Toast.LENGTH_SHORT).show()
                    }
                    AppMenuAction.OPEN_BROWSER -> {
                        runCatching { startActivity(Intent(Intent.ACTION_VIEW, currentUri)) }
                    }
                    AppMenuAction.RELOAD -> webView.reload()
                    AppMenuAction.END -> finish()
                }
            },
            onAuthorClick = ::openDeveloperProfile,
        ).show()
    }

    private fun openDeveloperProfile(developer: String) {
        launchLocalPage(LocalPageActivity.developerIntent(this, developer))
    }

    private fun openAppDetails(applicationKey: String) {
        launchLocalPage(LocalPageActivity.appDetailIntent(this, applicationKey, scrollToReviews = true))
    }

    private fun launchLocalPage(intent: Intent) {
        if (localPageLaunchPending) return
        localPageLaunchPending = true
        runCatching { startActivity(intent) }
            .onFailure { localPageLaunchPending = false }
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
                    .put("capsuleVisible", !titleBarVisible)
                    .put("titleBarVisible", titleBarVisible)
                    .put(
                        "safeAreaInsets",
                        safeAreaInsetsForPage(),
                    )
                    .put(
                        "capsuleRect",
                        capsuleRectForPage(),
                    ),
            )
            "setCapsuleVisible" -> replySuccess(messageId, replyProxy, JSONObject.NULL)
            "setTitleBarVisible" -> {
                setTitleBarVisible(params.getBool("visible") ?: true)
                replySuccess(messageId, replyProxy, JSONObject.NULL)
            }
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
            "haptic" -> {
                val style = params.getString("style")
                val feedback = when (style) {
                    "light" -> HapticFeedbackConstants.KEYBOARD_TAP
                    "medium" -> HapticFeedbackConstants.VIRTUAL_KEY
                    "heavy" -> HapticFeedbackConstants.LONG_PRESS
                    "success" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        HapticFeedbackConstants.CONFIRM
                    } else {
                        HapticFeedbackConstants.LONG_PRESS
                    }
                    else -> null
                }
                if (feedback == null) {
                    replyError(messageId, replyProxy, "bad request: unsupported haptic style")
                } else {
                    webView.performHapticFeedback(feedback)
                    replySuccess(messageId, replyProxy, JSONObject.NULL)
                }
            }
            "authorize" -> beginAuthorization(messageId, replyProxy, sourceOrigin, params)
            "openAuthSession" -> beginExternalAuthorization(messageId, replyProxy, sourceOrigin, params)
        }
    }

    private fun beginExternalAuthorization(
        messageId: String,
        replyProxy: JavaScriptReplyProxy,
        sourceOrigin: Uri,
        input: JSObject,
    ) {
        if (systemAuthorization != null || systemExternalAuthorization != null) {
            replyError(messageId, replyProxy, "EXTERNAL_AUTH_UNAVAILABLE")
            return
        }
        val request = ExternalAuthProtocol.readRequest(input, isDebuggable())
        if (request == null) {
            replyError(messageId, replyProxy, "EXTERNAL_AUTH_INVALID_REQUEST")
            return
        }
        val requestId = UUID.randomUUID().toString().lowercase()
        val timeout = Runnable {
            resolveAuthorization(requestId, null, "EXTERNAL_AUTH_FAILED")
        }
        pendingAuthorizations[requestId] = PendingAuthorization(
            messageId,
            replyProxy,
            timeout,
            input,
            exactOrigin(sourceOrigin),
        )
        val launched = runCatching {
            CustomTabsIntent.Builder()
                .setShowTitle(true)
                .build()
                .launchUrl(this, Uri.parse(request.url))
        }.isSuccess
        if (!launched) {
            resolveAuthorization(requestId, null, "EXTERNAL_AUTH_UNAVAILABLE")
            return
        }
        mainHandler.postDelayed(timeout, SYSTEM_AUTHORIZATION_TIMEOUT_MS)
        systemExternalAuthorization = SystemExternalAuthorization(requestId, request.state)
        systemAuthorizationWasPaused = false
    }

    private fun beginAuthorization(
        messageId: String,
        replyProxy: JavaScriptReplyProxy,
        sourceOrigin: Uri,
        request: JSObject,
    ) {
        val plugin = hostRuntimePlugin
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
            exactOrigin(sourceOrigin),
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

    private fun safeAreaInsetsForPage(): JSObject {
        val density = resources.displayMetrics.density.toDouble()
        return JSObject()
            .put("top", if (titleBarVisible) 0.0 else systemBarInsets.top / density)
            .put("bottom", if (titleBarVisible) 0.0 else systemBarInsets.bottom / density)
            .put("left", if (titleBarVisible) 0.0 else systemBarInsets.left / density)
            .put("right", if (titleBarVisible) 0.0 else systemBarInsets.right / density)
    }

    private fun capsuleRectForPage(): JSObject {
        if (titleBarVisible || !::floatingMenuButton.isInitialized) {
            return JSObject().put("x", 0).put("y", 0).put("width", 0).put("height", 0)
        }
        val density = resources.displayMetrics.density.toDouble()
        return JSObject()
            .put("x", floatingMenuButton.x / density)
            .put("y", floatingMenuButton.y / density)
            .put("width", floatingMenuButton.width / density)
            .put("height", floatingMenuButton.height / density)
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
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        proxy.postMessage(
            JSObject()
                .put("id", messageId)
                .put("ok", true)
                .put("result", result)
                .toString(),
        )
    }

    private fun replyError(messageId: String, proxy: JavaScriptReplyProxy, error: String) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
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
        systemExternalAuthorization = null
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
        activityResumed = false
        if (systemAuthorization != null || systemExternalAuthorization != null) {
            systemAuthorizationWasPaused = true
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        localPageLaunchPending = false
        activityResumed = true
        val actions = resumeActions.toList()
        resumeActions.clear()
        actions.forEach { it() }
        val active = systemAuthorization
        val external = systemExternalAuthorization
        if ((active != null || external != null) && systemAuthorizationWasPaused) {
            mainHandler.postDelayed({
                if (active != null && systemAuthorization === active) {
                    resolveAuthorization(active.requestId, null, "HOST_AUTH_DENIED")
                }
                if (external != null && systemExternalAuthorization === external) {
                    resolveAuthorization(external.requestId, null, "EXTERNAL_AUTH_CANCELLED")
                }
            }, SYSTEM_AUTHORIZATION_RETURN_GRACE_MS)
        }
    }

    override fun onDestroy() {
        cancelPendingAuthorizations("browser is gone")
        hostRuntimePlugin?.detach(this)
        hostRuntimePlugin = null
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
        val sourceOrigin: String,
    )

    private data class SystemAuthorization(
        val requestId: String,
        val state: String,
        val request: HostSsoProtocol.Request,
    )

    private data class SystemExternalAuthorization(
        val requestId: String,
        val state: String,
    )

    private enum class JsapiAccess { OPEN, TRUSTED }

    companion object {
        const val EXTRA_OPTIONS = "fun.yunle.apps.host_runtime_options"
        private const val AUTHORIZATION_TIMEOUT_MS = 30_000L
        private const val AUTHORIZATION_CONSENT_TIMEOUT_MS = 5 * 60_000L
        private const val SYSTEM_AUTHORIZATION_TIMEOUT_MS = 5 * 60_000L
        private const val SYSTEM_AUTHORIZATION_RETURN_GRACE_MS = 750L

        private val FIRST_PARTY_HOSTS = setOf("yunle.fun", "yunyoujun.cn")
        private val SECOND_LEVEL_SUFFIXES = setOf(
            "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
            "co.uk", "org.uk", "co.jp", "com.hk", "com.tw", "com.au",
        )
        private val TRUSTED_HOST_PATTERN = Regex("^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$")
        private val JSAPI_REGISTRY = mapOf(
            "canIUse" to JsapiAccess.OPEN,
            "getEnv" to JsapiAccess.OPEN,
            "setCapsuleVisible" to JsapiAccess.OPEN,
            "setTitleBarVisible" to JsapiAccess.OPEN,
            "close" to JsapiAccess.OPEN,
            "authorize" to JsapiAccess.TRUSTED,
            "openAuthSession" to JsapiAccess.TRUSTED,
            "haptic" to JsapiAccess.TRUSTED,
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
                version: 7,
                inYunleApp: true,
                invoke: invoke,
                canIUse: function (method) { return invoke('canIUse', { method: method }) },
                authorize: function (params) { return invoke('authorize', params) },
                openAuthSession: function (params) { return invoke('openAuthSession', params) },
                getEnv: function () { return invoke('getEnv') },
                hideCapsule: function () { return invoke('setCapsuleVisible', { visible: false }) },
                showCapsule: function () { return invoke('setCapsuleVisible', { visible: true }) },
                hideTitleBar: function () { return invoke('setTitleBarVisible', { visible: false }) },
                showTitleBar: function () { return invoke('setTitleBarVisible', { visible: true }) },
                closeBrowser: function () { return invoke('close') },
                haptic: function (style) { return invoke('haptic', { style: style }) },
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
