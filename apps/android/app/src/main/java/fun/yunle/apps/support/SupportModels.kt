package `fun`.yunle.apps.support

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import `fun`.yunle.apps.readString
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt

internal enum class SupportDestination(val title: String) {
    COMPOSE("在线反馈"),
    BOARD("需求墙"),
    MANAGE("反馈管理"),
}

internal object SupportProduct {
    val submissionIDs: List<String> = listOf("www", "cook", "play", "yunbox", "drive", "cms", "advjs")

    fun title(id: String): String = when (id) {
        "www" -> "云乐坊账号与服务"
        "cook" -> "云食册 / 食用手册"
        "play" -> "Play 游戏"
        "yunbox" -> "云匣 YunBox"
        "drive" -> "Drive"
        "cms" -> "CMS"
        "advjs" -> "AdvJS"
        else -> id
    }
}

internal object SupportCategory {
    val options: List<Pair<String, String>> = listOf(
        "problem" to "问题反馈",
        "suggestion" to "功能建议",
        "other" to "其他",
    )

    fun title(category: String): String = when (category) {
        "problem" -> "问题反馈"
        "suggestion" -> "功能建议"
        "other" -> "其他"
        else -> category
    }
}

internal enum class FeedbackChannel(val key: String) {
    STANDARD("standard"),
    TEST_FLIGHT("testFlight");

    companion object {
        fun forKey(key: String?): FeedbackChannel = when (key) {
            TEST_FLIGHT.key -> TEST_FLIGHT
            else -> STANDARD
        }
    }
}

internal data class SupportHttpCookie(
    val name: String,
    val value: String,
    val isHttpOnly: Boolean,
    val isSecure: Boolean,
)

internal data class SupportAccess(
    val userID: String?,
    val csrfToken: String,
    val cookies: List<SupportHttpCookie>,
) {
    fun cookieHeader(): String = cookies.joinToString("; ") { "${it.name}=${it.value}" }
}

internal data class SupportPage<T>(
    val items: List<T>,
    val nextCursor: String?,
)

