package `fun`.yunle.apps

import com.getcapacitor.JSObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

internal object ExternalAuthProtocol {
    private val statePattern = Regex("^native_[A-Za-z0-9_-]{43}$")

    data class Request(val url: String, val state: String)

    enum class Status { SUCCESS, DENIED, ERROR }

    fun readRequest(input: JSObject, allowLocalhost: Boolean = false): Request? {
        val state = input.getString("state") ?: return null
        if (!statePattern.matches(state)) return null
        val rawUrl = input.getString("url") ?: return null
        val url = runCatching { URI(rawUrl) }.getOrNull() ?: return null
        val query = readQuery(url) ?: return null
        if (
            url.scheme?.lowercase() != "https" ||
            url.host?.lowercase() != "github.com" ||
            url.path != "/login/oauth/authorize" ||
            url.userInfo != null ||
            url.fragment != null ||
            query["state"] != listOf(state) ||
            query["redirect_uri"]?.size != 1 ||
            !isAllowedRedirectUri(query["redirect_uri"]?.first(), allowLocalhost)
        ) return null
        return Request(rawUrl, state)
    }

    fun readCallback(rawUri: String, expectedState: String): Status? {
        if (!statePattern.matches(expectedState)) return null
        val uri = runCatching { URI(rawUri) }.getOrNull() ?: return null
        val query = readQuery(uri) ?: return null
        if (
            uri.scheme != "yunlefun" ||
            uri.host != "auth" ||
            uri.path != "/external" ||
            uri.userInfo != null ||
            uri.port != -1 ||
            uri.fragment != null ||
            query.keys != setOf("state", "status") ||
            query["state"] != listOf(expectedState) ||
            query["status"]?.size != 1
        ) return null
        return when (query["status"]?.first()) {
            "success" -> Status.SUCCESS
            "denied" -> Status.DENIED
            "error" -> Status.ERROR
            else -> null
        }
    }

    private fun isAllowedRedirectUri(raw: String?, allowLocalhost: Boolean): Boolean {
        if (raw == "https://cms.yunle.fun/api/github/callback") return true
        if (!allowLocalhost || raw == null) return false
        val uri = runCatching { URI(raw) }.getOrNull() ?: return false
        return uri.scheme in setOf("http", "https") &&
            uri.host in setOf("localhost", "127.0.0.1") &&
            uri.path == "/api/github/callback" &&
            uri.userInfo == null &&
            uri.fragment == null
    }

    private fun readQuery(uri: URI): Map<String, List<String>>? = runCatching {
        uri.rawQuery?.split('&')
            ?.filter { it.isNotEmpty() }
            ?.map { pair ->
                val parts = pair.split('=', limit = 2)
                decode(parts[0]) to decode(parts.getOrElse(1) { "" })
            }
            ?.groupBy({ it.first }, { it.second })
            ?: emptyMap()
    }.getOrNull()

    private fun decode(value: String): String =
        URLDecoder.decode(value, StandardCharsets.UTF_8)
}
