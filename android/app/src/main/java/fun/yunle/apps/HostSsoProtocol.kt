package `fun`.yunle.apps

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Base64
import org.json.JSONObject

/** OAuth result transport shared by the Android Custom Tab adapter. */
internal object HostSsoProtocol {
    private const val ISSUER = "https://www.yunle.fun"
    private val CLIENT_ID_RE = Regex("^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$")
    private val VALUE_RE = Regex("^[\\w-]{43}$")

    data class Request(
        val clientId: String,
        val codeChallenge: String,
        val nonce: String,
        val redirectUri: String,
        val scope: String,
    )

    sealed interface Result {
        data class Success(val code: String, val issuer: String) : Result
        data object Denied : Result
    }

    fun buildAuthorizationUrl(request: Request, state: String): String {
        require(isValid(request) && VALUE_RE.matches(state))
        val callback = "yunlefun://auth/sso?state=$state"
        val query = listOf(
            "client_id" to request.clientId,
            "redirect_uri" to request.redirectUri,
            "scope" to request.scope,
            "nonce" to request.nonce,
            "code_challenge" to request.codeChallenge,
            "code_challenge_method" to "S256",
            "prompt" to "select_account",
            "native_callback_uri" to callback,
        ).joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }
        return "$ISSUER/auth/sso?$query"
    }

    fun readCallback(raw: String, expectedState: String, request: Request): Result? {
        if (!VALUE_RE.matches(expectedState) || !isValid(request)) return null
        val callback = runCatching { URI(raw) }.getOrNull() ?: return null
        if (callback.scheme != "yunlefun" || callback.host != "auth" || callback.path != "/sso" ||
            callback.rawUserInfo != null || callback.fragment != null) return null
        val callbackQuery = readQuery(callback.rawQuery) ?: return null
        if (callbackQuery.keys != setOf("state", "result") ||
            callbackQuery["state"] != expectedState) return null

        val resultUrl = callbackQuery["result"] ?: return null
        val resultUri = runCatching { URI(resultUrl) }.getOrNull() ?: return null
        val redirect = URI(
            resultUri.scheme,
            resultUri.rawAuthority,
            resultUri.rawPath,
            resultUri.rawQuery,
            null,
        ).toString()
        if (redirect != request.redirectUri || resultUri.rawFragment.isNullOrEmpty()) return null
        val encoded = resultUri.rawFragment
            .takeIf { it.startsWith("ylf_sso=") && !it.contains('&') }
            ?.removePrefix("ylf_sso=")
            ?: return null
        val payload = runCatching {
            JSONObject(
                String(Base64.getUrlDecoder().decode(padded(encoded)), StandardCharsets.UTF_8),
            )
        }.getOrNull() ?: return null
        if (payload.optString("nonce") != request.nonce || payload.optString("iss") != ISSUER ||
            payload.has("ticket") || payload.has("session") || payload.has("access_token") ||
            payload.has("refresh_token")) return null
        val ok = payload.opt("ok") as? Boolean ?: return null
        if (ok) {
            val code = payload.optString("code")
            return code.takeIf(VALUE_RE::matches)?.let { Result.Success(it, ISSUER) }
        }
        return if (payload.optString("reason") == "access_denied") Result.Denied else null
    }

    private fun isValid(request: Request): Boolean =
        CLIENT_ID_RE.matches(request.clientId) &&
            VALUE_RE.matches(request.codeChallenge) &&
            VALUE_RE.matches(request.nonce) &&
            request.scope == "identity:bootstrap" &&
            isSecureRedirect(request.redirectUri)

    private fun isSecureRedirect(raw: String): Boolean {
        val uri = runCatching { URI(raw) }.getOrNull() ?: return false
        return uri.scheme == "https" && !uri.host.isNullOrBlank() &&
            uri.rawUserInfo == null && uri.rawFragment == null && uri.toString() == raw
    }

    private fun readQuery(raw: String?): Map<String, String>? {
        if (raw.isNullOrEmpty()) return null
        val result = linkedMapOf<String, String>()
        for (pair in raw.split('&')) {
            val parts = pair.split('=', limit = 2)
            val key = decode(parts[0])
            if (key in result) return null
            result[key] = decode(parts.getOrElse(1) { "" })
        }
        return result
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8)

    private fun decode(value: String): String =
        URLDecoder.decode(value, StandardCharsets.UTF_8)

    private fun padded(value: String): String =
        value + "=".repeat((4 - value.length % 4) % 4)
}
