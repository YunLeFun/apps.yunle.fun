package `fun`.yunle.apps.community

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.readString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.abs
import kotlin.math.floor

internal enum class CommunityError(val defaultMessage: String) {
    INVALID_INPUT("请检查填写内容后再提交。"),
    INVALID_RESPONSE("暂时无法读取评价或举报信息，请刷新后重试。"),
    UNAUTHORIZED("登录状态已失效，请重新登录。"),
    FORBIDDEN("当前账号没有此权限，请刷新后再试。"),
    NOT_FOUND("该应用、评价或举报已不存在。"),
    CONFLICT("你已举报过该内容，或状态已发生变化。"),
    THROTTLED("操作较频繁，请稍后再试。"),
    UNAVAILABLE("暂时无法连接评价与举报服务，请检查网络后重试。"),
    IDENTITY_CHANGED("账号已变化，请重新打开此页面。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun message(error: Throwable): String = when (error) {
            is CommunityException -> error.message
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class CommunityException(
    val error: CommunityError,
    cause: Throwable? = null,
    serverMessage: String? = null,
) : Exception(serverMessage?.takeIf { it.isNotBlank() } ?: error.defaultMessage, cause) {
    override val message: String
        get() = super.message ?: error.defaultMessage
}

internal object CommunityValidation {
    const val MAX_TITLE_LENGTH = 100
    const val MAX_CONTENT_LENGTH = 1000
    const val MAX_REPORT_DETAIL_LENGTH = 500
    const val MAX_TIMESTAMP = 253_402_300_799_999L
    private val IDENTIFIER_RE = Regex("^[A-Za-z0-9._-]{1,128}$")

    fun isValidIdentifier(value: String?): Boolean {
        val candidate = value?.trim().orEmpty()
        return candidate.isNotEmpty() && candidate != "." && candidate != ".." && IDENTIFIER_RE.matches(candidate)
    }

    fun requireIdentifier(value: String?): String {
        val candidate = value?.trim().orEmpty()
        if (!isValidIdentifier(candidate)) throw CommunityException(CommunityError.INVALID_INPUT)
        return candidate
    }

    fun appKeyFor(app: CatalogApp): String? {
        val key = app.key.trim()
        if (isValidIdentifier(key)) return key
        val id = app.id.trim()
        return id.takeIf(::isValidIdentifier)
    }

    fun isValidTimestamp(value: Long): Boolean = value in 1..MAX_TIMESTAMP

    fun readOptionalTimestamp(json: JSONObject, key: String): Long? {
        if (!json.has(key) || json.isNull(key)) return null
        val raw = json.opt(key)
        if (raw is Boolean || raw !is Number) throw CommunityException(CommunityError.INVALID_RESPONSE)
        val d = raw.toDouble()
        if (!d.isFinite() || floor(d) != d) throw CommunityException(CommunityError.INVALID_RESPONSE)
        val v = d.toLong()
        return v.takeIf { it > 0L }
    }

    fun readRequiredTimestamp(json: JSONObject, key: String): Long =
        readOptionalTimestamp(json, key) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)

    fun readInt(raw: Any?): Int {
        if (raw is Boolean || raw !is Number) throw CommunityException(CommunityError.INVALID_RESPONSE)
        val d = raw.toDouble()
        if (!d.isFinite() || floor(d) != d || d < Int.MIN_VALUE || d > Int.MAX_VALUE) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
        return d.toInt()
    }
}

internal enum class ReviewStatus(val key: String, val label: String) {
    PUBLISHED("published", "已发布"),
    PENDING("pending", "审核中"),
    REJECTED("rejected", "未通过");

    companion object {
        fun fromKey(raw: String?): ReviewStatus =
            entries.firstOrNull { it.key == raw }
                ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
    }
}

internal enum class ReportReason(val key: String, val label: String) {
    ILLEGAL("illegal", "违法违规"),
    PORN("porn", "色情低俗"),
    ABUSE("abuse", "人身攻击"),
    SPAM("spam", "垃圾营销"),
    PRIVACY("privacy", "隐私泄露"),
    OTHER("other", "其他");

    companion object {
        fun fromKey(raw: String?): ReportReason =
            entries.firstOrNull { it.key == raw }
                ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
    }
}

internal enum class ReportTargetType(val key: String, val label: String) {
    APP("app", "应用"),
    REVIEW("review", "评价");

    companion object {
        fun fromKey(raw: String?): ReportTargetType =
            entries.firstOrNull { it.key == raw }
                ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
    }
}

internal enum class ReportStatus(val key: String, val label: String) {
    OPEN("open", "待处理"),
    RESOLVED("resolved", "已处理"),
    DISMISSED("dismissed", "已忽略");