internal data class SupportBoardItem(
    val id: String,
    val productId: String,
    val title: String,
    val publicContent: String,
    val publicStatus: String,
    val voteCount: Int,
    val officialResponse: String?,
) {
    val statusTitle: String
        get() = when (publicStatus) {
            "collecting" -> "收集中"
            "evaluating" -> "评估中"
            "planned" -> "已计划"
            "in_progress" -> "进行中"
            "shipped" -> "已完成"
            "declined" -> "暂不采纳"
            else -> publicStatus
        }

    companion object {
        fun fromJson(json: JSONObject): SupportBoardItem {
            val id = json.readString("id") ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val productId = json.readString("productId")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val title = json.readString("title") ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val publicContent = json.readString("publicContent")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val publicStatus = json.readString("publicStatus")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val voteRaw = json.opt("voteCount")
            if (voteRaw is Boolean || voteRaw !is Number) {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            val voteCount = voteRaw.toInt()
            if (voteCount < 0) throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            return SupportBoardItem(
                id = id,
                productId = productId,
                title = title,
                publicContent = publicContent,
                publicStatus = publicStatus,
                voteCount = voteCount,
                officialResponse = json.readString("officialResponse"),
            )
        }
    }
}

internal data class SupportPrivateItem(
    val id: String,
    val productId: String,
    val description: String,
    val status: String,
    val category: String,
    val createdAt: String,
    val ticketId: String?,
    val context: Context?,
) {
    data class Context(
        val source: String?,
        val version: String?,
    )

    val sourceTitle: String
        get() = when (val source = context?.source) {
            "cook-web" -> "Web"
            "cook-ios" -> "iOS"
            "apps-ios-share" -> "iOS 系统分享"
            "apps-android" -> "Android"
            "apps-android-share" -> "Android 系统分享"
            null, "" -> "未记录"
            else -> source
        }

    val sourceSummary: String
        get() {
            val version = context?.version?.takeIf { it.isNotBlank() } ?: return sourceTitle
            return "$sourceTitle · $version"
        }

    val statusTitle: String
        get() = when (status) {
            "received" -> "待处理"
            "reviewing" -> "处理中"
            "resolved" -> "已处理"
            else -> status
        }

    companion object {
        fun fromJson(json: JSONObject): SupportPrivateItem {
            val id = json.readString("id") ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val productId = json.readString("productId")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val description = json.readString("description")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val status = json.readString("status")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val category = json.readString("category")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val createdAt = json.readString("createdAt")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val ctxObj = json.optJSONObject("context")
            val ctx = ctxObj?.let {
                Context(
                    source = it.readString("source"),
                    version = it.readString("version"),
                )
            }
            return SupportPrivateItem(
                id = id,
                productId = productId,
                description = description,
                status = status,
                category = category,
                createdAt = createdAt,
                ticketId = json.readString("ticketId"),
                context = ctx,
            )
        }
    }
}

internal data class SupportDashboard(
    val productId: String,
    val productIds: List<String>,
    val feedback: SupportPage<SupportBoardItem>,
    val privateFeedback: SupportPage<SupportPrivateItem>,
) {
    companion object {
        fun fromJson(json: JSONObject): SupportDashboard {
            val productId = json.readString("productId")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val productIdsArr = json.optJSONArray("productIds")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val productIds = (0 until productIdsArr.length()).mapNotNull { i ->
                (productIdsArr.opt(i) as? String)?.takeIf { it.isNotBlank() }
            }
            if (productIds.size != productIdsArr.length() || productIds.size > 100 || productId !in productIds) {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            val feedbackObj = json.optJSONObject("feedback")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val privateObj = json.optJSONObject("privateFeedback")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            return SupportDashboard(
                productId = productId,
                productIds = productIds,
                feedback = parseBoardPage(feedbackObj),
                privateFeedback = parsePrivatePage(privateObj),
            )
        }

        fun parseBoardPage(json: JSONObject): SupportPage<SupportBoardItem> {
            val arr = json.optJSONArray("items")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            if (arr.length() > 100) throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val items = (0 until arr.length()).map { i ->
                val obj = arr.optJSONObject(i) ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
                SupportBoardItem.fromJson(obj)
            }
            if (items.map { it.id }.toSet().size != items.size) {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            return SupportPage(items = items, nextCursor = json.readString("nextCursor"))
        }

        fun parsePrivatePage(json: JSONObject): SupportPage<SupportPrivateItem> {
            val arr = json.optJSONArray("items")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            if (arr.length() > 100) throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val items = (0 until arr.length()).map { i ->
                val obj = arr.optJSONObject(i) ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
                SupportPrivateItem.fromJson(obj)
            }
            if (items.map { it.id }.toSet().size != items.size) {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            return SupportPage(items = items, nextCursor = json.readString("nextCursor"))
        }
    }
}

internal data class SupportFeedbackReceipt(
    val id: String,
    val productId: String,
    val ticketId: String?,
    val ticketUrl: String?,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("productId", productId)
        if (ticketId != null) put("ticketId", ticketId)
        if (ticketUrl != null) put("ticketUrl", ticketUrl)
    }

    companion object {
        fun fromJson(json: JSONObject): SupportFeedbackReceipt {
            val id = json.readString("id")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val productId = json.readString("productId")
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            return SupportFeedbackReceipt(
                id = id,
                productId = productId,
                ticketId = json.readString("ticketId"),
                ticketUrl = json.readString("ticketUrl"),
            )
        }
    }
}

internal class FeedbackScreenshot(
    val id: String = UUID.randomUUID().toString(),
    val data: ByteArray,
    val width: Int,
    val height: Int,
) {
    fun sha256Hex(): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        return digest.joinToString("") { "%02x".format(it) }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is FeedbackScreenshot) return false
        return id == other.id && width == other.width && height == other.height && data.contentEquals(other.data)
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + data.contentHashCode()
        result = 31 * result + width
        result = 31 * result + height
        return result
    }

    companion object {
        const val MAXIMUM_COUNT = 3
        const val MAXIMUM_BYTES = 1024 * 1024
        const val MAXIMUM_INPUT_BYTES = 20 * 1024 * 1024
        const val MAX_DIMENSION = 2048
    }
}

internal object FeedbackScreenshotNormalizer {
    private val JPEG_QUALITIES = intArrayOf(85, 70, 50)

    fun prepare(
        rawBytes: ByteArray,
        maximumPixels: Double = 60_000_000.0,
    ): FeedbackScreenshot {
        if (rawBytes.isEmpty() || rawBytes.size > FeedbackScreenshot.MAXIMUM_INPUT_BYTES) {
            throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
        }
        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, boundsOpts)
        val rawWidth = boundsOpts.outWidth
        val rawHeight = boundsOpts.outHeight
        if (rawWidth <= 0 || rawHeight <= 0) {
            throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
        }
        if (rawWidth.toDouble() * rawHeight.toDouble() > maximumPixels) {
            throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
        }

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = computeInSampleSize(rawWidth, rawHeight, FeedbackScreenshot.MAX_DIMENSION)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, decodeOpts)
            ?: throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
        val oriented = try {
            applyExifAndScale(decoded, rawBytes, FeedbackScreenshot.MAX_DIMENSION)
        } catch (t: Throwable) {
            decoded.recycle()
            throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT, t)
        }
        if (oriented !== decoded && !decoded.isRecycled) {
            decoded.recycle()
        }

        try {
            val outWidth = oriented.width
            val outHeight = oriented.height
            for (quality in JPEG_QUALITIES) {
                val baos = ByteArrayOutputStream()
                val ok = oriented.compress(Bitmap.CompressFormat.JPEG, quality, baos)
                if (!ok) throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
                val encoded = baos.toByteArray()
                if (encoded.size <= FeedbackScreenshot.MAXIMUM_BYTES) {
                    return FeedbackScreenshot(
                        data = encoded,
                        width = outWidth,
                        height = outHeight,
                    )
                }
            }
            throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
        } finally {
            if (!oriented.isRecycled) {
                oriented.recycle()
            }
        }
    }

    private fun computeInSampleSize(width: Int, height: Int, maxDim: Int): Int {
        var sample = 1
        while ((width / (sample * 2)) >= maxDim || (height / (sample * 2)) >= maxDim) {
            sample *= 2
        }
        return sample
    }

    private fun applyExifAndScale(bitmap: Bitmap, rawBytes: ByteArray, maxDim: Int): Bitmap {
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(rawBytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
        }
        val rotated = if (!matrix.isIdentity) {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } else {
            bitmap
        }
        val largest = max(rotated.width, rotated.height)
        if (largest <= maxDim) return rotated
        val scale = maxDim.toFloat() / largest.toFloat()
        val dstW = (rotated.width * scale).roundToInt().coerceAtLeast(1)
        val dstH = (rotated.height * scale).roundToInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(rotated, dstW, dstH, true)
        if (rotated !== bitmap && rotated !== scaled && !rotated.isRecycled) {
            rotated.recycle()
        }
        return scaled
    }
}

