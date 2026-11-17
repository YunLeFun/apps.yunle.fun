package `fun`.yunle.apps

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
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
import androidx.lifecycle.lifecycleScope
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.google.android.material.button.MaterialButton
import com.google.android.material.color.MaterialColors
import `fun`.yunle.apps.account.AccountRequestBoundary
import `fun`.yunle.apps.webruntime.HostAuthorizationException
import `fun`.yunle.apps.webruntime.HostSsoRequest
import `fun`.yunle.apps.webruntime.NativeAuthorizationSheet
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID

/** Android's platform-native WebView adapter for HostRuntime. */
class HostWebViewActivity : AppCompatActivity() {
    private lateinit var root: FrameLayout
    private lateinit var content: LinearLayout
    private lateinit var webContainer: FrameLayout
    private var webView: WebView? = null
    private lateinit var recoveryView: LinearLayout
    private lateinit var recoveryTitleView: TextView
    private lateinit var recoveryMessageView: TextView
    private lateinit var recoveryRetryButton: MaterialButton
    private lateinit var toolbar: FrameLayout
    private lateinit var minimizeButton: ImageButton
    private lateinit var backButton: ImageButton
    private lateinit var titleView: TextView
    private lateinit var menuButton: ImageButton
    private lateinit var floatingMenuButton: ImageButton
    private lateinit var floatingMinimizeButton: ImageButton
    private lateinit var progressView: ProgressBar

    private var initialUrl = ""
    private var customTitle = ""
    private var displayMode = "titlebar"
    private var titleBarVisible = true
    private var capsuleVisible = true
    private var systemBarInsets = Insets.NONE
    private var externalLinkMode = "safari-view"
    private var toolbarColor: String? = null
    private var appInfo = JSONObject()
    private var extraTrustedHosts = emptySet<String>()
    private var documentStartBridgeInstalled = false
    private var localPageLaunchPending = false
    private lateinit var accountBoundary: AccountRequestBoundary

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingAuthorizations = mutableMapOf<String, PendingAuthorization>()
    private var systemAuthorization: SystemAuthorization? = null
    private var systemExternalAuthorization: SystemExternalAuthorization? = null
    private var systemAuthorizationWasPaused = false

    val sessionKey: String
        get() = appInfo.readString("id")?.takeIf { it.isNotBlank() } ?: initialUrl

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val rawOptions = intent.getStringExtra(EXTRA_OPTIONS)
        val options = runCatching { JSONObject(rawOptions ?: "{}") }.getOrElse { JSONObject() }
        if (!readOptions(options)) {
            finish()
            return
        }

