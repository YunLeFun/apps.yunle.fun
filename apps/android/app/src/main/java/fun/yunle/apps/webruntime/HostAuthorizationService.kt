package `fun`.yunle.apps.webruntime

import `fun`.yunle.apps.HostSsoProtocol
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.account.CloudbaseAuthService
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.Locale
import kotlin.math.floor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

enum class HostAuthorizationError(val code: String) {
    INVALID_REQUEST("HOST_AUTH_INVALID_REQUEST"),
    INVALID_RESPONSE("HOST_AUTH_FAILED"),
    UNAUTHORIZED("HOST_AUTH_FAILED"),
    DENIED("HOST_AUTH_DENIED"),
    UNAVAILABLE("HOST_AUTH_FAILED"),
    EXPIRED("HOST_AUTH_FAILED"),
}

class HostAuthorizationException(val error: HostAuthorizationError, cause: Throwable? = null) :
    Exception(error.code, cause)

data class HostSsoRequest(
    val clientID: String,
    val sourceOrigin: String,
    val redirectURI: String,
    val nonce: String,
    val challenge: String,
    val prompt: String?,
    val acquisitionJSON: String?,
) {
    fun protocolFields(): JSONObject = JSONObject().apply {
        put("mode", "redirect")
        put("clientId", clientID)
        put("targetOrigin", sourceOrigin)
        put("returnUrl", redirectURI)
        put("scope", "identity:bootstrap")
        put("nonce", nonce)
        put("codeChallenge", challenge)
        put("codeChallengeMethod", "S256")
        if (acquisitionJSON != null) {
            runCatching { JSONObject(acquisitionJSON) }.getOrNull()?.let { put("acquisition", it) }
        }
    }

    companion object {
        private val CLIENT_ID_RE = Regex("^[a-z0-9][a-z0-9-]{1,127}$")
        private val NONCE_RE = Regex("^[A-Za-z0-9_-]{32,128}$")
        private val CHALLENGE_RE = Regex("^[A-Za-z0-9_-]{43}$")

        fun parse(sourceOrigin: String, parameters: JSONObject): HostSsoRequest {
            val normalizedOrigin = validateOrigin(sourceOrigin)
                ?: throw HostAuthorizationException(HostAuthorizationError.INVALID_REQUEST)
            val client = parameters.optString("clientId")
            val redirect = parameters.optString("redirectUri")
            val nonce = parameters.optString("nonce")
            val challenge = parameters.optString("codeChallenge")
            val method = parameters.optString("codeChallengeMethod")
            val scopeArray = parameters.optJSONArray("scope")
            val scopeValid = scopeArray != null && scopeArray.length() == 1 &&
                scopeArray.optString(0) == "identity:bootstrap"
            val prompt = if (parameters.has("prompt") && !parameters.isNull("prompt")) {
                parameters.optString("prompt")
            } else {
                null
            }
            val promptValid = prompt == null || prompt == "consent" || prompt == "select_account"
            if (!CLIENT_ID_RE.matches(client) ||
                validateHttpsUrl(redirect) == null ||
                originOfUrl(redirect) != normalizedOrigin ||
                !NONCE_RE.matches(nonce) ||
                !CHALLENGE_RE.matches(challenge) ||
                method != "S256" ||
                !scopeValid ||
                !promptValid
            ) {
                throw HostAuthorizationException(HostAuthorizationError.INVALID_REQUEST)
            }
            val acquisition = HostSsoProtocol.readAcquisitionJson(parameters.opt("acquisition"))
            return HostSsoRequest(
                clientID = client,
                sourceOrigin = normalizedOrigin,
                redirectURI = redirect,
                nonce = nonce,
                challenge = challenge,
                prompt = prompt,
                acquisitionJSON = acquisition,
            )
        }

        internal fun validateHttpsUrl(value: String): URI? {
            if (value.any { it.code <= 32 || it.code in 127..159 }) return null
            val uri = runCatching { URI(value) }.getOrNull() ?: return null
            val host = uri.host ?: return null
            if (uri.scheme != "https" ||
                host != host.lowercase(Locale.ROOT) ||
                host.isEmpty() ||
                host.endsWith(".") ||
                uri.rawUserInfo != null ||
                uri.rawFragment != null ||
                uri.port == 443 ||
                !uri.rawPath.orEmpty().startsWith("/") ||
                uri.toString() != value ||
                uri.normalize().toString() != value
            ) {
                return null
            }
            return uri
        }

        internal fun validateOrigin(value: String): String? {
            if (value.any { it.code <= 32 || it.code in 127..159 }) return null
            val uri = runCatching { URI(value) }.getOrNull() ?: return null
            val host = uri.host ?: return null
            if (uri.scheme != "https" ||
                host != host.lowercase(Locale.ROOT) ||
                host.isEmpty() ||
                host.endsWith(".") ||
                uri.rawUserInfo != null ||
                uri.rawQuery != null ||
                uri.rawFragment != null ||
                !uri.rawPath.isNullOrEmpty() ||
                uri.port == 443 ||
                uri.toString() != value
            ) {
                return null
            }
            return value
        }

        private fun originOfUrl(value: String): String? {
            val uri = runCatching { URI(value) }.getOrNull() ?: return null
            val scheme = uri.scheme ?: return null
            val authority = uri.rawAuthority ?: return null
            return "$scheme://$authority"
        }
    }
}

