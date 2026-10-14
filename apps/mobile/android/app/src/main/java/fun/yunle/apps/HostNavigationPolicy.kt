package `fun`.yunle.apps

import java.net.URI

/** Security policy shared by Android host navigation and message-channel setup. */
internal object HostNavigationPolicy {
    fun isSupportedUrl(raw: String, allowLocalHttp: Boolean): Boolean {
        val uri = parse(raw) ?: return false
        return when (uri.scheme.lowercase()) {
            "https" -> true
            "http" -> allowLocalHttp && isLoopback(uri.host)
            else -> false
        }
    }

    fun allowedOriginRules(raw: String, allowLocalHttp: Boolean): Set<String> {
        if (!isSupportedUrl(raw, allowLocalHttp)) return emptySet()
        val uri = parse(raw) ?: return emptySet()
        val scheme = uri.scheme.lowercase()
        val host = uri.host.lowercase().let {
            if (it.contains(':') && !it.startsWith('[')) "[$it]" else it
        }
        val defaultPort = uri.port == -1 ||
            (scheme == "https" && uri.port == 443) ||
            (scheme == "http" && uri.port == 80)
        return setOf("$scheme://$host${if (defaultPort) "" else ":${uri.port}"}")
    }

    fun hasSameOrigin(first: String, second: String, allowLocalHttp: Boolean): Boolean {
        val firstOrigin = allowedOriginRules(first, allowLocalHttp).singleOrNull() ?: return false
        return firstOrigin == allowedOriginRules(second, allowLocalHttp).singleOrNull()
    }

    private fun parse(raw: String): URI? = runCatching { URI(raw.trim()) }
        .getOrNull()
        ?.takeIf {
            it.isAbsolute &&
                !it.host.isNullOrBlank() &&
                it.rawUserInfo == null
        }

    private fun isLoopback(host: String): Boolean =
        host.equals("localhost", ignoreCase = true) ||
            host == "127.0.0.1" ||
            host == "::1" ||
            host == "[::1]"
}
