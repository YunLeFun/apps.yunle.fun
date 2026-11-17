package `fun`.yunle.apps.account

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

interface AccountAuthenticating {
    suspend fun passwordSignIn(
        identifier: String,
        password: String,
        deviceID: String,
        captcha: String? = null,
    ): AuthTokenResponse

    suspend fun sendVerification(
        address: VerificationAddress,
        deviceID: String,
        captcha: String? = null,
    ): VerificationChallenge

    suspend fun verify(
        challenge: VerificationChallenge,
        code: String,
        deviceID: String,
        captcha: String? = null,
    ): AuthTokenResponse

    suspend fun refresh(refreshToken: String, deviceID: String): AuthTokenResponse
    suspend fun user(accessToken: String, deviceID: String): AccountUser
    suspend fun signOut(accessToken: String, deviceID: String)
    suspend fun updateProfile(
        userID: String,
        name: String,
        description: String,
        accessToken: String,
        deviceID: String,
    )

    suspend fun captcha(deviceID: String): CaptchaImage
    suspend fun verifyCaptcha(token: String, text: String, deviceID: String): String
}

class CloudbaseAuthService(
    private val origin: String = GATEWAY_ORIGIN,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) : AccountAuthenticating {

    override suspend fun passwordSignIn(
        identifier: String,
        password: String,
        deviceID: String,
        captcha: String?,
    ): AuthTokenResponse {
        val normalizedIdentifier = VerificationAddress.passwordIdentifier(identifier)
        if (password.isEmpty()) throw AccountException(AccountError.MISSING_PASSWORD)
        val json = requestJson(
            path = "signin",
            fields = mapOf("username" to normalizedIdentifier, "password" to password),
            deviceID = deviceID,
            captcha = captcha,
        )
        return AuthTokenResponse.fromJson(json)
    }

    override suspend fun sendVerification(
        address: VerificationAddress,
        deviceID: String,
        captcha: String?,
    ): VerificationChallenge {
        val fields = address.requestFields.toMutableMap()
        fields["target"] = "ANY"
        val json = requestJson(
            path = "verification",
            fields = fields,
            deviceID = deviceID,
            captcha = captcha,
        )
        val verificationId = json.optString("verification_id")
        val expiresIn = json.optInt("expires_in", 0)
        if (verificationId.isEmpty() || expiresIn <= 0) {
            throw AccountException(AccountError.INVALID_RESPONSE)
        }
        return VerificationChallenge(
            address = address,
            id = verificationId,
            isExistingUser = json.optBoolean("is_user", false),
            expiresAtMillis = nowMillis() + expiresIn * 1000L,
        )
    }

    override suspend fun verify(
        challenge: VerificationChallenge,
        code: String,
        deviceID: String,
        captcha: String?,
    ): AuthTokenResponse {
        if (challenge.expiresAtMillis <= nowMillis()) {
            throw AccountException(AccountError.VERIFICATION_EXPIRED)
        }
        if (code.length != 6 || !code.all { it in '0'..'9' }) {
            throw AccountException(AccountError.INVALID_VERIFICATION)
        }
        val verifiedJson = requestJson(
            path = "verification/verify",
            fields = mapOf("verification_id" to challenge.id, "verification_code" to code),
            deviceID = deviceID,
            captcha = captcha,
        )
        val verificationToken = verifiedJson.optString("verification_token")
        if (verificationToken.isEmpty()) {
            throw AccountException(AccountError.INVALID_RESPONSE)
        }
        val fields = if (challenge.isExistingUser) {
            mutableMapOf()
        } else {
            challenge.address.requestFields.toMutableMap()
        }
        fields["verification_token"] = verificationToken
        val authJson = requestJson(
            path = if (challenge.isExistingUser) "signin" else "signup",
            fields = fields,
            deviceID = deviceID,
            captcha = captcha,
        )
        return AuthTokenResponse.fromJson(authJson)
    }

    override suspend fun refresh(refreshToken: String, deviceID: String): AuthTokenResponse {
        val json = requestJson(
            path = "token",
            fields = mapOf("grant_type" to "refresh_token", "refresh_token" to refreshToken),
            deviceID = deviceID,
        )
        return AuthTokenResponse.fromJson(json)
    }

    override suspend fun user(accessToken: String, deviceID: String): AccountUser {
        val json = requestJson(
            path = "user/me",
            method = "GET",
            fields = null,
            accessToken = accessToken,
            deviceID = deviceID,
        )
        return AccountUser.fromJson(json)
    }

    override suspend fun signOut(accessToken: String, deviceID: String) {
        requestData(
            path = "user/signout",
            fields = emptyMap(),
            accessToken = accessToken,
            deviceID = deviceID,
        )
    }

    override suspend fun updateProfile(
        userID: String,
        name: String,
        description: String,
        accessToken: String,
        deviceID: String,
    ) {
        requestData(
            path = "user/basic/edit",
            fields = mapOf(
                "user_id" to userID,
                "nickname" to name,
                "description" to description,
            ),
            accessToken = accessToken,
            deviceID = deviceID,
        )
    }

    override suspend fun captcha(deviceID: String): CaptchaImage {
        val json = requestJson(path = "captcha/data", fields = emptyMap(), deviceID = deviceID)
        val data = json.optString("data")
        val type = json.optString("type")
        val token = json.optString("token")
        val expiresIn = json.optInt("expires_in", 0)
        if (data.isEmpty() || token.isEmpty()) throw AccountException(AccountError.INVALID_RESPONSE)
        return CaptchaImage(data = data, type = type, token = token, expiresIn = expiresIn)
    }

    override suspend fun verifyCaptcha(token: String, text: String, deviceID: String): String {
        val json = requestJson(
            path = "captcha/data/verify",
            fields = mapOf("token" to token, "key" to text),
            deviceID = deviceID,
        )
        val verifiedToken = json.optString("token")
        if (verifiedToken.isEmpty()) throw AccountException(AccountError.INVALID_RESPONSE)
        return verifiedToken
    }

    private suspend fun requestJson(
        path: String,
        method: String = "POST",
        fields: Map<String, String>? = null,
        accessToken: String? = null,
        deviceID: String,
        captcha: String? = null,
    ): JSONObject {
        val body = requestData(path, method, fields, accessToken, deviceID, captcha)
        return try {
            JSONObject(body)
        } catch (e: Throwable) {
            throw AccountException(AccountError.INVALID_RESPONSE, e)
        }
    }

    private suspend fun requestData(
        path: String,
        method: String = "POST",
        fields: Map<String, String>? = null,
        accessToken: String? = null,
        deviceID: String,
        captcha: String? = null,
    ): String = withContext(Dispatchers.IO) {
        val endpoint = URL("${origin.trimEnd('/')}/auth/v1/$path")
        val conn = (endpoint.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("x-device-id", deviceID)
            if (accessToken != null) {
                setRequestProperty("Authorization", "Bearer $accessToken")
            }
            if (captcha != null) {
                setRequestProperty("x-captcha-token", captcha)
            }
        }
        try {
            if (fields != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                val payload = JSONObject(fields).toString().toByteArray(Charsets.UTF_8)
                conn.outputStream.use { it.write(payload) }
            }
            val statusCode = conn.responseCode
            val stream = if (statusCode in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (statusCode !in 200..299) {
                val failure = runCatching { JSONObject(text) }.getOrNull()
                val errorCodeStr = failure?.optString("error")?.takeIf { it.isNotEmpty() }
                val numericCode = failure?.optInt("error_code", -1) ?: -1
                if (path == "user/me" && statusCode == 400 &&
                    ((errorCodeStr == "failed_precondition" && numericCode == 9) || errorCodeStr == "user_not_found")
                ) {
                    throw AccountException(AccountError.EXPIRED_SESSION)
                }
                throw AccountException(mapError(statusCode, errorCodeStr))
            }
            text
        } catch (e: AccountException) {
            throw e
        } catch (e: IOException) {
            throw e
        } catch (e: Throwable) {
            throw AccountException(AccountError.UNAVAILABLE, e)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        const val GATEWAY_ORIGIN = "https://yunlefun-8g7ybcxc7345c490.api.tcloudbasegateway.com"

        fun mapError(status: Int, code: String?): AccountError = when (code) {
            "invalid_grant", "invalid_token", "unauthenticated", "access_token_expired" ->
                AccountError.EXPIRED_SESSION
            "invalid_username_or_password", "user_not_found", "password_not_set" ->
                AccountError.INVALID_CREDENTIALS
            "captcha_required" -> AccountError.CAPTCHA_REQUIRED
            "invalid_captcha", "invalid_captcha_token" -> AccountError.INVALID_CAPTCHA
            "invalid_verification_code", "invalid_verification_token", "verification_expired" ->
                AccountError.INVALID_VERIFICATION
            "invalid_status", "user_disabled" -> AccountError.BLOCKED_ACCOUNT
            else -> when (status) {
                429 -> AccountError.RATE_LIMITED
                401 -> AccountError.EXPIRED_SESSION
                else -> AccountError.UNAVAILABLE
            }
        }
    }
}
