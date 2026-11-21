package `fun`.yunle.apps

import `fun`.yunle.apps.webruntime.HostSsoPolicy
import `fun`.yunle.apps.webruntime.HostSsoRequest
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.util.Base64
import java.util.Locale

internal object WorkshopLink {
    private val CODE_RE = Regex("^[2-9A-HJKMNP-Z]{6}$")

    fun normalize(input: String): String? {
        val value = input.trim().uppercase(Locale.ROOT)
        return value.takeIf(CODE_RE::matches)
    }

    fun parse(input: String): String? {
        val value = input.trim()
        normalize(value)?.let { return it }
        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase(Locale.ROOT) != "https" ||
            uri.host?.lowercase(Locale.ROOT) != "apps.yunle.fun" ||
            uri.port !in listOf(-1, 443) ||
            uri.rawUserInfo != null ||
            uri.rawQuery != null ||
            uri.rawFragment != null
        ) {
            return null
        }
        val segments = (uri.rawPath ?: "").trimEnd('/').split('/')
        if (segments.size != 3 || segments[0].isNotEmpty() || segments[1] != "w") return null
        return normalize(segments[2])
    }
}

internal data class CrossAppAuthorizationRequest(
    val clientId: String,
    val redirectUri: String,
    val nonce: String,
    val codeChallenge: String,
) {
    val sourceOrigin: String
        get() = "https://${URI(redirectUri).host.orEmpty()}"

    fun toHostSsoRequest(): HostSsoRequest = HostSsoRequest.parse(
        sourceOrigin = sourceOrigin,
        parameters = JSONObject().apply {
            put("clientId", clientId)
            put("redirectUri", redirectUri)
            put("nonce", nonce)
            put("codeChallenge", codeChallenge)
            put("codeChallengeMethod", "S256")
            put("scope", JSONArray(listOf("identity:bootstrap")))
        },
    )
}

internal object CrossAppAuthorizationLink {
    const val HOST = "www.yunle.fun"
    const val PATH = "/auth/app"

    private val REQUIRED_KEYS = setOf(
        "client_id",
        "redirect_uri",
        "scope",
        "nonce",
        "code_challenge",
        "code_challenge_method",
    )
    private val OPTIONAL_KEYS = setOf("prompt")
    private val ALLOWED_PROMPTS = setOf("select_account", "consent")

    private val CLIENT_ID_RE = Regex("^[a-z0-9][a-z0-9-]{1,127}$")
    private val NONCE_RE = Regex("^[A-Za-z0-9_-]{32,128}$")
    private val CHALLENGE_RE = Regex("^[A-Za-z0-9_-]{43}$")

    fun isEntry(rawUrl: String): Boolean {
        val uri = runCatching { URI(rawUrl) }.getOrNull()
        if (uri != null) {
            return uri.scheme?.lowercase(Locale.ROOT) == "https" &&
                uri.host?.lowercase(Locale.ROOT) == HOST &&
                uri.rawPath == PATH
        }
        val lower = rawUrl.lowercase(Locale.ROOT)
        val prefix = "https://$HOST$PATH"
        return lower == prefix ||
            lower.startsWith("$prefix?") ||
            lower.startsWith("$prefix#")
    }

    fun parse(rawUrl: String): CrossAppAuthorizationRequest? {
        if (rawUrl.toByteArray(Charsets.UTF_8).size > 4096) return null
        val uri = runCatching { URI(rawUrl) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase(Locale.ROOT) != "https" ||
            uri.host?.lowercase(Locale.ROOT) != HOST ||
            uri.rawPath != PATH ||
            uri.port != -1 ||
            uri.rawUserInfo != null ||
            uri.rawFragment != null ||
            uri.rawQuery.isNullOrEmpty()
        ) {
            return null
        }

        val values = linkedMapOf<String, String>()
        for (pair in uri.rawQuery.split('&')) {
            val idx = pair.indexOf('=')
            if (idx <= 0) return null
            val key = runCatching { URLDecoder.decode(pair.substring(0, idx), Charsets.UTF_8.name()) }
                .getOrNull() ?: return null
            val value = runCatching { URLDecoder.decode(pair.substring(idx + 1), Charsets.UTF_8.name()) }
                .getOrNull() ?: return null
            if (!REQUIRED_KEYS.contains(key) && !OPTIONAL_KEYS.contains(key)) return null
            if (values.containsKey(key) || value.isEmpty()) return null
            values[key] = value
        }

        if (!values.keys.containsAll(REQUIRED_KEYS)) return null
        val clientId = values["client_id"] ?: return null
        val redirectUri = values["redirect_uri"] ?: return null
        val scope = values["scope"] ?: return null
        val method = values["code_challenge_method"] ?: return null
        val nonce = values["nonce"] ?: return null
        val codeChallenge = values["code_challenge"] ?: return null
        val prompt = values["prompt"]

        val parsedRedirect = HostSsoRequest.validateHttpsUrl(redirectUri) ?: return null
        if (parsedRedirect.port != -1) return null
        if (!CLIENT_ID_RE.matches(clientId) ||
            scope != "identity:bootstrap" ||
            method != "S256" ||
            !NONCE_RE.matches(nonce) ||
            !CHALLENGE_RE.matches(codeChallenge) ||
            (prompt != null && !ALLOWED_PROMPTS.contains(prompt))
        ) {
            return null
        }

        return CrossAppAuthorizationRequest(
            clientId = clientId,
            redirectUri = redirectUri,
            nonce = nonce,
            codeChallenge = codeChallenge,
        )
    }
}