internal data class SupportFeedbackSubmission(
    val productId: String,
    val category: String,
    val description: String,
    val images: List<ByteArray> = emptyList(),
    val context: Context? = null,
) {
    data class Context(
        val source: String,
        val version: String,
    )

    fun validate() {
        val trimmed = description.trim()
        if (productId !in SupportProduct.submissionIDs ||
            category !in VALID_CATEGORIES ||
            trimmed.length !in 5..4000
        ) {
            throw SupportCenterException(SupportCenterError.INVALID_INPUT)
        }
        if (images.size > FeedbackScreenshot.MAXIMUM_COUNT ||
            images.any { it.isEmpty() || it.size > FeedbackScreenshot.MAXIMUM_BYTES }
        ) {
            throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("productId", productId)
        put("category", category)
        put("description", description.trim())
        if (images.isNotEmpty()) {
            val arr = JSONArray()
            for (img in images) {
                arr.put(
                    JSONObject()
                        .put("mimeType", "image/jpeg")
                        .put("data", Base64.getEncoder().encodeToString(img)),
                )
            }
            put("screenshots", arr)
        }
        if (context != null) {
            put(
                "context",
                JSONObject()
                    .put("source", context.source)
                    .put("version", context.version),
            )
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SupportFeedbackSubmission) return false
        if (productId != other.productId || category != other.category || description != other.description || context != other.context) {
            return false
        }
        if (images.size != other.images.size) return false
        return images.indices.all { i -> images[i].contentEquals(other.images[i]) }
    }

    override fun hashCode(): Int {
        var result = productId.hashCode()
        result = 31 * result + category.hashCode()
        result = 31 * result + description.hashCode()
        result = 31 * result + (context?.hashCode() ?: 0)
        for (img in images) {
            result = 31 * result + img.contentHashCode()
        }
        return result
    }

    companion object {
        private val VALID_CATEGORIES = setOf("problem", "suggestion", "other")

        fun fromScreenshots(
            product: String,
            category: String,
            description: String,
            screenshots: List<FeedbackScreenshot>,
            context: Context? = null,
        ): SupportFeedbackSubmission = SupportFeedbackSubmission(
            productId = product,
            category = category,
            description = description.trim(),
            images = screenshots.map { it.data },
            context = context,
        )
    }
}

internal data class SupportTicketDetail(
    val ticket: Ticket,
    val messages: List<Message>,
) {
    data class Ticket(
        val id: String,
        val number: String,
        val title: String,
        val productId: String,
        val status: String,
        val createdAt: String,
        val updatedAt: String,
    ) {
        val statusTitle: String
            get() = when (status) {
                "new", "open" -> "待处理"
                "triaged" -> "已分流"
                "in_progress" -> "处理中"
                "waiting_user" -> "等待补充"
                "resolved" -> "已解决"
                "closed" -> "已关闭"
                else -> status
            }
    }

    data class Message(
        val id: String,
        val content: String,
        val createdAt: String,
        val author: String,
    ) {
        val authorTitle: String
            get() = if (author == "team") "云乐坊支持团队" else "我"
    }

    companion object {
        fun fromJson(json: JSONObject): SupportTicketDetail {
            val ticketObj = json.optJSONObject("ticket")
                ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            val ticket = Ticket(
                id = ticketObj.readString("id") ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
                number = ticketObj.readString("number")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
                title = ticketObj.readString("title") ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
                productId = ticketObj.readString("productId")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
                status = ticketObj.readString("status")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
                createdAt = ticketObj.readString("createdAt")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
                updatedAt = ticketObj.readString("updatedAt")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE),
            )
            val arr = json.optJSONArray("messages")
                ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            if (arr.length() > 1000) throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            val messages = (0 until arr.length()).map { i ->
                val obj = arr.optJSONObject(i) ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                val id = obj.readString("id") ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                val content = obj.readString("content")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                val createdAt = obj.readString("createdAt")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                val author = obj.readString("author")
                    ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                if (author !in VALID_AUTHORS || content.toByteArray(Charsets.UTF_8).size > 100_000) {
                    throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                }
                Message(id = id, content = content, createdAt = createdAt, author = author)
            }
            if (messages.map { it.id }.toSet().size != messages.size) {
                throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            }
            return SupportTicketDetail(ticket = ticket, messages = messages)
        }

        private val VALID_AUTHORS = setOf("you", "team")
    }
}

