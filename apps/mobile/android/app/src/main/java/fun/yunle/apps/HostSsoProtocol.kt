package `fun`.yunle.apps

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
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
        val acquisitionJSON: String? = null,
    )

    sealed interface Result {
        data class Success(val code: String, val issuer: String) : Result
        data object Denied : Result
    }

    fun buildAuthorizationUrl(request: Request, state: String): String {
        require(isValid(request) && VALUE_RE.matches(state))
        val callback = "yunlefun://auth/sso?state=$state"
        val fields = mutableListOf(
            "client_id" to request.clientId,
            "redirect_uri" to request.redirectUri,
            "scope" to request.scope,
            "nonce" to request.nonce,
            "code_challenge" to request.codeChallenge,
            "code_challenge_method" to "S256",
            "prompt" to "select_account",
            "native_callback_uri" to callback,
        )
        request.acquisitionJSON?.let { raw ->
            readAcquisitionJson(runCatching { JSONObject(raw) }.getOrNull())?.let {
                fields.add("acquisition" to it)
            }
        }
        val query = fields.joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }
        return "$ISSUER/auth/sso?$query"
    }

    /** Bounded allowlist; invalid optional attribution never prevents authentication. */
    fun readAcquisitionJson(input: Any?): String? = runCatching {
        val context = input as? JSONObject ?: return null
        if (context.toString().toByteArray(Charsets.UTF_8).size > 4096 || context.opt("version") != 1) return null
        val first = readAcquisitionTouch(context.optJSONObject("firstTouch")) ?: return null
        val current = readAcquisitionTouch(context.optJSONObject("registerTouch")) ?: return null
        JSONObject().put("version", 1).put("firstTouch", first).put("registerTouch", current)
            .toString().takeIf { it.toByteArray(Charsets.UTF_8).size <= 4096 }
    }.getOrNull()

    private fun readAcquisitionTouch(input: JSONObject?): JSONObject? {
        if (input == null) return null
        val timestamp = (input.opt("capturedAt") as? Number)?.toDouble() ?: return null
        if (!timestamp.isFinite() || timestamp <= 0 || timestamp > 9007199254740991.0 ||
            timestamp != kotlin.math.floor(timestamp)) return null
        val output = JSONObject().put("capturedAt", timestamp.toLong())
        for (key in listOf("landingHost", "referrerHost", "landingPath", "utmSource", "utmMedium", "utmCampaign")) {
            val value = input.opt(key) as? String ?: return null
            if (value.any { it.code < 32 || it.code in 127..159 }) return null
            val normalized = when (key) {
                "landingHost", "referrerHost" -> {
                    val host = value.lowercase(java.util.Locale.ROOT)
                    if (host.length > 253 || !(host.isEmpty() && key == "referrerHost") &&
                        (!Regex("^[a-z0-9.-]+$").matches(host) || host.split('.').any {
                            it.isEmpty() || it.length > 63 || it.startsWith('-') || it.endsWith('-')
                        })) return null
                    host
                }
                "landingPath" -> {
                    if (!value.startsWith('/') || value.startsWith("//") || value.contains('\\') ||
                        Regex("%0[0-9a-f]|%1[0-9a-f]|%7f", RegexOption.IGNORE_CASE).containsMatchIn(value)) return null
                    value.substringBefore('?').substringBefore('#').take(256)
                }
                else -> {
                    if (value.length > 120 || !Regex("^[\\p{L}\\p{N}\\p{M} ._/-]*$").matches(value)) return null
                    value.trim()
                }
            }
            output.put(key, normalized)
        }
        return output
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
                String(Base64.getUrlDecoder().decode(padded(encoded)), Charsets.UTF_8),
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
        URLEncoder.encode(value, Charsets.UTF_8.name())

    private fun decode(value: String): String =
        URLDecoder.decode(value, Charsets.UTF_8.name())

    private fun padded(value: String): String =
        value + "=".repeat((4 - value.length % 4) % 4)
}