internal sealed class CrossAppRedirect {
    data class Approved(val code: String) : CrossAppRedirect()
    data object Denied : CrossAppRedirect()
    data object AccountSelectionRequired : CrossAppRedirect()

    fun callbackUrl(request: CrossAppAuthorizationRequest): String? {
        val body = when (this) {
            is Approved -> {
                if (!CODE_RE.matches(code)) return null
                """{"nonce":"${request.nonce}","iss":"${HostSsoPolicy.ISSUER}","ok":true,"code":"$code"}"""
            }
            Denied -> """{"nonce":"${request.nonce}","iss":"${HostSsoPolicy.ISSUER}","ok":false,"reason":"access_denied"}"""
            AccountSelectionRequired ->
                """{"nonce":"${request.nonce}","iss":"${HostSsoPolicy.ISSUER}","ok":false,"reason":"account_selection_required"}"""
        }
        val encoded = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(body.toByteArray(Charsets.UTF_8))
        return "${request.redirectUri}#ylf_sso=$encoded"
    }

    companion object {
        private val CODE_RE = Regex("^[A-Za-z0-9_-]{43}$")
    }
}

internal sealed class NativeDestination {
    data class Application(val key: String) : NativeDestination()
    data class Workshop(val id: String) : NativeDestination()
    data class Developer(val login: String) : NativeDestination()
    data class CrossAppAuth(val request: CrossAppAuthorizationRequest) : NativeDestination()
    data object InvalidCrossAppAuth : NativeDestination()
}

internal object NativeDeepLinkRouter {
    private val APP_KEY_RE = Regex("^[A-Za-z0-9_-]+$")
    private val DEVELOPER_RE = Regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,62}[A-Za-z0-9])?$")

    fun parse(rawUrl: String?): NativeDestination? {
        val value = rawUrl?.trim()?.takeIf(String::isNotEmpty) ?: return null
        if (CrossAppAuthorizationLink.isEntry(value)) {
            return CrossAppAuthorizationLink.parse(value)?.let { NativeDestination.CrossAppAuth(it) }
                ?: NativeDestination.InvalidCrossAppAuth
        }

        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        if (uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null) return null

        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return null
        val host = uri.host?.lowercase(Locale.ROOT) ?: return null
        val rawPath = uri.rawPath.orEmpty()

        val normalizedPath = when {
            scheme == "https" && host == "apps.yunle.fun" && uri.port in listOf(-1, 443) -> rawPath
            scheme == "yunlefun" && uri.port == -1 && host in setOf("app", "w", "workshop", "developer") -> {
                val typeSegment = if (host == "workshop") "w" else host
                "/$typeSegment$rawPath"
            }
            else -> return null
        }

        val trimmedPath = normalizedPath.removeSuffix("/")
        val segments = trimmedPath.split('/')
        if (segments.size != 3 || segments[0].isNotEmpty()) return null
        val kind = segments[1]
        val key = segments[2]

        return when (kind) {
            "app" -> key.takeIf { it.toByteArray(Charsets.UTF_8).size <= 256 && APP_KEY_RE.matches(it) }
                ?.let(NativeDestination::Application)
            "w" -> WorkshopLink.normalize(key)?.let(NativeDestination::Workshop)
            "developer" -> key.takeIf { it.length in 1..64 && DEVELOPER_RE.matches(it) }
                ?.let(NativeDestination::Developer)
            else -> null
        }
    }
}