internal data class SupportTicketScreenshot(
    val id: String,
    val mimeType: String,
    val width: Int,
    val height: Int,
    val sizeBytes: Int,
) {
    companion object {
        fun fromJson(json: JSONObject): SupportTicketScreenshot {
            val id = json.readString("id") ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            val mimeType = json.readString("mimeType")
                ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            val width = json.optInt("width", -1)
            val height = json.optInt("height", -1)
            val sizeBytes = json.optInt("sizeBytes", -1)
            if (mimeType != "image/jpeg" || width <= 0 || height <= 0 || sizeBytes <= 0 ||
                sizeBytes > FeedbackScreenshot.MAXIMUM_BYTES
            ) {
                throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            }
            return SupportTicketScreenshot(
                id = id,
                mimeType = mimeType,
                width = width,
                height = height,
                sizeBytes = sizeBytes,
            )
        }
    }
}

internal data class SupportTicketSnapshot(
    val detail: SupportTicketDetail,
    val screenshots: List<SupportTicketScreenshot>,
    val cookies: List<SupportHttpCookie>,
)

internal data class SharedFeedbackRecord(
    val receipt: SupportFeedbackReceipt,
    val createdAtMillis: Long,
) {
    val id: String get() = receipt.id

    fun toJson(): JSONObject = JSONObject()
        .put("receipt", receipt.toJson())
        .put("createdAtMillis", createdAtMillis)

    companion object {
        fun fromJson(json: JSONObject): SharedFeedbackRecord? {
            val receiptObj = json.optJSONObject("receipt") ?: return null
            val receipt = runCatching { SupportFeedbackReceipt.fromJson(receiptObj) }.getOrNull() ?: return null
            val createdAt = json.optLong("createdAtMillis", -1L)
            if (createdAt <= 0L) return null
            return SharedFeedbackRecord(receipt = receipt, createdAtMillis = createdAt)
        }
    }
}

