package `fun`.yunle.apps.account

import java.io.IOException
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

data class AccountUser(
    val id: String,
    val name: String? = null,
    val username: String? = null,
    val email: String? = null,
    val phoneNumber: String? = null,
    val picture: String? = null,
    val description: String? = null,
    val status: String? = null,
    val isAnonymous: Boolean? = null,
) {
    val displayName: String
        get() = name?.takeIf { it.isNotBlank() }
            ?: username?.takeIf { it.isNotBlank() }
            ?: "云乐坊用户"

    val detail: String
        get() {
            username?.takeIf { it.isNotBlank() }?.let { return "@$it" }
            phoneNumber?.takeIf { it.isNotBlank() }?.let { phone ->
                val digits = phone.filter { it.isDigit() }
                return if (digits.length >= 7) {
                    "${digits.take(3)}••••${digits.takeLast(4)}"
                } else {
                    "手机号账号"
                }
            }
            email?.takeIf { it.isNotBlank() }?.let { rawEmail ->
                val at = rawEmail.indexOf('@')
                if (at > 0) {
                    return "${rawEmail.take(1)}•••${rawEmail.substring(at)}"
                }
            }
            return "云乐坊账号"
        }

    val isUsable: Boolean
        get() = id.isNotEmpty() && isAnonymous != true && status != "BLOCKED"

    fun toJson(): JSONObject = JSONObject().apply {
        put("sub", id)
        name?.let { put("name", it) }
        username?.let { put("username", it) }
        email?.let { put("email", it) }
        phoneNumber?.let { put("phone_number", it) }
        picture?.let { put("picture", it) }
        description?.let { put("user_desc", it) }
        status?.let { put("status", it) }
        isAnonymous?.let { put("is_anonymous", it) }
    }

    companion object {
        fun fromJson(json: JSONObject): AccountUser {
            val id = json.optString("sub").trim()
            if (id.isEmpty()) throw AccountException(AccountError.INVALID_RESPONSE)
            return AccountUser(
                id = id,
                name = json.optString("name").takeIf { it.isNotEmpty() && !json.isNull("name") },
                username = json.optString("username").takeIf { it.isNotEmpty() && !json.isNull("username") },
                email = json.optString("email").takeIf { it.isNotEmpty() && !json.isNull("email") },
                phoneNumber = json.optString("phone_number").takeIf { it.isNotEmpty() && !json.isNull("phone_number") },
                picture = resolvePicture(json),
                description = json.optString("user_desc").takeIf { it.isNotEmpty() && !json.isNull("user_desc") },
                status = json.optString("status").takeIf { it.isNotEmpty() && !json.isNull("status") },
                isAnonymous = if (json.has("is_anonymous") && !json.isNull("is_anonymous")) {
                    json.optBoolean("is_anonymous")
                } else {
                    null
                },
            )
        }

        private fun resolvePicture(json: JSONObject): String? {
            fun JSONObject.nonEmptyString(key: String): String? =
                if (!has(key) || isNull(key)) null
                else optString(key).trim().takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }

            val metadata = json.optJSONObject("user_metadata")
            return json.nonEmptyString("picture")
                ?: metadata?.nonEmptyString("avatarUrl")
                ?: metadata?.nonEmptyString("picture")
                ?: json.nonEmptyString("avatarUrl")
                ?: json.nonEmptyString("avatar")
        }
    }
}

data class AuthTokenResponse(
    val accessToken: String,
    val refreshToken: String,
    val expiresIn: Int,
    val subject: String,
) {
    fun credential(nowMillis: Long): AccountCredential {
        if (accessToken.isEmpty() || refreshToken.isEmpty() || subject.isEmpty() || expiresIn <= 0) {
            throw AccountException(AccountError.INVALID_RESPONSE)
        }
        return AccountCredential(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAtMillis = nowMillis + expiresIn * 1000L,
        )
    }

    companion object {
        fun fromJson(json: JSONObject): AuthTokenResponse = AuthTokenResponse(
            accessToken = json.optString("access_token"),
            refreshToken = json.optString("refresh_token"),
            expiresIn = json.optInt("expires_in", 0),
            subject = json.optString("sub"),
        )
    }
}

