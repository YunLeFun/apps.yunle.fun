package `fun`.yunle.apps.catalog

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.readString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.TemporalAdjusters
import kotlin.math.floor

private const val MAX_JSON_BYTES = 2 * 1024 * 1024
private const val MAX_ECOSYSTEM_TIMESTAMP = 253_402_300_799_999L

private fun readStrictLong(raw: Any?): Long? {
    if (raw is Boolean || raw !is Number) return null
    val d = raw.toDouble()
    if (!d.isFinite() || floor(d) != d || d < Long.MIN_VALUE.toDouble() || d > Long.MAX_VALUE.toDouble()) {
        return null
    }
    return d.toLong()
}

private fun readStrictInt(raw: Any?): Int? {
    val l = readStrictLong(raw) ?: return null
    return if (l in Int.MIN_VALUE..Int.MAX_VALUE) l.toInt() else null
}

// region Developer Profile

internal enum class DeveloperProfileError(val defaultMessage: String) {
    INVALID_INPUT("开发者标识格式不正确。"),
    INVALID_RESPONSE("暂时无法读取开发者主页，请刷新后重试。"),
    NOT_FOUND("该开发者主页不存在或暂无公开应用。"),
    THROTTLED("操作较频繁，请稍后再试。"),
    UNAVAILABLE("暂时无法连接开发者主页，请检查网络后重试。");

