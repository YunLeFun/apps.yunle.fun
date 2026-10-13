package `fun`.yunle.apps

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebView
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.core.view.setPadding
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.getcapacitor.BridgeActivity
import com.getcapacitor.CapConfig
import com.getcapacitor.WebViewListener
import org.json.JSONObject
import java.lang.ref.WeakReference

/** Hosts one allowlisted first-party route in a bundled Capacitor WebView. */
class LocalPageActivity : BridgeActivity() {
    private lateinit var request: LocalPageRequest
    private val mainHandler = Handler(Looper.getMainLooper())
    private val startedAt = SystemClock.elapsedRealtime()
    private val initialPssKb = Debug.getPss()
    private var pageCommitted = false
    private var errorOverlay: View? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val kind = savedInstanceState?.getString(STATE_KIND) ?: intent.getStringExtra(EXTRA_KIND)
        val value = savedInstanceState?.getString(STATE_VALUE) ?: intent.getStringExtra(EXTRA_VALUE)
        val target = savedInstanceState?.getString(STATE_TARGET) ?: intent.getStringExtra(EXTRA_TARGET)
        val resolved = LocalPageRoutePolicy.resolve(kind, value, target)
        if (resolved == null) {
            request = LocalPageRequest("/", LocalPageRoutePolicy.KIND_APP_DETAIL, null)
            config = bundledConfig(request.routePath)
            super.onCreate(savedInstanceState)
            finish()
            return
        }

        request = resolved
        config = bundledConfig(request.routePath)
        registerPlugin(HostRuntimePlugin::class.java)
        bridgeBuilder.addWebViewListener(pageListener)
        super.onCreate(savedInstanceState)