data class AccountCredential(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMillis: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("accessToken", accessToken)
        .put("refreshToken", refreshToken)
        .put("expiresAtMillis", expiresAtMillis)

    companion object {
        fun fromJson(json: JSONObject): AccountCredential = AccountCredential(
            accessToken = json.optString("accessToken"),
            refreshToken = json.optString("refreshToken"),
            expiresAtMillis = json.optLong("expiresAtMillis", 0L),
        )
    }
}

data class SavedAccount(
    val user: AccountUser,
    val credential: AccountCredential,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("user", user.toJson())
        .put("credential", credential.toJson())

    companion object {
        fun fromJson(json: JSONObject): SavedAccount = SavedAccount(
            user = AccountUser.fromJson(json.getJSONObject("user")),
            credential = AccountCredential.fromJson(json.getJSONObject("credential")),
        )
    }
}

data class AccountVaultState(
    val version: Int = 1,
    val deviceID: String = UUID.randomUUID().toString(),
    val accounts: List<SavedAccount> = emptyList(),
    val activeID: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("version", version)
        put("deviceID", deviceID)
        put("accounts", JSONArray().apply { accounts.forEach { put(it.toJson()) } })
        activeID?.let { put("activeID", it) }
    }

    companion object {
        fun fromJson(json: JSONObject): AccountVaultState {
            val version = json.optInt("version", 1)
            if (version != 1) throw AccountException(AccountError.UNSUPPORTED_VAULT)
            val deviceID = json.optString("deviceID").takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString()
            val array = json.optJSONArray("accounts") ?: JSONArray()
            val accounts = buildList {
                for (i in 0 until array.length()) {
                    add(SavedAccount.fromJson(array.getJSONObject(i)))
                }
            }
            val activeID = json.optString("activeID").takeIf { it.isNotBlank() && !json.isNull("activeID") }
            return AccountVaultState(
                version = version,
                deviceID = deviceID,
                accounts = accounts,
                activeID = activeID,
            )
        }
    }
}

data class AccountOverview(
    val revision: Int = 0,
    val users: List<AccountUser> = emptyList(),
    val activeID: String? = null,
) {
    val activeUser: AccountUser?
        get() = users.firstOrNull { it.id == activeID }
}

data class AuthorizedAccount(
    val userID: String,
    val accessToken: String,
)

sealed class VerificationAddress {
    data class Phone(val number: String) : VerificationAddress()
    data class Email(val email: String) : VerificationAddress()

    val requestFields: Map<String, String>
        get() = when (this) {
            is Phone -> mapOf("phone_number" to number)
            is Email -> mapOf("email" to email)
        }

