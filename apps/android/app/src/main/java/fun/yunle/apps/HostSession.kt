package `fun`.yunle.apps

import android.app.Activity
import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.lang.ref.WeakReference

/** Main-thread ownership of the one running cloud application. */
internal object HostSession {
    private var active = WeakReference<HostWebViewActivity>(null)
    private var isMinimized = false
    private val _minimizedAppName = MutableStateFlow<String?>(null)
    val minimizedAppName: StateFlow<String?> = _minimizedAppName.asStateFlow()

    fun current(): HostWebViewActivity? = active.get()?.takeUnless { it.isFinishing || it.isDestroyed }
    fun minimizedName(): String? = current()?.takeIf { isMinimized }?.sessionName()
    fun isMinimized(activity: HostWebViewActivity): Boolean = isMinimized && current() === activity

    fun attach(activity: HostWebViewActivity) {
        current()?.takeUnless { it === activity }?.finish()
        active = WeakReference(activity)
        isMinimized = false
        _minimizedAppName.value = null
    }

    fun detach(activity: HostWebViewActivity) {
        if (active.get() === activity) {
            active.clear()
            isMinimized = false
            _minimizedAppName.value = null
        }
    }

    fun minimized(activity: HostWebViewActivity) {
        if (current() === activity) {
            isMinimized = true
            _minimizedAppName.value = activity.sessionName()
        }
    }

    fun closeAll() {
        current()?.finish()
        active.clear()
        isMinimized = false
        _minimizedAppName.value = null
    }

    fun resume(presenter: Activity): Boolean {
        val session = current()
        if (session == null) {
            isMinimized = false
            _minimizedAppName.value = null
            return false
        }
        isMinimized = false
        _minimizedAppName.value = null
        presenter.startActivity(
            Intent(presenter, HostWebViewActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        return true
    }

    fun open(presenter: Activity, app: CatalogApp) {
        val options = app.launchOptions() ?: return
        val activeSession = current()
        if (activeSession?.matchesSession(app) == true && resume(presenter)) {
            return
        }
        presenter.startActivity(
            Intent(presenter, HostWebViewActivity::class.java)
                .putExtra(HostWebViewActivity.EXTRA_OPTIONS, options.toString()),
        )
    }
}