data class HostSsoPolicy(
    val applicationID: String,
    val applicationName: String,
    val applicationOrigin: String,
    val applicationIconURL: String?,
    val permissionDescription: String,
    val prompt: String?,
    val version: String,
    val registrationFingerprint: String,
) {
    companion object {
        const val ISSUER = "https://www.yunle.fun"
        private val FINGERPRINT_RE = Regex("^[a-f0-9]{64}$")
        private val APP_ID_RE = Regex("^[a-z0-9][a-z0-9-]{0,127}$")

        fun parse(response: JSONObject, request: HostSsoRequest): HostSsoPolicy {
            val body = response.optJSONObject("result") ?: response
            val ok = body.opt("ok") as? Boolean
            if (ok == false) throw HostAuthorizationException(HostAuthorizationError.INVALID_REQUEST)
            val version = body.optString("policyVersion")
            val fingerprint = body.optString("registrationFingerprint")
            val echo = body.optJSONObject("request")
            val presentation = body.optJSONObject("presentation")
            val appID = presentation?.optString("appId").orEmpty()
            val name = presentation?.optString("applicationName").orEmpty()
            val consent = presentation?.optString("consent").orEmpty()
            if (ok != true ||
                body.optString("issuer") != ISSUER ||
                version.isEmpty() || version.length > 128 ||
                !FINGERPRINT_RE.matches(fingerprint) ||
                echo == null ||
                presentation == null ||
                !APP_ID_RE.matches(appID) ||
                name.isEmpty() || name.length > 80 || name != name.trim() ||
                presentation.optString("applicationOrigin") != request.sourceOrigin ||
                presentation.optString("permissionDescription") != "账号标识、昵称和头像" ||
                (consent != "explicit" && consent != "trusted")
            ) {
                throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
            }
            val expectedFields = request.protocolFields()
            for (key in expectedFields.keys()) {
                if (key == "acquisition") continue
                if (echo.optString(key) != expectedFields.optString(key)) {
                    throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
                }
            }
            val prompt = if (presentation.has("prompt") && !presentation.isNull("prompt")) {
                presentation.optString("prompt")
            } else {
                null
            }
            val promptAllowed = prompt == null || prompt == "consent" || prompt == "select_account"
            val promptMatchesRequest = if (request.prompt != null) {
                prompt == request.prompt
            } else {
                prompt == null || prompt == "consent"
            }
            val consentValid = consent != "explicit" || prompt == "consent" || prompt == "select_account"
            if (!promptAllowed || !promptMatchesRequest || !consentValid) {
                throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
            }
            val iconUrl = if (presentation.has("applicationIconUrl") && !presentation.isNull("applicationIconUrl")) {
                val rawIcon = presentation.opt("applicationIconUrl") as? String
                    ?: throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
                if (HostSsoRequest.validateHttpsUrl(rawIcon) == null) {
                    throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
                }
                rawIcon
            } else {
                null
            }
            return HostSsoPolicy(
                applicationID = appID,
                applicationName = name,
                applicationOrigin = request.sourceOrigin,
                applicationIconURL = iconUrl,
                permissionDescription = "账号标识、昵称和头像",
                prompt = prompt,
                version = version,
                registrationFingerprint = fingerprint,
            )
        }
    }
}