    companion object {
        fun fromKey(raw: String?): ReportStatus =
            entries.firstOrNull { it.key == raw }
                ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
    }
}

internal data class ReviewSummary(
    val average: Double,
    val count: Int,
    val distribution: Map<Int, Int>,
) {
    fun validate() {
        if (count < 0 || !average.isFinite() || distribution.keys != setOf(1, 2, 3, 4, 5)) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
        if (distribution.values.any { it < 0 } || distribution.values.sum() != count) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
        val expected = if (count == 0) {
            0.0
        } else {
            distribution.entries.sumOf { (star, n) -> star * n }.toDouble() / count
        }
        if (abs(expected - average) >= 0.001) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): ReviewSummary {
            val avgRaw = json.opt("average")
            if (avgRaw is Boolean || avgRaw !is Number) throw CommunityException(CommunityError.INVALID_RESPONSE)
            val average = avgRaw.toDouble()
            val count = CommunityValidation.readInt(json.opt("count"))
            val distObj = json.optJSONObject("distribution")
                ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
            if (distObj.length() != 5) throw CommunityException(CommunityError.INVALID_RESPONSE)
            val distribution = linkedMapOf<Int, Int>()
            for (star in 1..5) {
                val key = star.toString()
                if (!distObj.has(key)) throw CommunityException(CommunityError.INVALID_RESPONSE)
                distribution[star] = CommunityValidation.readInt(distObj.opt(key))
            }
            return ReviewSummary(average = average, count = count, distribution = distribution).also { it.validate() }
        }
    }
}

internal data class AppReview(
    val id: String,
    val appKey: String,
    val authorName: String,
    val authorAvatar: String?,
    val rating: Int,
    val title: String?,
    val content: String,
    val status: ReviewStatus,
    val rejectedReason: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val publishedAt: Long?,
) {
    fun validate() {
        if (!CommunityValidation.isValidIdentifier(id) ||
            !CommunityValidation.isValidIdentifier(appKey) ||
            authorName.trim().isEmpty() ||
            rating !in 1..5 ||
            content.trim().isEmpty() ||
            content.length > CommunityValidation.MAX_CONTENT_LENGTH ||
            (title != null && title.length > CommunityValidation.MAX_TITLE_LENGTH) ||
            !CommunityValidation.isValidTimestamp(createdAt) ||
            !CommunityValidation.isValidTimestamp(updatedAt) ||
            (publishedAt != null && !CommunityValidation.isValidTimestamp(publishedAt))
        ) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject, isPublicItem: Boolean): AppReview {
            val statusKey = json.readString("status")
            val status = if (statusKey != null) {
                ReviewStatus.fromKey(statusKey)
            } else if (isPublicItem) {
                ReviewStatus.PUBLISHED
            } else {
                throw CommunityException(CommunityError.INVALID_RESPONSE)
            }
            return AppReview(
                id = json.readString("_id") ?: json.readString("id")
                    ?: throw CommunityException(CommunityError.INVALID_RESPONSE),
                appKey = json.readString("appKey") ?: throw CommunityException(CommunityError.INVALID_RESPONSE),
                authorName = json.readString("authorName") ?: throw CommunityException(CommunityError.INVALID_RESPONSE),
                authorAvatar = json.readString("authorAvatar"),
                rating = CommunityValidation.readInt(json.opt("rating")),
                title = json.readString("title"),
                content = json.readString("content") ?: throw CommunityException(CommunityError.INVALID_RESPONSE),
                status = status,
                rejectedReason = json.readString("rejectedReason"),
                createdAt = CommunityValidation.readRequiredTimestamp(json, "createdAt"),
                updatedAt = CommunityValidation.readRequiredTimestamp(json, "updatedAt"),
                publishedAt = CommunityValidation.readOptionalTimestamp(json, "publishedAt"),
            ).also { it.validate() }
        }
    }
}

internal data class ReviewList(
    val summary: ReviewSummary,
    val reviews: List<AppReview>,
    val myReview: AppReview?,
)

internal data class ReviewDraft(
    val rating: Int = 5,
    val title: String = "",
    val content: String = "",
) {
    val isValid: Boolean
        get() = rating in 1..5 &&
            title.trim().length <= CommunityValidation.MAX_TITLE_LENGTH &&
            content.trim().isNotEmpty() &&
            content.trim().length <= CommunityValidation.MAX_CONTENT_LENGTH

    companion object {
        fun fromReview(review: AppReview): ReviewDraft = ReviewDraft(
            rating = review.rating,
            title = review.title.orEmpty(),
            content = review.content,
        )
    }
}

