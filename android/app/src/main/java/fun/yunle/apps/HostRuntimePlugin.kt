package `fun`.yunle.apps

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.webkit.CookieManager
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.lang.ref.WeakReference

/** Android adapter for the cross-platform HostRuntime contract. */
@CapacitorPlugin(name = "HostRuntime")
class HostRuntimePlugin : Plugin() {
    private var hostActivity = WeakReference<HostWebViewActivity>(null)
    private var authorizationPromptActive = false

    override fun load() {
        current = WeakReference(this)
    }

    @PluginMethod
    fun open(call: PluginCall) {
        val url = call.getString("url")?.trim().orEmpty()
        val allowLocalHttp = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (!HostNavigationPolicy.isSupportedUrl(url, allowLocalHttp)) {
            call.reject("Missing or invalid url")
            return
        }

        activity.runOnUiThread {
            val currentActivity = hostActivity.get()
            if (currentActivity != null &&
                !currentActivity.isFinishing &&
                currentActivity.canReuseFor(url)
            ) {
                currentActivity.applyOptions(call.data)
            } else {
                currentActivity?.takeUnless { it.isFinishing }?.finish()
                val intent = Intent(activity, HostWebViewActivity::class.java)
                    .putExtra(HostWebViewActivity.EXTRA_OPTIONS, call.data.toString())
                activity.startActivity(intent)
            }
            call.resolve()
        }
    }

    @PluginMethod
    fun close(call: PluginCall) {
        activity.runOnUiThread {
            hostActivity.get()?.finish()
            call.resolve()
        }
    }

    @PluginMethod
    fun updateAppInfo(call: PluginCall) {
        activity.runOnUiThread {
            hostActivity.get()?.updateAppInfo(call.getObject("app"))
            call.resolve()
        }
    }

    @PluginMethod
    fun listSessions(call: PluginCall) {
        activity.runOnUiThread {
            call.resolve(sessionsPayload())
        }
    }

    @PluginMethod
    fun endSession(call: PluginCall) {
        val key = call.getString("id").orEmpty()
        activity.runOnUiThread {
            hostActivity.get()?.takeIf { it.sessionKey == key }?.finish()
            call.resolve()
        }
    }

    /** The account choice is deliberately rendered by Android, outside page DOM control. */
    @PluginMethod
    fun confirmAuthorization(call: PluginCall) {
        val applicationName = normalizedLabel(call.getString("applicationName"), 80)
        val applicationOrigin = normalizedHttpsOrigin(call.getString("applicationOrigin"))
        val accountName = normalizedLabel(call.getString("accountName"), 120)
        val permissionDescription = normalizedLabel(call.getString("permissionDescription"), 160)
        if (
            applicationName == null ||
            applicationOrigin == null ||
            accountName == null ||
            permissionDescription == null
        ) {
            call.reject("Missing authorization prompt context")
            return
        }

        activity.runOnUiThread {
            if (authorizationPromptActive) {
                call.reject("Authorization prompt already active")
                return@runOnUiThread
            }
            val presenter = hostActivity.get()?.takeUnless { it.isFinishing }
            if (presenter == null) {
                call.reject("No active browser session")
                return@runOnUiThread
            }

            authorizationPromptActive = true
            val authorizationNotice = normalizedLabel(call.getString("authorizationNotice"), 160)
            AuthorizationConsentSheet(
                activity = presenter,
                content = AuthorizationSheetContent(
                    applicationName = applicationName,
                    applicationOrigin = applicationOrigin,
                    applicationIconUrl = normalizedHttpsUrl(call.getString("applicationIconUrl")),
                    accountName = accountName,
                    accountAvatarUrl = normalizedHttpsUrl(call.getString("accountAvatarUrl")),
                    permissionDescription = permissionDescription,
                    authorizationNotice = authorizationNotice,
                ),
            ) { choice ->
                authorizationPromptActive = false
                call.resolve(
                    JSObject()
                        .put("allowed", choice == AuthorizationSheetChoice.CURRENT)
                        .put("choice", choice.wireValue),
                )
            }.show()
        }
    }

    /** Continue the pending page request in an Android Custom Tab. */
    @PluginMethod
    fun authorizeWithOtherAccount(call: PluginCall) {
        val requestId = call.getString("requestId").orEmpty()
        if (requestId.isEmpty()) {
            call.reject("Missing requestId")
            return
        }
        activity.runOnUiThread {
            val started = hostActivity.get()?.beginOtherAccountAuthorization(requestId) == true
            if (started) call.resolve()
            else call.reject("Unknown or invalid authorization request")
        }
    }

