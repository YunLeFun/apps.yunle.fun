package `fun`.yunle.apps

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.view.ViewGroup
import android.webkit.WebView
import `fun`.yunle.apps.account.AccountRequestBoundary
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.lang.ref.WeakReference

internal data class RunningAppSession(
    val sessionKey: String,
    val appId: String,
    val appName: String,
    val launchUrl: String,
    val optionsJson: String,
    val isMinimized: Boolean,
)

internal interface RuntimeWebHandle {
    fun pause()
    fun resume()
    fun detachFromParent()
    fun destroy()
}

internal class WebViewRuntimeHandle(val webView: WebView) : RuntimeWebHandle {
    override fun pause() {
        runCatching { webView.onPause() }
    }

    override fun resume() {
        runCatching { webView.onResume() }
    }

    override fun detachFromParent() {
        (webView.parent as? ViewGroup)?.removeView(webView)
    }

    override fun destroy() {
        detachFromParent()
        runCatching { webView.stopLoading() }
        runCatching { webView.destroy() }
    }
}

internal data class PooledWebSession(
    val sessionKey: String,
    val appId: String,
    val appName: String,
    val launchUrl: String,
    val optionsJson: String,
    val accountBoundary: AccountRequestBoundary,
    val handle: RuntimeWebHandle,
    var lastUsedAtMillis: Long,
)

/** Main-thread ownership of the foreground cloud application and memory-bounded LRU background pool. */
internal object HostSession {
    private var active = WeakReference<HostWebViewActivity>(null)
    private var isMinimized = false
    private val pool = linkedMapOf<String, PooledWebSession>()
    private var poolLimitOverrideForTesting: Int? = null
    private var detectedMaxSessions = 3

    private val _minimizedAppName = MutableStateFlow<String?>(null)
    val minimizedAppName: StateFlow<String?> = _minimizedAppName.asStateFlow()

    private val _runningSessions = MutableStateFlow<List<RunningAppSession>>(emptyList())
    val runningSessions: StateFlow<List<RunningAppSession>> = _runningSessions.asStateFlow()

    fun current(): HostWebViewActivity? = active.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    fun minimizedName(): String? = current()?.takeIf { isMinimized }?.sessionName()
        ?: pool.values.lastOrNull()?.appName

    fun isMinimized(activity: HostWebViewActivity): Boolean = isMinimized && current() === activity

    fun maxPooledSessions(context: Context): Int {
        poolLimitOverrideForTesting?.let { return it.coerceAtLeast(1) }
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return 3
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        val total = info.totalMem
        val computed = when {
            total <= (3L shl 30) -> 2
            total <= (6L shl 30) -> 3
            else -> 4
        }
        detectedMaxSessions = computed
        return computed
    }

    internal fun setMaxPoolSizeForTesting(limit: Int?) {
        poolLimitOverrideForTesting = limit
        if (limit != null) detectedMaxSessions = limit.coerceAtLeast(1)
    }

    internal fun pooledKeysForTesting(): List<String> = pool.keys.toList()

    fun attach(activity: HostWebViewActivity) {
        current()?.takeUnless { it === activity }?.finish()
        active = WeakReference(activity)
        isMinimized = false
        pool.remove(activity.sessionKey)?.let { displaced ->
            if (displaced.handle is WebViewRuntimeHandle && displaced.handle.webView !== activity.currentWebViewOrNull()) {
                displaced.handle.destroy()
            } else if (displaced.handle !is WebViewRuntimeHandle) {
                displaced.handle.destroy()
            }
        }
        publishState()
    }

    fun detach(activity: HostWebViewActivity) {
        if (active.get() === activity) {
            active.clear()
            isMinimized = false
            publishState()
        }
    }

    fun minimized(activity: HostWebViewActivity) {
        if (current() === activity) {
            isMinimized = true
            publishState()
        }
    }