internal data class ReviewSubmission(
    val status: ReviewStatus,
    val message: String?,
    val review: AppReview,
)

internal data class ReportTarget(
    val type: ReportTargetType,
    val id: String,
    val label: String,
    val appKey: String? = null,
)

internal data class ReportDraft(
    val reason: ReportReason = ReportReason.SPAM,
    val detail: String = "",
) {
    val isValid: Boolean
        get() = detail.trim().length <= CommunityValidation.MAX_REPORT_DETAIL_LENGTH
}

internal data class MyReport(
    val id: String,
    val targetType: ReportTargetType,
    val targetId: String,
    val appKey: String?,
    val appName: String?,
    val reason: ReportReason,
    val detail: String?,
    val status: ReportStatus,
    val createdAt: Long,
    val handledAt: Long?,
) {
    fun validate() {
        if (!CommunityValidation.isValidIdentifier(id) ||
            !CommunityValidation.isValidIdentifier(targetId) ||
            (appKey != null && !CommunityValidation.isValidIdentifier(appKey)) ||
            (detail != null && detail.length > CommunityValidation.MAX_REPORT_DETAIL_LENGTH) ||
            !CommunityValidation.isValidTimestamp(createdAt) ||
            (handledAt != null && !CommunityValidation.isValidTimestamp(handledAt))
        ) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): MyReport = MyReport(
            id = json.readString("_id") ?: json.readString("id")
                ?: throw CommunityException(CommunityError.INVALID_RESPONSE),
            targetType = ReportTargetType.fromKey(json.readString("targetType")),
            targetId = json.readString("targetId") ?: throw CommunityException(CommunityError.INVALID_RESPONSE),
            appKey = json.readString("appKey"),
            appName = json.readString("appName"),
            reason = ReportReason.fromKey(json.readString("reason")),
            detail = json.readString("detail"),
            status = ReportStatus.fromKey(json.readString("status")),
            createdAt = CommunityValidation.readRequiredTimestamp(json, "createdAt"),
            handledAt = CommunityValidation.readOptionalTimestamp(json, "handledAt"),
        ).also { it.validate() }
    }
}

internal interface CommunityServing {
    suspend fun listReviews(appKey: String, identity: AuthorizedAccount?): ReviewList
    suspend fun submitReview(appKey: String, draft: ReviewDraft, identity: AuthorizedAccount): ReviewSubmission
    suspend fun deleteReview(id: String, identity: AuthorizedAccount)
    suspend fun submitReport(target: ReportTarget, draft: ReportDraft, identity: AuthorizedAccount): String
    suspend fun myReports(identity: AuthorizedAccount): List<MyReport>
}