    @PluginMethod
    fun resolveAuthorization(call: PluginCall) {
        val requestId = call.getString("requestId").orEmpty()
        if (requestId.isEmpty()) {
            call.reject("Missing requestId")
            return
        }
        activity.runOnUiThread {
            val resolved = hostActivity.get()?.resolveAuthorization(
                requestId,
                call.getObject("result"),
                call.getString("error"),
            ) == true
            if (resolved) call.resolve()
            else call.reject("Unknown or expired authorization request")
        }
    }

    /**
     * Clear only the fixed first-party cookie allowlist. Web input cannot select
     * cookie names or domains, and no host access/refresh token is exposed.
     */
    @PluginMethod
    fun clearIdentitySessions(call: PluginCall) {
        activity.runOnUiThread {
            val cookieManager = CookieManager.getInstance()
            val cookies = listOf(
                Triple("https://play.yunle.fun/", "__Host-ylf_play_session", true),
                Triple("https://cms.yunle.fun/", "__Host-ylf-cms-session", true),
                Triple("https://cms.yunle.fun/", "h3", false),
            )
            var remaining = cookies.size
            cookies.forEach { (origin, name, hostOnly) ->
                val attributes = if (hostOnly) "; Secure; HttpOnly; SameSite=Lax" else ""
                cookieManager.setCookie(
                    origin,
                    "$name=; Path=/; Max-Age=0$attributes",
                ) {
                    remaining -= 1
                    if (remaining == 0) {
                        cookieManager.flush()
                        hostActivity.get()?.notifyHostIdentityChanged()
                        call.resolve()
                    }
                }
            }
        }
    }

    internal fun attach(activity: HostWebViewActivity) {
        hostActivity = WeakReference(activity)
        notifySessionsChanged()
    }

    internal fun detach(activity: HostWebViewActivity) {
        if (hostActivity.get() === activity) {
            hostActivity.clear()
            notifyListeners("browserFinished", JSObject())
            notifySessionsChanged()
        }
    }

    internal fun requestAuthorization(
        requestId: String,
        sourceOrigin: String,
        appId: String,
        request: JSObject,
    ) {
        notifyListeners(
            "authorizationRequested",
            JSObject()
                .put("requestId", requestId)
                .put("sourceOrigin", sourceOrigin)
                .put("appId", appId)
                .put("request", request),
            true,
        )
    }

    internal fun deliverSystemAuthorizationCallback(uri: android.net.Uri?) {
        activity.runOnUiThread {
            uri?.let { hostActivity.get()?.deliverSystemAuthorizationCallback(it) }
        }
    }

    private fun sessionsPayload(): JSObject {
        val sessions = JSArray()
        hostActivity.get()?.takeUnless { it.isFinishing }?.let {
            sessions.put(it.sessionInfo())
        }
        return JSObject().put("sessions", sessions)
    }

    private fun notifySessionsChanged() {
        notifyListeners("sessionsChanged", sessionsPayload())
    }

    private fun normalizedLabel(value: String?, maxLength: Int): String? =
        value
            ?.trim()
            ?.replace(Regex("\\s+"), " ")
            ?.takeIf { it.isNotEmpty() }
            ?.take(maxLength)

    private fun normalizedHttpsOrigin(value: String?): String? {
        val uri = value?.let(Uri::parse) ?: return null
        if (
            uri.scheme?.lowercase() != "https" ||
            uri.host.isNullOrBlank() ||
            uri.userInfo != null ||
            (uri.path.orEmpty().isNotEmpty() && uri.path != "/") ||
            uri.query != null ||
            uri.fragment != null
        ) return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "https://${uri.host!!.lowercase()}$port"
    }

    private fun normalizedHttpsUrl(value: String?): String? {
        val uri = value?.let(Uri::parse) ?: return null
        return if (
            uri.scheme?.lowercase() == "https" &&
            !uri.host.isNullOrBlank() &&
            uri.userInfo == null
        ) uri.toString() else null
    }

    override fun handleOnDestroy() {
        if (current.get() === this) current.clear()
        hostActivity.clear()
        super.handleOnDestroy()
    }

    companion object {
        private var current = WeakReference<HostRuntimePlugin>(null)

        internal fun instance(): HostRuntimePlugin? = current.get()
    }
}