        installErrorOverlay()
        mainHandler.postDelayed({
            if (!pageCommitted && !isFinishing)
                showStartupError()
        }, STARTUP_TIMEOUT_MS)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                val webView = bridge?.webView
                if (webView?.canGoBack() == true)
                    webView.goBack()
                else
                    finish()
            }
        })
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        if (!::request.isInitialized) return
        outState.putString(STATE_KIND, request.kind)
        outState.putString(STATE_VALUE, intent.getStringExtra(EXTRA_VALUE))
        request.target?.let { outState.putString(STATE_TARGET, it) }
    }

    @SuppressLint("AddJavascriptInterface")
    override fun load() {
        val webView = findViewById<WebView>(com.getcapacitor.android.R.id.webview)
        webView.addJavascriptInterface(
            NativePresentationJavascriptBridge(this, request.contextJson()),
            ANDROID_BRIDGE_NAME,
        )

        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(
                webView,
                presentationScript(request),
                setOf(LOCAL_ORIGIN),
            )
        }
        super.load()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        bridge?.webView?.removeJavascriptInterface(ANDROID_BRIDGE_NAME)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun bundledConfig(routePath: String): CapConfig {
        val rawConfig = assets.open("capacitor.config.json").bufferedReader().use { it.readText() }
        val configJson = JSONObject(rawConfig)
        val server = configJson.optJSONObject("server") ?: JSONObject().also {
            configJson.put("server", it)
        }
        server.put("appStartPath", routePath)
        return CapConfig(assets, configJson)
    }

    private fun installErrorOverlay() {
        val root = bridge?.webView?.parent as? ViewGroup ?: return
        errorOverlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(32))
            setBackgroundColor(resolveSurfaceColor())
            visibility = View.GONE

            addView(TextView(context).apply {
                text = "页面暂时无法打开"
                textSize = 20f
                setTextColor(resolveTextColor())
                gravity = Gravity.CENTER
            })
            addView(TextView(context).apply {
                text = "请重试，或关闭后返回应用。"
                textSize = 14f
                setTextColor(resolveSecondaryTextColor())
                gravity = Gravity.CENTER
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(8) })
            addView(Button(context).apply {
                text = "重试"
                setOnClickListener { recreate() }
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(20) })
            addView(Button(context).apply {
                text = "关闭"
                setOnClickListener { finish() }
            })
        }
        root.addView(errorOverlay, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ))
    }

    private fun showStartupError() {
        errorOverlay?.visibility = View.VISIBLE
        Log.e(LOG_TAG, "Bundled ${request.kind} failed before first content became visible")
    }

    private fun resolveSurfaceColor(): Int = if (
        resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
        android.content.res.Configuration.UI_MODE_NIGHT_YES
    ) Color.rgb(30, 30, 30) else Color.WHITE

    private fun resolveTextColor(): Int = if (resolveSurfaceColor() == Color.WHITE) Color.rgb(30, 30, 30) else Color.WHITE

    private fun resolveSecondaryTextColor(): Int = if (resolveSurfaceColor() == Color.WHITE) Color.DKGRAY else Color.LTGRAY

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private val pageListener = object : WebViewListener() {
        override fun onPageCommitVisible(view: WebView, url: String) {
            if (pageCommitted) return
            pageCommitted = true
            errorOverlay?.visibility = View.GONE
            Log.i(
                LOG_TAG,
                "Bundled ${request.kind} visible in ${SystemClock.elapsedRealtime() - startedAt}ms; " +
                    "PSS delta ${Debug.getPss() - initialPssKb}KB",
            )
        }

        override fun onReceivedError(webView: WebView) {
            if (!pageCommitted)
                showStartupError()
        }

        override fun onRenderProcessGone(webView: WebView, detail: RenderProcessGoneDetail): Boolean {
            Log.e(LOG_TAG, "Bundled ${request.kind} renderer exited; crashed=${detail.didCrash()}")
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.destroy()
            showStartupError()
            return true
        }
    }

    private class NativePresentationJavascriptBridge(
        activity: LocalPageActivity,
        private val contextJson: String,
    ) {
        private val activity = WeakReference(activity)

        @JavascriptInterface
        fun getContext(): String = contextJson

        @JavascriptInterface
        fun close() {
            activity.get()?.runOnUiThread { activity.get()?.finish() }
        }
    }

    companion object {
        private const val EXTRA_KIND = "fun.yunle.apps.localPage.kind"
        private const val EXTRA_VALUE = "fun.yunle.apps.localPage.value"
        private const val EXTRA_TARGET = "fun.yunle.apps.localPage.target"
        private const val STATE_KIND = "localPage.kind"
        private const val STATE_VALUE = "localPage.value"
        private const val STATE_TARGET = "localPage.target"
        private const val ANDROID_BRIDGE_NAME = "YlfNativePresentationAndroid"
        private const val LOCAL_ORIGIN = "https://localhost"
        private const val STARTUP_TIMEOUT_MS = 8_000L
        private const val LOG_TAG = "YlfLocalPage"

        internal fun appDetailIntent(context: Context, applicationKey: String, scrollToReviews: Boolean): Intent =
            Intent(context, LocalPageActivity::class.java)
                .putExtra(EXTRA_KIND, LocalPageRoutePolicy.KIND_APP_DETAIL)
                .putExtra(EXTRA_VALUE, applicationKey)
                .apply {
                    if (scrollToReviews)
                        putExtra(EXTRA_TARGET, LocalPageRoutePolicy.TARGET_REVIEWS)
                }

        internal fun developerIntent(context: Context, login: String): Intent =
            Intent(context, LocalPageActivity::class.java)
                .putExtra(EXTRA_KIND, LocalPageRoutePolicy.KIND_DEVELOPER)
                .putExtra(EXTRA_VALUE, login)

        private fun presentationScript(request: LocalPageRequest): String = """
            (() => {
              const nativeBridge = window.$ANDROID_BRIDGE_NAME
              window.__YLF_NATIVE_PRESENTATION__ = Object.freeze({
                ...${request.contextJson()},
                close: () => nativeBridge.close()
              })
            })()
        """.trimIndent()
    }
}