internal enum class SupportCenterError(val defaultMessage: String) {
    IDENTITY_CHANGED("账号已变化，请重新打开支持中心。"),
    UNAUTHORIZED("支持中心登录已失效，请重新连接。"),
    FORBIDDEN("当前账号没有此项权限，或尚未完成手机号验证。请在账号中心核对。"),
    CONSENT_REQUIRED("请允许支持中心使用当前云乐坊账号。"),
    INVALID_RESPONSE("支持中心返回了无法识别的内容，请稍后重试。"),
    UNAVAILABLE("暂时无法连接支持中心，请稍后重试。"),
    THROTTLED("操作有些频繁，请稍后再试。"),
    INVALID_INPUT("请填写 5 至 4000 个字符的问题描述。"),
    INVALID_SCREENSHOT("截图未能提交。最多 3 张，压缩后每张不超过 1 MB，请检查后重试。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED
}

internal class SupportCenterException(
    val error: SupportCenterError,
    cause: Throwable? = null,
    serverMessage: String? = null,
) : Exception(serverMessage?.takeIf { it.isNotBlank() } ?: error.defaultMessage, cause) {
    override val message: String
        get() = super.message ?: error.defaultMessage
}

internal enum class SupportTicketError(val defaultMessage: String) {
    INVALID_RESPONSE("工单内容暂时无法读取，请稍后重试。"),
    UNAVAILABLE("暂时无法读取工单，请检查网络后重试。"),
    EXPIRED("工单访问凭证已失效，请使用原账号或有效的私密工单链接查看。"),
    NOT_FOUND("工单或截图已不可用。"),
    THROTTLED("操作有些频繁，请稍后再试。"),
}

internal class SupportTicketException(
    val error: SupportTicketError,
    cause: Throwable? = null,
    serverMessage: String? = null,
) : Exception(serverMessage?.takeIf { it.isNotBlank() } ?: error.defaultMessage, cause) {
    override val message: String
        get() = super.message ?: error.defaultMessage
}

internal object SupportUrlRules {
    private val IDENTIFIER_RE = Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
    private val IDEMPOTENCY_RE = Regex("^[A-Za-z0-9_-]{8,128}$")

    fun isValidIdentifier(value: String?): Boolean {
        val candidate = value?.trim().orEmpty()
        return candidate.isNotEmpty() && IDENTIFIER_RE.matches(candidate)
    }

    fun isValidIdempotencyKey(value: String?): Boolean {
        val candidate = value?.trim().orEmpty()
        return candidate.isNotEmpty() && IDEMPOTENCY_RE.matches(candidate)
    }

    fun isLoopbackOrigin(origin: String): Boolean {
        val uri = runCatching { URI(origin) }.getOrNull() ?: return false
        val host = uri.host?.lowercase(Locale.ROOT) ?: return false
        return uri.scheme == "http" && (host == "127.0.0.1" || host == "localhost")
    }

    fun ticketUrl(
        receipt: SupportFeedbackReceipt,
        origin: String = "https://support.yunle.fun",
        requiringGuestAccess: Boolean = false,
    ): String? {
        val ticketId = receipt.ticketId?.takeIf(::isValidIdentifier) ?: return null
        val raw = receipt.ticketUrl?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val parsedOrigin = runCatching { URI(origin.trimEnd('/')) }.getOrNull() ?: return null
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        if (!uri.scheme.equals(parsedOrigin.scheme, ignoreCase = true) ||
            !uri.host.equals(parsedOrigin.host, ignoreCase = true) ||
            effectivePort(uri) != effectivePort(parsedOrigin)
        ) {
            return null
        }
        val expectedPath = "/tickets/$ticketId"
        if (uri.rawPath != expectedPath) return null
        if (requiringGuestAccess && extractAccessToken(raw) == null) return null
        return raw
    }

    fun extractAccessToken(ticketUrl: String?): String? {
        val raw = ticketUrl?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val fragment = uri.rawFragment?.takeIf { it.isNotBlank() } ?: return null
        for (part in fragment.split('&')) {
            val idx = part.indexOf('=')
            val key = if (idx >= 0) part.substring(0, idx) else part
            if (key == "access" && idx >= 0) {
                val decoded = runCatching {
                    URLDecoder.decode(part.substring(idx + 1), StandardCharsets.UTF_8.name())
                }.getOrDefault(part.substring(idx + 1))
                if (decoded.isNotEmpty()) return decoded
            }
        }
        return null
    }

    fun isValidJpegBytes(bytes: ByteArray): Boolean {
        if (bytes.size < 4 || bytes.size > FeedbackScreenshot.MAXIMUM_BYTES) return false
        return (bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte())
    }

    private fun effectivePort(uri: URI): Int {
        if (uri.port > 0) return uri.port
        return when (uri.scheme?.lowercase(Locale.ROOT)) {
            "https" -> 443
            "http" -> 80
            else -> -1
        }
    }
}