    fun parkWebView(session: PooledWebSession, maxSessions: Int = activeMaxSessions()) {
        val cap = maxSessions.coerceAtLeast(1)
        session.handle.pause()
        session.handle.detachFromParent()
        pool.remove(session.sessionKey)?.handle?.takeIf { it !== session.handle }?.destroy()
        if (cap <= 1) {
            // Only the foreground session fits within a 1-session budget.
            evictAllPooled()
            session.handle.destroy()
            publishState()
            return
        }
        pool[session.sessionKey] = session
        // Reserve 1 slot for the foreground session, keep at most (cap - 1) in pool.
        val maxPoolEntries = (cap - 1).coerceAtLeast(0)
        val iterator = pool.entries.iterator()
        while (pool.size > maxPoolEntries && iterator.hasNext()) {
            val oldest = iterator.next()
            iterator.remove()
            oldest.value.handle.destroy()
        }
        publishState()
    }

    fun takePooledWebView(
        sessionKey: String,
        launchUrl: String,
        boundary: AccountRequestBoundary,
    ): PooledWebSession? {
        val existing = pool.remove(sessionKey) ?: return null
        if (existing.launchUrl != launchUrl || existing.accountBoundary != boundary) {
            existing.handle.destroy()
            publishState()
            return null
        }
        existing.handle.resume()
        publishState()
        return existing
    }

    fun closeSession(sessionKey: String) {
        val foreground = current()
        if (foreground?.sessionKey == sessionKey) {
            active.clear()
            isMinimized = false
            foreground.finish()
        }
        pool.remove(sessionKey)?.handle?.destroy()
        publishState()
    }

    @Suppress("DEPRECATION")
    fun trimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            evictAllPooled()
            publishState()
        }
    }

    fun closeAll() {
        current()?.let { foreground ->
            active.clear()
            isMinimized = false
            foreground.finish()
        } ?: run {
            active.clear()
            isMinimized = false
        }
        evictAllPooled()
        publishState()
    }

    fun resume(presenter: Activity): Boolean {
        val session = current()
        if (session == null) {
            isMinimized = false
            publishState()
            return false
        }
        isMinimized = false
        publishState()
        presenter.startActivity(
            Intent(presenter, HostWebViewActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        return true
    }

    fun resumeSession(presenter: Activity, sessionKey: String): Boolean {
        val activeSession = current()
        if (activeSession?.sessionKey == sessionKey) {
            return resume(presenter)
        }
        val pooled = pool[sessionKey] ?: return false
        openRaw(presenter, pooled.sessionKey, pooled.optionsJson)
        return true
    }

    fun open(presenter: Activity, app: CatalogApp) {
        val options = app.launchOptions()?.toString() ?: return
        maxPooledSessions(presenter)
        val activeSession = current()
        if (activeSession?.matchesSession(app) == true && resume(presenter)) {
            return
        }
        openRaw(presenter, app.id, options)
    }

    fun openRaw(presenter: Activity, sessionKey: String, optionsJson: String) {
        maxPooledSessions(presenter)
        val activeSession = current()
        if (activeSession != null) {
            if (activeSession.sessionKey == sessionKey && activeSession.currentOptions() == optionsJson) {
                resume(presenter)
                return
            }
            presenter.startActivity(
                Intent(presenter, HostWebViewActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(HostWebViewActivity.EXTRA_OPTIONS, optionsJson),
            )
            return
        }
        presenter.startActivity(
            Intent(presenter, HostWebViewActivity::class.java)
                .putExtra(HostWebViewActivity.EXTRA_OPTIONS, optionsJson),
        )
    }

    private fun evictAllPooled() {
        val values = pool.values.toList()
        pool.clear()
        values.forEach { it.handle.destroy() }
    }

    private fun activeMaxSessions(): Int = poolLimitOverrideForTesting ?: detectedMaxSessions

    private fun publishState() {
        val foreground = current()
        val list = buildList {
            if (foreground != null) {
                add(
                    RunningAppSession(
                        sessionKey = foreground.sessionKey,
                        appId = foreground.sessionKey,
                        appName = foreground.sessionName(),
                        launchUrl = foreground.currentUrl(),
                        optionsJson = foreground.currentOptions(),
                        isMinimized = isMinimized,
                    ),
                )
            }
            pool.values.toList().asReversed().forEach { entry ->
                add(
                    RunningAppSession(
                        sessionKey = entry.sessionKey,
                        appId = entry.appId,
                        appName = entry.appName,
                        launchUrl = entry.launchUrl,
                        optionsJson = entry.optionsJson,
                        isMinimized = true,
                    ),
                )
            }
        }
        _runningSessions.value = list
        _minimizedAppName.value = minimizedName()
    }
}