    companion object {
        fun message(error: Throwable): String = when (error) {
            is DeveloperProfileException -> error.error.defaultMessage
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class DeveloperProfileException(
    val error: DeveloperProfileError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal data class DeveloperProfile(
    val ownerLogin: String,
    val items: List<CatalogApp>,
) {
    fun validate(requestedLogin: String) {
        if (!isValidLogin(ownerLogin) || ownerLogin != requestedLogin) {
            throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
        }
        if (items.map { it.id }.toSet().size != items.size) {
            throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
        }
        if (items.any {
                it.id.isEmpty() ||
                    it.name.isEmpty() ||
                    it.audience != "public" ||
                    it.personalMarketOwnerLogin != ownerLogin ||
                    it.accessWorkshopId != null ||
                    it.trustedHosts.isNotEmpty()
            }
        ) {
            throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
        }
    }

    companion object {
        private val LOGIN_RE = Regex("^[A-Za-z0-9_.-]{1,64}$")

        fun isValidLogin(raw: String): Boolean =
            raw.isNotEmpty() && raw != "." && raw != ".." && LOGIN_RE.matches(raw)

        fun fromJson(json: JSONObject, requestedLogin: String): DeveloperProfile {
            val ownerLogin = json.readString("ownerLogin")
                ?: throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
            val arr = json.optJSONArray("items")
                ?: throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
            if (arr.length() > 1000) throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
            val decoded = (0 until arr.length()).map { idx ->
                val obj = arr.optJSONObject(idx)
                    ?: throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
                val audience = obj.readString("audience")
                val isPublic = obj.opt("isPublic") == true
                val isUnavailable = obj.optBoolean("isUnavailable", false)
                val hasScopedRestriction = obj.readString("accessOwnerId") != null ||
                    obj.readString("accessOwnerID") != null ||
                    obj.readString("accessWorkshopId") != null ||
                    obj.readString("accessWorkshopID") != null
                if (audience != "public" || !isPublic || isUnavailable || hasScopedRestriction) {
                    throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
                }
                CatalogApp.readScoped(
                    record = obj,
                    allowWorkshopAudience = false,
                    personalMarketLogin = ownerLogin,
                    allowAuthorizedLaunch = false,
                ) ?: throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
            }
            return DeveloperProfile(ownerLogin = ownerLogin, items = decoded).also {
                it.validate(requestedLogin)
            }
        }
    }
}

internal interface DeveloperProfileServing {
    suspend fun profile(login: String): DeveloperProfile
}

internal class DeveloperProfileService(
    private val origin: String = "https://apps.yunle.fun",
) : DeveloperProfileServing {
    private val baseUrl = origin.trimEnd('/')

    override suspend fun profile(login: String): DeveloperProfile {
        val normalized = login.trim()
        if (!DeveloperProfile.isValidLogin(normalized)) {
            throw DeveloperProfileException(DeveloperProfileError.INVALID_INPUT)
        }
        val segment = URLEncoder.encode(normalized, Charsets.UTF_8.name()).replace("+", "%20")
        val json = withContext(Dispatchers.IO) {
            val conn = (URL("$baseUrl/api/markets/personal/$segment").openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                instanceFollowRedirects = false
                useCaches = false
                connectTimeout = 20_000
                readTimeout = 30_000
                setRequestProperty("Accept", "application/json")
            }
            try {
                when (conn.responseCode) {
                    400 -> throw DeveloperProfileException(DeveloperProfileError.INVALID_INPUT)
                    404 -> throw DeveloperProfileException(DeveloperProfileError.NOT_FOUND)
                    429 -> throw DeveloperProfileException(DeveloperProfileError.THROTTLED)
                    in 200..299 -> Unit
                    else -> throw DeveloperProfileException(DeveloperProfileError.UNAVAILABLE)
                }
                val bytes = readLimitedBytes(conn)
                    ?: throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
                JSONObject(bytes.toString(Charsets.UTF_8))
            } catch (e: DeveloperProfileException) {
                throw e
            } catch (t: Throwable) {
                throw DeveloperProfileException(DeveloperProfileError.UNAVAILABLE, t)
            } finally {
                conn.disconnect()
            }
        }
        return DeveloperProfile.fromJson(json, normalized)
    }
}

internal object PersonalMarketLaunchAuthorization {
    suspend fun resolve(app: CatalogApp, service: DeveloperProfileServing): CatalogApp {
        val login = app.personalMarketOwnerLogin
            ?: throw DeveloperProfileException(DeveloperProfileError.INVALID_INPUT)
        val profile = service.profile(login)
        val current = profile.items.firstOrNull { it.id == app.id }
            ?: throw DeveloperProfileException(DeveloperProfileError.NOT_FOUND)
        if (current.launchUrl == null) {
            throw DeveloperProfileException(DeveloperProfileError.INVALID_RESPONSE)
        }
        return current
    }
}

// endregion

// region Application Acquisition

internal enum class ApplicationAcquisitionState(val key: String) {
    ALLOWED("allowed"),
    MEMBERSHIP_REQUIRED("membership_required"),
    PURCHASE_REQUIRED("purchase_required"),
    INVITATION_REQUIRED("invitation_required");

    companion object {
        fun fromKey(raw: String?): ApplicationAcquisitionState? =
            entries.firstOrNull { it.key == raw }
    }
}

internal enum class ApplicationAcquisitionError(val defaultMessage: String) {
    INVALID_INPUT("请重新打开应用详情后再试。"),
    INVALID_RESPONSE("暂时无法核对应用权益，请稍后重试。"),
    UNAUTHORIZED("登录状态已失效，请重新登录后再试。"),
    NOT_FOUND("应用暂未上架或已下架。"),
    PRICE_CHANGED("应用价格已变化，请重新确认。"),
    INSUFFICIENT_COIN("云币余额不足，请先前往钱包充值。"),
    CONFLICT("应用权益状态已更新，请重新核对。"),
    THROTTLED("操作较频繁，请稍后再试。"),
    UNAVAILABLE("暂时无法连接权益核对服务，请检查网络后重试。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun message(error: Throwable): String = when (error) {
            is ApplicationAcquisitionException -> error.message
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class ApplicationAcquisitionException(
    val error: ApplicationAcquisitionError,
    cause: Throwable? = null,
    serverMessage: String? = null,
) : Exception(serverMessage?.takeIf { it.isNotBlank() } ?: error.defaultMessage, cause) {
    override val message: String
        get() = super.message ?: error.defaultMessage
}

internal data class ApplicationAcquisitionQuote(
    val userId: String,
    val application: CatalogApp,
    val state: ApplicationAcquisitionState,
    val reason: String,
    val coinCost: Int,
    val balance: Int,
) {
    fun validate(expectedUserId: String, expectedAppId: String) {
        if (userId != expectedUserId || application.id != expectedAppId || coinCost < 0 || balance < 0) {
            throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
        }
        val validCombo = when (state) {
            ApplicationAcquisitionState.ALLOWED ->
                reason in setOf("free", "member", "purchased") && application.launchUrl != null
            ApplicationAcquisitionState.MEMBERSHIP_REQUIRED -> reason == "membership"
            ApplicationAcquisitionState.PURCHASE_REQUIRED -> reason == "purchase" && coinCost > 0
            ApplicationAcquisitionState.INVITATION_REQUIRED -> reason == "invitation"
        }
        if (!validCombo) {
            throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(
            json: JSONObject,
            expectedUserId: String,
            expectedAppId: String,
        ): ApplicationAcquisitionQuote {
            val userId = json.readString("userId")
                ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            val state = ApplicationAcquisitionState.fromKey(json.readString("state"))
                ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            val reason = json.readString("reason")
                ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            val coinCost = readStrictInt(json.opt("coinCost"))
                ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            val balance = readStrictInt(json.opt("balance"))
                ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            val appObj = json.optJSONObject("application")
                ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            val app = CatalogApp.readScoped(
                record = appObj,
                allowWorkshopAudience = false,
                allowAuthorizedLaunch = (state == ApplicationAcquisitionState.ALLOWED),
            ) ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            return ApplicationAcquisitionQuote(
                userId = userId,
                application = app,
                state = state,
                reason = reason,
                coinCost = coinCost,
                balance = balance,
            ).also { it.validate(expectedUserId, expectedAppId) }
        }
    }
}

internal interface ApplicationAcquisitionServing {
    suspend fun check(appId: String, identity: AuthorizedAccount): ApplicationAcquisitionQuote
    suspend fun purchase(
        appId: String,
        expectedCoinCost: Int,
        identity: AuthorizedAccount,
    ): ApplicationAcquisitionQuote
}

internal class ApplicationAcquisitionService(
    private val origin: String = "https://apps.yunle.fun",
) : ApplicationAcquisitionServing {
    private val baseUrl = origin.trimEnd('/')

    override suspend fun check(
        appId: String,
        identity: AuthorizedAccount,
    ): ApplicationAcquisitionQuote {
        val validAppId = requireAppId(appId)
        val body = JSONObject()
            .put("action", "check")
            .put("appId", validAppId)
        return postAcquisition(validAppId, body, identity)
    }

    override suspend fun purchase(
        appId: String,
        expectedCoinCost: Int,
        identity: AuthorizedAccount,
    ): ApplicationAcquisitionQuote {
        val validAppId = requireAppId(appId)
        if (expectedCoinCost <= 0) {
            throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_INPUT)
        }
        val body = JSONObject()
            .put("action", "purchase")
            .put("appId", validAppId)
            .put("expectedCoinCost", expectedCoinCost)
        return postAcquisition(validAppId, body, identity)
    }

    private fun requireAppId(appId: String): String {
        val trimmed = appId.trim()
        if (!APP_ID_RE.matches(trimmed)) {
            throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_INPUT)
        }
        return trimmed
    }

    private suspend fun postAcquisition(
        appId: String,
        body: JSONObject,
        identity: AuthorizedAccount,
    ): ApplicationAcquisitionQuote = withContext(Dispatchers.IO) {
        val conn = (URL("$baseUrl/api/apps/acquisition").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            instanceFollowRedirects = false
            useCaches = false
            doOutput = true
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
        }
        try {
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val statusCode = conn.responseCode
            val stream = if (statusCode in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.use { input ->
                readStreamLimited(input)?.toString(Charsets.UTF_8)
                    ?: throw ApplicationAcquisitionException(ApplicationAcquisitionError.INVALID_RESPONSE)
            }.orEmpty()

            if (statusCode !in 200..299) {
                val errJson = runCatching { JSONObject(text) }.getOrNull()
                val msg = errJson?.readString("message")
                val errCode = errJson?.optJSONObject("data")?.readString("code")
                    ?: errJson?.readString("code")
                val error = when (statusCode) {
                    400 -> ApplicationAcquisitionError.INVALID_INPUT
                    401 -> ApplicationAcquisitionError.UNAUTHORIZED
                    404 -> ApplicationAcquisitionError.NOT_FOUND
                    409 -> when (errCode) {
                        "APP_PRICE_CHANGED" -> ApplicationAcquisitionError.PRICE_CHANGED
                        "APP_INSUFFICIENT_COIN" -> ApplicationAcquisitionError.INSUFFICIENT_COIN
                        else -> ApplicationAcquisitionError.CONFLICT
                    }
                    429 -> ApplicationAcquisitionError.THROTTLED
                    else -> ApplicationAcquisitionError.UNAVAILABLE
                }
                throw ApplicationAcquisitionException(error, serverMessage = msg)
            }

            ApplicationAcquisitionQuote.fromJson(
                json = JSONObject(text),
                expectedUserId = identity.userID,
                expectedAppId = appId,
            )
        } catch (e: ApplicationAcquisitionException) {
            throw e
        } catch (t: Throwable) {
            throw ApplicationAcquisitionException(ApplicationAcquisitionError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private val APP_ID_RE = Regex("^[A-Za-z0-9_-]{1,128}$")
    }
}

// endregion

// region Workshop Discovery

internal data class WorkshopDiscoveryFeatured(
    val appId: String,
    val title: String?,
    val subtitle: String?,
    val startsAt: Long,
    val expiresAt: Long,
)

internal data class WorkshopDiscoveryChartItem(
    val appId: String,
    val rank: Int,
)

internal data class WorkshopDiscoveryWeeklyChart(
    val weekStart: Long,
    val items: List<WorkshopDiscoveryChartItem>,
)

internal data class WorkshopDiscoveryPayload(
    val schemaVersion: Int,
    val generatedAt: Long,
    val featured: List<WorkshopDiscoveryFeatured>,
    val weeklyChart: WorkshopDiscoveryWeeklyChart?,
) {
    fun validate() {
        if (schemaVersion != 1 ||
            generatedAt !in 1..MAX_ECOSYSTEM_TIMESTAMP ||
            featured.size > 10 ||
            featured.map { it.appId }.toSet().size != featured.size ||
            featured.any {
                it.appId.isBlank() ||
                    it.startsAt !in 1..MAX_ECOSYSTEM_TIMESTAMP ||
                    it.expiresAt !in 1..MAX_ECOSYSTEM_TIMESTAMP ||
                    it.expiresAt <= it.startsAt
            }
        ) {
            throw IllegalStateException("Invalid discovery payload")
        }
        weeklyChart?.let { chart ->
            if (chart.weekStart !in 1..MAX_ECOSYSTEM_TIMESTAMP ||
                chart.items.size > 10 ||
                chart.items.any { it.appId.isBlank() || it.rank !in 1..10 } ||
                chart.items.map { it.appId }.toSet().size != chart.items.size ||
                chart.items.map { it.rank }.toSet().size != chart.items.size
            ) {
                throw IllegalStateException("Invalid discovery chart")
            }
            val ranks = chart.items.map { it.rank }
            if (ranks != ranks.sorted()) {
                throw IllegalStateException("Discovery chart ranks must be ascending")
            }
        }
    }

    companion object {
        fun fromJson(json: JSONObject): WorkshopDiscoveryPayload {
            val schemaVersion = readStrictInt(json.opt("schemaVersion"))
                ?: throw IllegalStateException("Missing schemaVersion")
            val generatedAt = readStrictLong(json.opt("generatedAt"))
                ?: throw IllegalStateException("Missing generatedAt")
            val featuredArr = json.optJSONArray("featured")
                ?: throw IllegalStateException("Missing featured")
            val featured = (0 until featuredArr.length()).map { idx ->
                val obj = featuredArr.optJSONObject(idx) ?: throw IllegalStateException("Invalid featured item")
                WorkshopDiscoveryFeatured(
                    appId = obj.readString("appId") ?: throw IllegalStateException("Missing featured appId"),
                    title = obj.readString("title")?.take(100),
                    subtitle = obj.readString("subtitle")?.take(240),
                    startsAt = readStrictLong(obj.opt("startsAt"))
                        ?: throw IllegalStateException("Missing startsAt"),
                    expiresAt = readStrictLong(obj.opt("expiresAt"))
                        ?: throw IllegalStateException("Missing expiresAt"),
                )
            }
            val chartObj = if (json.has("weeklyChart") && !json.isNull("weeklyChart")) {
                json.optJSONObject("weeklyChart") ?: throw IllegalStateException("Invalid weeklyChart")
            } else {
                null
            }
            val weeklyChart = chartObj?.let { chart ->
                val weekStart = readStrictLong(chart.opt("weekStart"))
                    ?: throw IllegalStateException("Missing weekStart")
                val itemsArr = chart.optJSONArray("items") ?: throw IllegalStateException("Missing chart items")
                val items = (0 until itemsArr.length()).map { idx ->
                    val item = itemsArr.optJSONObject(idx) ?: throw IllegalStateException("Invalid chart item")
                    WorkshopDiscoveryChartItem(
                        appId = item.readString("appId") ?: throw IllegalStateException("Missing chart appId"),
                        rank = readStrictInt(item.opt("rank")) ?: throw IllegalStateException("Missing rank"),
                    )
                }
                WorkshopDiscoveryWeeklyChart(weekStart = weekStart, items = items)
            }
            return WorkshopDiscoveryPayload(
                schemaVersion = schemaVersion,
                generatedAt = generatedAt,
                featured = featured,
                weeklyChart = weeklyChart,
            ).also { it.validate() }
        }
    }
}

internal data class WorkshopDiscoverySelection(
    val featuredApps: List<CatalogApp>,
    val weeklyChartApps: List<CatalogApp>,
) {
    companion object {
        fun gmtPlus8MondayStartMillis(nowMillis: Long): Long {
            val zone = ZoneOffset.ofHours(8)
            val localDate = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
            val monday = localDate.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            return monday.atStartOfDay(zone).toInstant().toEpochMilli()
        }

        fun select(
            payload: WorkshopDiscoveryPayload,
            catalogApps: List<CatalogApp>,
            nowMillis: Long = System.currentTimeMillis(),
        ): WorkshopDiscoverySelection {
            val byId = catalogApps.associateBy { it.id }
            val featuredApps = payload.featured
                .filter { it.startsAt <= nowMillis && it.expiresAt > nowMillis }
                .mapNotNull { byId[it.appId] }
                .distinctBy { it.id }
            val currentWeekStart = gmtPlus8MondayStartMillis(nowMillis)
            val chartApps = if (payload.weeklyChart?.weekStart == currentWeekStart) {
                payload.weeklyChart.items
                    .sortedBy { it.rank }
                    .mapNotNull { byId[it.appId] }
                    .distinctBy { it.id }
            } else {
                emptyList()
            }
            return WorkshopDiscoverySelection(featuredApps = featuredApps, weeklyChartApps = chartApps)
        }
    }
}

internal interface WorkshopDiscoveryServing {
    suspend fun fetch(): WorkshopDiscoveryPayload
}

internal class WorkshopDiscoveryService(
    private val origin: String = "https://apps.yunle.fun",
) : WorkshopDiscoveryServing {
    private val baseUrl = origin.trimEnd('/')

    override suspend fun fetch(): WorkshopDiscoveryPayload = withContext(Dispatchers.IO) {
        val conn = (URL("$baseUrl/api/catalog/discovery").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 10_000
            readTimeout = 15_000
            setRequestProperty("Accept", "application/json")
        }
        try {
            check(conn.responseCode in 200..299) { "Discovery HTTP ${conn.responseCode}" }
            val bytes = readLimitedBytes(conn) ?: throw IllegalStateException("Discovery response too large")
            WorkshopDiscoveryPayload.fromJson(JSONObject(bytes.toString(Charsets.UTF_8)))
        } finally {
            conn.disconnect()
        }
    }
}

// endregion

private fun readLimitedBytes(conn: HttpURLConnection): ByteArray? =
    conn.inputStream.use { readStreamLimited(it) }

private fun readStreamLimited(stream: java.io.InputStream): ByteArray? {
    val buffer = ByteArray(8192)
    val out = ByteArrayOutputStream()
    while (true) {
        val count = stream.read(buffer)
        if (count == -1) break
        if (out.size() + count > MAX_JSON_BYTES) return null
        out.write(buffer, 0, count)
    }
    return out.toByteArray()
}