internal class CommunityService(
    private val origin: String = "https://apps.yunle.fun",
) : CommunityServing {
    private val baseUrl = origin.trimEnd('/')

    override suspend fun listReviews(appKey: String, identity: AuthorizedAccount?): ReviewList {
        val key = CommunityValidation.requireIdentifier(appKey)
        val encoded = URLEncoder.encode(key, Charsets.UTF_8.name()).replace("+", "%20")
        val data = requestEnvelopeData(
            urlString = "$baseUrl/api/reviews?appKey=$encoded",
            identity = identity,
            requireData = true,
        ) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)

        val summaryObj = data.optJSONObject("summary")
            ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        val summary = ReviewSummary.fromJson(summaryObj)

        val reviewsArr = data.optJSONArray("reviews")
            ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        if (reviewsArr.length() > 100) throw CommunityException(CommunityError.INVALID_RESPONSE)
        val reviews = (0 until reviewsArr.length()).map { idx ->
            val obj = reviewsArr.optJSONObject(idx) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
            AppReview.fromJson(obj, isPublicItem = true)
        }
        if (reviews.map { it.id }.toSet().size != reviews.size) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }

        val myReview = if (data.has("myReview") && !data.isNull("myReview")) {
            val obj = data.optJSONObject("myReview") ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
            AppReview.fromJson(obj, isPublicItem = false)
        } else {
            null
        }
        if (identity == null && myReview != null) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
        return ReviewList(summary = summary, reviews = reviews, myReview = myReview)
    }

    override suspend fun submitReview(
        appKey: String,
        draft: ReviewDraft,
        identity: AuthorizedAccount,
    ): ReviewSubmission {
        val key = CommunityValidation.requireIdentifier(appKey)
        if (!draft.isValid) throw CommunityException(CommunityError.INVALID_INPUT)
        val body = JSONObject()
            .put("appKey", key)
            .put("rating", draft.rating)
            .put("content", draft.content.trim())
        val trimmedTitle = draft.title.trim()
        if (trimmedTitle.isNotEmpty()) {
            body.put("title", trimmedTitle)
        }
        val data = requestEnvelopeData(
            urlString = "$baseUrl/api/reviews",
            method = "POST",
            fields = body,
            identity = identity,
            requireData = true,
        ) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)

        val status = ReviewStatus.fromKey(data.readString("status"))
        val message = data.readString("message")
        val reviewObj = data.optJSONObject("review")
            ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        val review = AppReview.fromJson(reviewObj, isPublicItem = false)
        if (review.status != status) throw CommunityException(CommunityError.INVALID_RESPONSE)
        return ReviewSubmission(status = status, message = message, review = review)
    }

    override suspend fun deleteReview(id: String, identity: AuthorizedAccount) {
        val normalizedId = CommunityValidation.requireIdentifier(id)
        val segment = URLEncoder.encode(normalizedId, Charsets.UTF_8.name()).replace("+", "%20")
        requestEnvelopeData(
            urlString = "$baseUrl/api/reviews/$segment",
            method = "DELETE",
            identity = identity,
            requireData = false,
        )
    }

    override suspend fun submitReport(
        target: ReportTarget,
        draft: ReportDraft,
        identity: AuthorizedAccount,
    ): String {
        val normalizedTargetId = CommunityValidation.requireIdentifier(target.id)
        if (!draft.isValid) throw CommunityException(CommunityError.INVALID_INPUT)
        val body = JSONObject()
            .put("targetType", target.type.key)
            .put("targetId", normalizedTargetId)
            .put("reason", draft.reason.key)
        target.appKey?.takeIf { CommunityValidation.isValidIdentifier(it) }?.let {
            body.put("appKey", it)
        }
        val detail = draft.detail.trim()
        if (detail.isNotEmpty()) {
            body.put("detail", detail)
        }
        val data = requestEnvelopeData(
            urlString = "$baseUrl/api/reports",
            method = "POST",
            fields = body,
            identity = identity,
            requireData = true,
        ) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        return data.readString("id") ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
    }

    override suspend fun myReports(identity: AuthorizedAccount): List<MyReport> {
        val data = requestEnvelopeData(
            urlString = "$baseUrl/api/reports",
            identity = identity,
            requireData = true,
        ) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        val arr = data.optJSONArray("reports")
            ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        if (arr.length() > 100) throw CommunityException(CommunityError.INVALID_RESPONSE)
        val list = (0 until arr.length()).map { idx ->
            val obj = arr.optJSONObject(idx) ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
            MyReport.fromJson(obj)
        }
        if (list.map { it.id }.toSet().size != list.size) {
            throw CommunityException(CommunityError.INVALID_RESPONSE)
        }
        return list
    }

    private suspend fun requestEnvelopeData(
        urlString: String,
        method: String = "GET",
        fields: JSONObject? = null,
        identity: AuthorizedAccount?,
        requireData: Boolean,
    ): JSONObject? = withContext(Dispatchers.IO) {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            if (identity != null) {
                setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
            }
            if (fields != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (fields != null) {
                conn.outputStream.use { it.write(fields.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.use { input ->
                val buffer = ByteArray(8192)
                val out = ByteArrayOutputStream()
                while (true) {
                    val count = input.read(buffer)
                    if (count == -1) break
                    if (out.size() + count > MAXIMUM_BYTES) {
                        throw CommunityException(CommunityError.INVALID_RESPONSE)
                    }
                    out.write(buffer, 0, count)
                }
                out.toString(Charsets.UTF_8.name())
            }.orEmpty()

            if (code !in 200..299) {
                val parsedMessage = runCatching { JSONObject(text).readString("message") }.getOrNull()
                val err = when (code) {
                    400 -> CommunityError.INVALID_INPUT
                    401 -> CommunityError.UNAUTHORIZED
                    403 -> CommunityError.FORBIDDEN
                    404 -> CommunityError.NOT_FOUND
                    409 -> CommunityError.CONFLICT
                    429 -> CommunityError.THROTTLED
                    else -> CommunityError.UNAVAILABLE
                }
                throw CommunityException(err, serverMessage = parsedMessage)
            }

            val root = JSONObject(text)
            if (CommunityValidation.readInt(root.opt("code")) != 0) {
                throw CommunityException(CommunityError.INVALID_RESPONSE)
            }
            if (!requireData && (!root.has("data") || root.isNull("data"))) {
                return@withContext null
            }
            root.optJSONObject("data") ?: throw CommunityException(CommunityError.INVALID_RESPONSE)
        } catch (e: CommunityException) {
            throw e
        } catch (t: Throwable) {
            throw CommunityException(CommunityError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val MAXIMUM_BYTES = 2 * 1024 * 1024
    }
}