        YunleContainer.ensureInitialized(this)
        accountBoundary = YunleContainer.accounts.currentBoundary
        buildNativeChrome()
        attachFreshWebView(initialUrl)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                val activeWeb = webView
                if (activeWeb != null && activeWeb.canGoBack()) activeWeb.goBack() else finish()
            }
        })
    }

    /** Return to the native catalog while retaining this cloud app. */
    private fun minimize() {
        if (webView == null) {
            finish()
            return
        }
        HostSession.minimized(this)
        startActivity(Intent(this, MainActivity::class.java).addFlags(
            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP,
        ))
    }

    internal fun sessionName(): String = appInfo.readString("name") ?: customTitle.ifBlank { initialUrl }

    internal fun matchesSession(app: CatalogApp): Boolean = sessionKey == app.id &&
        initialUrl == app.launchUrl && accountBoundary == YunleContainer.accounts.currentBoundary

    internal fun resolveAuthorization(
        requestId: String,
        result: JSONObject?,
        error: String?,
    ): Boolean {
        val pending = pendingAuthorizations.remove(requestId) ?: return false
        mainHandler.removeCallbacks(pending.timeout)
        if (systemAuthorization?.requestId == requestId) systemAuthorization = null
        if (systemExternalAuthorization?.requestId == requestId) systemExternalAuthorization = null
        if (error != null) {
            replyError(pending.messageId, pending.replyProxy, error)
        } else {
            replySuccess(pending.messageId, pending.replyProxy, result ?: JSONObject())
        }
        return true
    }

    private fun beginSystemAuthorization(requestId: String): Boolean {
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
                    JSONObject().put("ok", true).put("state", external.state),
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
                JSONObject()
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

    private fun readOptions(options: JSONObject): Boolean {
        val url = options.readString("url")?.trim().orEmpty()
        if (!isSupportedUrl(url, isDebuggable())) return false
        initialUrl = url
        customTitle = options.readString("title") ?: ""
        // Android starts with the shared title bar. Trusted pages may request a
        // reversible immersive layout while a floating host menu remains visible.
        displayMode = "titlebar"
        titleBarVisible = true
        capsuleVisible = true
        externalLinkMode = options.readString("externalLinkMode")
            ?.takeIf { it == "default-browser" || it == "safari-view" }
            ?: "safari-view"
        toolbarColor = options.readString("toolbarColor")
        options.optJSONObject("app")?.let { appInfo = it }

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

        toolbar = FrameLayout(this).apply {
            setPadding(dp(8), 0, dp(8), 0)
        }
        backButton = chromeIconButton(R.drawable.ic_host_arrow_back, "返回").apply {
            setOnClickListener {
                val activeWeb = webView
                if (activeWeb != null && activeWeb.canGoBack()) activeWeb.goBack() else finish()
            }
        }
        titleView = TextView(this).apply {
            textSize = 17f
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        menuButton = chromeIconButton(R.drawable.ic_host_more_vert, "更多").apply {
            setOnClickListener { showAppMenu() }
        }
        floatingMenuButton = chromeIconButton(R.drawable.ic_host_more_vert, "更多").apply {
            imageTintList = ColorStateList.valueOf(Color.WHITE)
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
        minimizeButton = chromeIconButton(R.drawable.ic_host_minimize, "收起应用").apply {
            setOnClickListener { minimize() }
        }
        // Equal insets center the title in the whole bar and prevent action overlap.
        toolbar.addView(titleView, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
        ).apply {
            marginStart = dp(96)
            marginEnd = dp(96)
        })
        toolbar.addView(minimizeButton, FrameLayout.LayoutParams(
            dp(48), dp(48), Gravity.START or Gravity.CENTER_VERTICAL,
        ))
        toolbar.addView(backButton, FrameLayout.LayoutParams(
            dp(48), dp(48), Gravity.START or Gravity.CENTER_VERTICAL,
        ).apply { marginStart = dp(48) })
        toolbar.addView(menuButton, FrameLayout.LayoutParams(
            dp(48), dp(48), Gravity.END or Gravity.CENTER_VERTICAL,
        ))

        progressView = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
        }
        webContainer = FrameLayout(this)
        recoveryView = buildRecoveryView()
        webContainer.addView(
            recoveryView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        content.addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)))
        content.addView(progressView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)))
        content.addView(webContainer, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(
            content,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        root.addView(
            floatingMenuButton,
            FrameLayout.LayoutParams(dp(64), dp(48), Gravity.TOP or Gravity.END),
        )
        floatingMinimizeButton = chromeIconButton(R.drawable.ic_host_minimize, "收起应用").apply {
            imageTintList = ColorStateList.valueOf(Color.WHITE)
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.argb(184, 22, 25, 35))
            }
            setOnClickListener { minimize() }
        }
        root.addView(floatingMinimizeButton,
            FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.START))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            systemBarInsets = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            applyChromeInsets()
            insets
        }
        ViewCompat.requestApplyInsets(root)
        updateNativeChrome()
    }

    private fun chromeIconButton(icon: Int, description: String): ImageButton =
        ImageButton(this).apply {
            setImageResource(icon)
            scaleType = ImageView.ScaleType.CENTER
            setPadding(0, 0, 0, 0)
            contentDescription = description
            val ripple = TypedValue()
            theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, ripple, true)
            setBackgroundResource(ripple.resourceId)
        }

    private fun updateNativeChrome() {
        if (!::toolbar.isInitialized) return
        updateTitleBarVisibility()
        titleView.text = customTitle.ifBlank { appInfo.readString("name") ?: "云乐坊" }
        val color = parseColor(
            appInfo.readString("themeColor")
                ?: toolbarColor,
        )
        val backgroundColor = color ?: Color.WHITE
        val foregroundColor = if (ColorUtils.calculateLuminance(backgroundColor) > 0.55) {
            Color.BLACK
        } else {
            Color.WHITE
        }
        toolbar.setBackgroundColor(backgroundColor)
        minimizeButton.imageTintList = ColorStateList.valueOf(foregroundColor)
        backButton.imageTintList = ColorStateList.valueOf(foregroundColor)
        titleView.setTextColor(foregroundColor)
        menuButton.imageTintList = ColorStateList.valueOf(foregroundColor)
    }

    private fun setTitleBarVisible(visible: Boolean) {
        if (titleBarVisible == visible) return
        titleBarVisible = visible
        updateTitleBarVisibility()
    }

    private fun updateTitleBarVisibility() {
        if (!::toolbar.isInitialized) return
        toolbar.visibility = if (titleBarVisible) View.VISIBLE else View.GONE
        val showFloating = !titleBarVisible && capsuleVisible
        floatingMenuButton.visibility = if (showFloating) View.VISIBLE else View.GONE
        floatingMinimizeButton.visibility = if (showFloating) View.VISIBLE else View.GONE
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
        if (::floatingMinimizeButton.isInitialized) {
            val layout = floatingMinimizeButton.layoutParams as FrameLayout.LayoutParams
            layout.topMargin = systemBarInsets.top + dp(8)
            layout.leftMargin = systemBarInsets.left + dp(8)
            floatingMinimizeButton.layoutParams = layout
        }
        if (::floatingMenuButton.isInitialized) {
            val layout = floatingMenuButton.layoutParams as FrameLayout.LayoutParams
            layout.topMargin = systemBarInsets.top + dp(8)
            layout.rightMargin = systemBarInsets.right + dp(8)
            floatingMenuButton.layoutParams = layout
        }
    }

    private fun showAppMenu() {
        val currentUri = Uri.parse(webView?.url ?: initialUrl)
        val currentUrl = currentUri.toString()
        val applicationName = appInfo.readString("name")
            ?.takeIf { it.isNotBlank() }
            ?: customTitle.ifBlank { currentUri.host ?: "云乐坊应用" }
        val applicationKey = (appInfo.readString("slug") ?: appInfo.readString("id"))
            ?.takeIf { it.isNotBlank() }
        AppMenuSheet(
            activity = this,
            content = AppMenuContent(
                applicationName = applicationName,
                applicationOrigin = exactOrigin(currentUri),
                applicationIconUrl = appInfo.readString("logo")?.takeIf { it.isNotBlank() },
                themeColor = appInfo.readString("themeColor")?.takeIf { it.isNotBlank() },
                description = appInfo.readString("description")?.takeIf { it.isNotBlank() },
                author = appInfo.readString("developer")?.takeIf { it.isNotBlank() },
                authorDisplayName = appInfo.readString("developerName")?.takeIf { it.isNotBlank() },
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
                    AppMenuAction.RELOAD -> webView?.reload() ?: reopenAfterTermination()
                    AppMenuAction.END -> finish()
                }
            },
            onAuthorClick = ::openDeveloperProfile,
        ).show()
    }

    private fun openDeveloperProfile(developer: String) {
        openInCustomTab(this, Uri.Builder().scheme("https").authority("www.yunle.fun").appendPath("u").appendPath(developer).build())
    }

    private fun openAppDetails(applicationKey: String) {
        launchLocalPage(MainActivity.detailIntent(this, applicationKey))
    }

    private fun launchLocalPage(intent: Intent) {
        if (localPageLaunchPending) return
        localPageLaunchPending = true
        runCatching { startActivity(intent) }
            .onFailure { localPageLaunchPending = false }
    }

    private fun buildRecoveryView(): LinearLayout {
        val surface = MaterialColors.getColor(this, com.google.android.material.R.attr.colorSurface, Color.WHITE)
        val onSurface = MaterialColors.getColor(this, com.google.android.material.R.attr.colorOnSurface, Color.BLACK)
        val onSurfaceVariant = MaterialColors.getColor(
            this,
            com.google.android.material.R.attr.colorOnSurfaceVariant,
            Color.DKGRAY,
        )
        val primary = MaterialColors.getColor(this, com.google.android.material.R.attr.colorPrimary, Color.BLUE)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(surface)
            visibility = View.GONE
        }
        recoveryTitleView = TextView(this).apply {
            textSize = 20f
            gravity = Gravity.CENTER
            setTextColor(onSurface)
            ViewCompat.setAccessibilityHeading(this, true)
        }
        recoveryMessageView = TextView(this).apply {
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(onSurfaceVariant)
            setPadding(0, dp(10), 0, dp(20))
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        recoveryRetryButton = MaterialButton(this).apply {
            text = "重新打开"
            minimumHeight = dp(48)
            setOnClickListener { reopenAfterTermination() }
        }
        val backToCatalogButton = MaterialButton(
            this,
            null,
            com.google.android.material.R.attr.materialButtonOutlinedStyle,
        ).apply {
            text = "返回目录"
            minimumHeight = dp(48)
            setTextColor(ColorStateList.valueOf(primary))
            setOnClickListener { finish() }
        }
        actions.addView(backToCatalogButton, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { marginEnd = dp(12) })
        actions.addView(recoveryRetryButton, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
        container.addView(recoveryTitleView)
        container.addView(recoveryMessageView)
        container.addView(actions)
        return container
    }

    private fun attachFreshWebView(url: String) {
        if (isFinishing || isDestroyed) return
        teardownWebView()
        recoveryView.visibility = View.GONE

        if (accountBoundary != YunleContainer.accounts.currentBoundary) {
            showWebViewRecovery("账号已切换", "请返回目录，在当前账号下重新打开云应用。", canRetry = false)
            return
        }
        val supportsProfiles = runCatching { WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) }
            .getOrDefault(false)
        if (!supportsProfiles) {
            showWebViewRecovery("当前 WebView 版本无法打开云应用", "请更新 Android System WebView 后从目录重试。", canRetry = false)
            return
        }

        var pendingView: WebView? = null
        val created = try {
            val selection = YunleContainer.selectWebProfile(appInfo.readString("id").orEmpty(), url)
            WebView(this).also { view ->
                pendingView = view
                // Bind before configuring or loading anything. The default profile belongs to the old shell.
                WebViewCompat.setProfile(view, selection.profileName)
                val profile = WebViewCompat.getProfile(view)
                check(profile.name == selection.profileName)
                configureWebView(view, profile.cookieManager)
            }
        } catch (_: Exception) {
            pendingView?.destroy()
            showWebViewRecovery("暂时无法打开云应用", "无法打开此应用的独立存储，请重试或返回目录。")
            return
        }
        webView = created
        webContainer.addView(
            created,
            0,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        HostSession.attach(this)
        created.loadUrl(url)
    }

    private fun teardownWebView() {
        documentStartBridgeInstalled = false
        val active = webView ?: return
        webView = null
        (active.parent as? ViewGroup)?.removeView(active)
        runCatching { active.stopLoading() }
        active.destroy()
    }

    private fun reopenAfterTermination() {
        updateNativeChrome()
        attachFreshWebView(initialUrl)
    }

    internal fun handleRenderProcessGone(didCrash: Boolean) {
        if (isFinishing || isDestroyed) return
        val wasMinimized = HostSession.isMinimized(this)
        cancelPendingAuthorizations("web render process terminated")
        teardownWebView()
        if (wasMinimized) {
            HostSession.detach(this)
            finish()
            return
        }
        showWebViewRecovery(
            if (didCrash) "应用页面意外退出" else "应用页面已停止运行",
            "当前云应用渲染进程已退出，旧会话已清理。你可以重新打开应用或返回目录。",
        )
    }

    private fun showWebViewRecovery(title: String, message: String, canRetry: Boolean = true) {
        HostSession.detach(this)
        progressView.progress = 0
        progressView.visibility = View.GONE
        setTitleBarVisible(true)
        recoveryTitleView.text = title
        recoveryMessageView.text = message
        recoveryRetryButton.visibility = if (canRetry) View.VISIBLE else View.GONE
        recoveryView.visibility = View.VISIBLE
    }

    @Suppress("SetJavaScriptEnabled")
    private fun configureWebView(targetWebView: WebView, cookieManager: CookieManager) {
        targetWebView.settings.apply {
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
        cookieManager.apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(targetWebView, false)
        }

        installSecureMessageBridge(targetWebView)
        targetWebView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                if (view !== webView) return
                progressView.progress = newProgress
                progressView.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }

            override fun onReceivedTitle(view: WebView?, title: String?) {
                if (view !== webView) return
                if (customTitle.isBlank() && !title.isNullOrBlank()) titleView.text = title
            }
        }
        targetWebView.webViewClient = object : WebViewClient() {
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
                if (view !== webView) return
                cancelPendingAuthorizations("authorization cancelled by navigation")
            }

            override fun onPageFinished(view: WebView, url: String?) {
                if (view !== webView) return
                if (!documentStartBridgeInstalled) view.evaluateJavascript(BRIDGE_SCRIPT, null)
            }

            override fun onRenderProcessGone(
                view: WebView,
                detail: RenderProcessGoneDetail,
            ): Boolean {
                if (view !== webView || isFinishing || isDestroyed) return true
                handleRenderProcessGone(detail.didCrash())
                return true
            }
        }
    }

    /**
     * WebViewCompat supplies an unforgeable sourceOrigin and main-frame bit.
     * Never replace this with addJavascriptInterface: it lacks the per-message
     * origin boundary required by authorization and clipboard capabilities.
     */
    private fun installSecureMessageBridge(targetWebView: WebView) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        val allowedOrigins = HostNavigationPolicy.allowedOriginRules(initialUrl, isDebuggable())
        if (allowedOrigins.isEmpty()) return

        WebViewCompat.addWebMessageListener(
            targetWebView,
            "ylfHost",
            allowedOrigins,
        ) { _, message, sourceOrigin, isMainFrame, replyProxy ->
            handleHostMessage(message, sourceOrigin, isMainFrame, replyProxy)
        }

        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(targetWebView, BRIDGE_SCRIPT, allowedOrigins)
            documentStartBridgeInstalled = true
        }
    }

    private fun handleHostMessage(
        message: WebMessageCompat,
        sourceOrigin: Uri,
        isMainFrame: Boolean,
        replyProxy: JavaScriptReplyProxy,
    ) {
        val payload = runCatching { JSONObject(message.data ?: "") }.getOrNull()
        val messageId = payload?.readString("id").orEmpty()
        if (!isMainFrame) {
            replyError(messageId, replyProxy, "forbidden: main frame only")
            return
        }
        val method = payload?.readString("method").orEmpty()
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

        val params = payload?.optJSONObject("params") ?: JSONObject()
        when (method) {
            "canIUse" -> {
                val requestedAccess = JSAPI_REGISTRY[params.readString("method")]
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
                JSONObject()
                    .put("platform", "android")
                    .put("appId", (appInfo.readString("id") ?: appInfo.readString("slug")).orEmpty())
                    .put("displayMode", displayMode)
                    .put("trusted", trusted)
                    .put("capsuleVisible", !titleBarVisible && capsuleVisible)
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
            "setCapsuleVisible" -> {
                capsuleVisible = params.opt("visible") as? Boolean ?: true
                updateTitleBarVisibility()
                replySuccess(messageId, replyProxy, JSONObject.NULL)
            }
            "setTitleBarVisible" -> {
                setTitleBarVisible(params.opt("visible") as? Boolean ?: true)
                replySuccess(messageId, replyProxy, JSONObject.NULL)
            }
            "close" -> {
                replySuccess(messageId, replyProxy, JSONObject.NULL)
                mainHandler.post { finish() }
            }
            "setClipboard" -> {
                val text = params.readString("text")
                if (text == null) {
                    replyError(messageId, replyProxy, "bad request: missing text")
                } else {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("云乐坊", text))
                    replySuccess(messageId, replyProxy, JSONObject.NULL)
                }
            }
            "haptic" -> {
                val style = params.readString("style")
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
                    (webView ?: root).performHapticFeedback(feedback)
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
        input: JSONObject,
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
        request: JSONObject,
    ) {
        val redirect = request.readString("redirectUri")?.let(Uri::parse)
        if (redirect == null || exactOrigin(redirect) != exactOrigin(sourceOrigin)) {
            replyError(messageId, replyProxy, "HOST_AUTH_INVALID_REQUEST")
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
        YunleContainer.ensureInitialized(this)
        val activeUser = YunleContainer.accounts.user?.takeIf { it.isUsable }
        val originStr = exactOrigin(sourceOrigin)
        if (activeUser != null) {
            val ssoRequest = try {
                HostSsoRequest.parse(originStr, request)
            } catch (e: HostAuthorizationException) {
                resolveAuthorization(requestId, null, e.error.code)
                return
            }
            val boundGeneration = YunleContainer.accounts.identityGeneration.value
            lifecycleScope.launch {
                val policy = try {
                    YunleContainer.hostAuthService.resolve(ssoRequest)
                } catch (e: HostAuthorizationException) {
                    if (!pendingAuthorizations.containsKey(requestId)) return@launch
                    resolveAuthorization(requestId, null, e.error.code)
                    return@launch
                }
                if (!pendingAuthorizations.containsKey(requestId) || isFinishing || isDestroyed) return@launch
                val currentUser = YunleContainer.accounts.user?.takeIf { it.isUsable }
                if (currentUser == null ||
                    currentUser.id != activeUser.id ||
                    YunleContainer.accounts.identityGeneration.value != boundGeneration
                ) {
                    resolveAuthorization(requestId, null, "HOST_AUTH_FAILED")
                    return@launch
                }
                NativeAuthorizationSheet.show(
                    activity = this@HostWebViewActivity,
                    policy = policy,
                    user = currentUser,
                    onConfirm = {
                        lifecycleScope.launch {
                            try {
                                if (YunleContainer.accounts.identityGeneration.value != boundGeneration ||
                                    YunleContainer.accounts.user?.id != currentUser.id
                                ) {
                                    resolveAuthorization(requestId, null, "HOST_AUTH_FAILED")
                                    return@launch
                                }
                                val identity = YunleContainer.accounts.authorization(forceRefresh = false)
                                val issued = YunleContainer.hostAuthService.issue(ssoRequest, identity)
                                resolveAuthorization(requestId, issued.toPageResult(), null)
                            } catch (e: HostAuthorizationException) {
                                resolveAuthorization(requestId, null, e.error.code)
                            } catch (_: Throwable) {
                                resolveAuthorization(requestId, null, "HOST_AUTH_FAILED")
                            }
                        }
                    },
                    onSwitchViaBrowser = {
                        if (!beginSystemAuthorization(requestId)) {
                            resolveAuthorization(requestId, null, "HOST_AUTH_FAILED")
                        }
                    },
                    onCancel = {
                        resolveAuthorization(requestId, null, "HOST_AUTH_DENIED")
                    },
                )
            }
            return
        }
        if (!beginSystemAuthorization(requestId)) {
            resolveAuthorization(requestId, null, "HOST_AUTH_FAILED")
        }
    }

    private fun isTrustedOrigin(origin: Uri): Boolean {
        val host = origin.host?.lowercase() ?: return false
        val local = host == "localhost" || host == "127.0.0.1"
        if (origin.scheme?.lowercase() != "https" && !local) return false
        return (FIRST_PARTY_HOSTS + extraTrustedHosts).any {
            host == it || host.endsWith(".$it")
        }
    }

    private fun safeAreaInsetsForPage(): JSONObject {
        val density = resources.displayMetrics.density.toDouble()
        return JSONObject()
            .put("top", if (titleBarVisible) 0.0 else systemBarInsets.top / density)
            .put("bottom", if (titleBarVisible) 0.0 else systemBarInsets.bottom / density)
            .put("left", if (titleBarVisible) 0.0 else systemBarInsets.left / density)
            .put("right", if (titleBarVisible) 0.0 else systemBarInsets.right / density)
    }

    private fun capsuleRectForPage(): JSONObject {
        if (titleBarVisible || !::floatingMenuButton.isInitialized) {
            return JSONObject().put("x", 0).put("y", 0).put("width", 0).put("height", 0)
        }
        val density = resources.displayMetrics.density.toDouble()
        return JSONObject()
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
            JSONObject()
                .put("id", messageId)
                .put("ok", true)
                .put("result", result)
                .toString(),
        )
    }

    private fun replyError(messageId: String, proxy: JavaScriptReplyProxy, error: String) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        proxy.postMessage(
            JSONObject()
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
        if (systemAuthorization != null || systemExternalAuthorization != null) {
            systemAuthorizationWasPaused = true
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        localPageLaunchPending = false
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
        HostSession.detach(this)
        teardownWebView()
        super.onDestroy()
    }

    private data class PendingAuthorization(
        val messageId: String,
        val replyProxy: JavaScriptReplyProxy,
        val timeout: Runnable,
        val request: JSONObject,
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

    private fun readSystemAuthorizationRequest(request: JSONObject): HostSsoProtocol.Request? {
        if (request.readString("codeChallengeMethod") != "S256") return null
        val scopes = request.optJSONArray("scope") ?: return null
        if (scopes.length() != 1) return null
        return HostSsoProtocol.Request(
            clientId = request.readString("clientId") ?: return null,
            codeChallenge = request.readString("codeChallenge") ?: return null,
            nonce = request.readString("nonce") ?: return null,
            redirectUri = request.readString("redirectUri") ?: return null,
            scope = scopes.optString(0),
            acquisitionJSON = HostSsoProtocol.readAcquisitionJson(request.opt("acquisition")),
        )
    }

    private fun randomBase64Url(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}