    companion object {
        fun normalizedPhoneInput(input: String): String {
            val digitsBuilder = StringBuilder()
            for (ch in input) {
                if (Character.getType(ch) == Character.DECIMAL_DIGIT_NUMBER.toInt()) {
                    val numeric = Character.getNumericValue(ch)
                    if (numeric in 0..9) digitsBuilder.append(numeric)
                }
            }
            var digits = digitsBuilder.toString()
            val firstRelevant = input.firstOrNull { it.isDigit() || it == '+' }
            val international = firstRelevant == '+'
            if (international) {
                if (!digits.startsWith("86")) return "+$digits"
                digits = digits.removePrefix("86")
            } else if (digits.startsWith("0086")) {
                digits = digits.removePrefix("0086")
            } else if (digits.startsWith("86") && digits.length > 11) {
                digits = digits.removePrefix("86")
            }
            return digits.take(11)
        }

        fun isMainlandMobile(number: String): Boolean =
            number.length == 11 && number.startsWith("1")

        private fun isFormatting(ch: Char): Boolean =
            Character.getType(ch) == Character.FORMAT.toInt()

        fun phoneInput(input: String): VerificationAddress {
            val trimmed = input.trim()
            if (!trimmed.all { it.isDigit() || it.isWhitespace() || "+-()".contains(it) || isFormatting(it) }) {
                throw AccountException(AccountError.INVALID_PHONE)
            }
            val number = normalizedPhoneInput(trimmed)
            if (number.startsWith("+") && number.length > 2) {
                throw AccountException(AccountError.UNSUPPORTED_PHONE_REGION)
            }
            if (!isMainlandMobile(number)) {
                throw AccountException(AccountError.INVALID_PHONE)
            }
            return Phone("+86 $number")
        }

        fun emailInput(input: String): VerificationAddress {
            val value = input.trim()
            val parts = value.split("@")
            if (parts.size != 2 || parts[0].isEmpty() || !parts[1].contains(".") || value.any { it.isWhitespace() }) {
                throw AccountException(AccountError.INVALID_EMAIL)
            }
            return Email(value)
        }

        fun passwordIdentifier(input: String): String {
            val value = input.trim()
            if (value.isEmpty()) throw AccountException(AccountError.MISSING_IDENTIFIER)
            if (value.contains("@")) {
                return (emailInput(value) as Email).email
            }
            val phoneLike = value.all { it.isDigit() || it.isWhitespace() || "+-()".contains(it) || isFormatting(it) }
            if (value.startsWith("+86") || (phoneLike && isMainlandMobile(normalizedPhoneInput(value)))) {
                return (phoneInput(value) as Phone).number
            }
            return value
        }
    }
}

data class VerificationChallenge(
    val address: VerificationAddress,
    val id: String,
    val isExistingUser: Boolean,
    val expiresAtMillis: Long,
)

data class CaptchaImage(
    val data: String,
    val type: String,
    val token: String,
    val expiresIn: Int,
)

enum class AccountError(val message: String) {
    INVALID_RESPONSE("账号服务暂时无法使用，请稍后重试。"),
    SESSION_CHANGED("账号已发生变化，请重新操作。"),
    SIGNED_OUT("请先登录云乐坊账号。"),
    EXPIRED_SESSION("登录已过期，请重新登录。"),
    BLOCKED_ACCOUNT("当前账号暂时无法登录，请联系支持。"),
    INVALID_CREDENTIALS("账号或密码不正确，请检查后重试。"),
    INVALID_VERIFICATION("验证码不正确或已过期，请重新获取。"),
    CAPTCHA_REQUIRED("请先完成图片验证。"),
    INVALID_CAPTCHA("图片验证码不正确，请重试。"),
    RATE_LIMITED("操作有些频繁，请稍后再试。"),
    UNAVAILABLE("暂时无法连接账号服务，请稍后重试。"),
    INVALID_PHONE("请输入正确的中国大陆手机号。"),
    UNSUPPORTED_PHONE_REGION("暂时只支持中国大陆（+86）手机号，其他地区请使用邮箱登录。"),
    INVALID_EMAIL("请输入正确的邮箱地址。"),
    MISSING_IDENTIFIER("请输入用户名、邮箱或手机号。"),
    MISSING_PASSWORD("请输入密码。"),
    VERIFICATION_EXPIRED("验证码已过期，请重新获取。"),
    STORAGE("无法安全保存账号，请解锁设备后重试。"),
    UNSUPPORTED_VAULT("本机账号数据暂时无法读取，原有数据已保留。");

    companion object {
        fun messageFor(throwable: Throwable): String = when (throwable) {
            is AccountException -> throwable.error.message
            is IOException -> "网络暂时无法连接，请检查网络后重试。"
            else -> "操作未能完成，请稍后重试。"
        }
    }
}

class AccountException(val error: AccountError, cause: Throwable? = null) : Exception(error.message, cause)

data class AccountRequestBoundary(
    val uid: String?,
    val generation: UUID,
)

data class AccountSignInCommit(
    val attemptID: UUID,
    val userID: String,
    val selectionGeneration: Int,
)

data class AccountSignInContinuation(
    val requestID: UUID,
    val origin: AccountRequestBoundary,
)

data class AccountSignInSuccess(
    val requestID: UUID,
    val attemptID: UUID,
    val origin: AccountRequestBoundary,
    val target: AccountRequestBoundary,
)