data class HostSsoCode(
    val code: String,
    val expiresAt: Long?,
) {
    fun toPageResult(): JSONObject = JSONObject().apply {
        put("ok", true)
        put("code", code)
        put("issuer", HostSsoPolicy.ISSUER)
        expiresAt?.let { put("expiresAt", it) }
    }

    companion object {
        private val CODE_RE = Regex("^[A-Za-z0-9_-]{43}$")

        fun parse(response: JSONObject): HostSsoCode {
            val body = response.optJSONObject("result") ?: response
            val ok = body.opt("ok") as? Boolean
            val code = body.optString("code")
            if (ok != true || !CODE_RE.matches(code)) {
                throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
            }
            val expiresAt: Long? = if (body.has("expiresAt") && !body.isNull("expiresAt")) {
                val raw = body.opt("expiresAt")
                if (raw is Boolean || raw !is Number) {
                    throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
                }
                val d = raw.toDouble()
                if (!d.isFinite() || d < 0 || d > 9_007_199_254_740_991.0 || floor(d) != d) {
                    throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
                }
                d.toLong()
            } else {
                null
            }
            return HostSsoCode(code = code, expiresAt = expiresAt)
        }
    }
}

interface HostAuthorizationServing {
    suspend fun resolve(request: HostSsoRequest): HostSsoPolicy
    suspend fun issue(request: HostSsoRequest, identity: AuthorizedAccount): HostSsoCode
}

class HostAuthorizationService(
    private val resolverUrl: String = "https://apps.yunle.fun/api/auth/sso/resolve",
    private val gatewayOrigin: String = CloudbaseAuthService.GATEWAY_ORIGIN,
) : HostAuthorizationServing {

    override suspend fun resolve(request: HostSsoRequest): HostSsoPolicy {
        val fields = request.protocolFields()
        request.prompt?.let { fields.put("prompt", it) }
        val response = send(resolverUrl, fields, token = null)
        return HostSsoPolicy.parse(response, request)
    }

    override suspend fun issue(request: HostSsoRequest, identity: AuthorizedAccount): HostSsoCode {
        val fields = request.protocolFields().apply {
            put("action", "issueSsoCode")
        }
        val response = send(
            url = "${gatewayOrigin.trimEnd('/')}/v1/functions/sso-ticket",
            fields = fields,
            token = identity.accessToken,
        )
        return HostSsoCode.parse(response)
    }

    private suspend fun send(url: String, fields: JSONObject, token: String?): JSONObject =
        withContext(Dispatchers.IO) {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                instanceFollowRedirects = false
                useCaches = false
                connectTimeout = 15_000
                readTimeout = 25_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
                if (token != null) {
                    setRequestProperty("Authorization", "Bearer $token")
                }
            }
            try {
                val payload = fields.toString().toByteArray(Charsets.UTF_8)
                conn.outputStream.use { it.write(payload) }
                val status = conn.responseCode
                if (status == 401) {
                    throw HostAuthorizationException(HostAuthorizationError.UNAUTHORIZED)
                }
                if (status !in 200..299) {
                    throw HostAuthorizationException(HostAuthorizationError.UNAVAILABLE)
                }
                val bytes = conn.inputStream.use { it.readBytes() }
                if (bytes.size > 128 * 1024) {
                    throw HostAuthorizationException(HostAuthorizationError.INVALID_RESPONSE)
                }
                JSONObject(String(bytes, Charsets.UTF_8))
            } catch (e: HostAuthorizationException) {
                throw e
            } catch (e: Throwable) {
                throw HostAuthorizationException(HostAuthorizationError.UNAVAILABLE, e)
            } finally {
                conn.disconnect()
            }
        }
}
