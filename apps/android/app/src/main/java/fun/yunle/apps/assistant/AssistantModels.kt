package `fun`.yunle.apps.assistant

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.readString
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

internal enum class AssistantError(val defaultMessage: String) {
    UNAUTHORIZED("登录已失效，请重新登录后再试。"),
    FORBIDDEN("当前账号暂不能使用 AI 助手。"),
    MEMBERSHIP_REQUIRED("AI 助手需要有效会员。"),
    QUOTA("今日 AI 助手使用次数已达上限，请明天再试。"),
    UNAVAILABLE("AI 助手暂时不可用，请稍后重试。"),
    INVALID_RESPONSE("AI 助手返回格式无法识别，请稍后重试。"),
    IDENTITY_CHANGED("账号已变化，请重新开始对话。"),
    INTERRUPTED("连接已中断，已保留收到的内容。可以重试。"),
    TOO_LONG("对话内容过长，请缩短问题或开始新对话。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun fromServerCode(code: String?): AssistantError = when (code) {
            "UNAUTHENTICATED", "TOKEN_EXPIRED" -> UNAUTHORIZED
            "MEMBERSHIP_REQUIRED" -> MEMBERSHIP_REQUIRED
            "ACCOUNT_RESTRICTED" -> FORBIDDEN
            "DAILY_LIMIT_EXCEEDED" -> QUOTA
            "REQUEST_TOO_LARGE" -> TOO_LONG
            else -> UNAVAILABLE
        }

        fun message(error: Throwable): String = when (error) {
            is AssistantException -> error.error.defaultMessage
            is AccountException -> error.error.message
            else -> UNAVAILABLE.defaultMessage
        }
    }
}

internal class AssistantException(
    val error: AssistantError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal data class AssistantAppCard(
    val applicationId: String?,
    val slug: String,
    val name: String,
    val reason: String?,
) {
    val id: String get() = applicationId ?: slug

    fun resolve(catalog: List<CatalogApp>): CatalogApp? {
        val candidates = catalog.filter { app ->
            app.accessWorkshopId == null &&
                app.personalMarketOwnerLogin == null &&
                app.launchUrl != null &&
                (app.audience == null || app.audience == "public") &&
                (applicationId?.let { app.id == it } ?: (app.key == slug || app.id == slug))
        }
        return if (candidates.size == 1) candidates.first() else null
    }

    fun toJson(): JSONObject = JSONObject()
        .put("applicationId", applicationId ?: JSONObject.NULL)
        .put("slug", slug)
        .put("name", name)
        .put("reason", reason ?: JSONObject.NULL)

    companion object {
        fun fromJson(json: JSONObject): AssistantAppCard? {
            val slug = json.readString("slug") ?: json.readString("id") ?: return null
            val name = json.readString("name") ?: json.readString("title") ?: return null
            return AssistantAppCard(
                applicationId = json.readString("applicationId") ?: json.readString("appId") ?: json.readString("id"),
                slug = slug,
                name = name,
                reason = json.readString("reason"),
            )
        }
    }
}

internal data class AssistantMessage(
    val id: String,
    val role: Role,
    val content: String,
    val cards: List<AssistantAppCard> = emptyList(),
    val status: Status = Status.DONE,
    val toolStatus: String? = null,
) {
    enum class Role(val key: String) {
        USER("user"),
        ASSISTANT("assistant");

        companion object {
            fun fromKey(raw: String?): Role? = entries.firstOrNull { it.key == raw }
        }
    }

    enum class Status(val key: String) {
        STREAMING("streaming"),
        DONE("done"),
        STOPPED("stopped"),
        FAILED("failed");

        companion object {
            fun fromKey(raw: String?): Status = entries.firstOrNull { it.key == raw } ?: DONE
        }
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("role", role.key)
        .put("content", content)
        .put("cards", JSONArray(cards.map(AssistantAppCard::toJson)))
        .put("status", status.key)
        .put("toolStatus", toolStatus ?: JSONObject.NULL)

    companion object {
        fun fromJson(json: JSONObject): AssistantMessage? {
            val id = json.readString("id") ?: return null
            val role = Role.fromKey(json.readString("role")) ?: return null
            val content = json.optString("content", "")
            val status = Status.fromKey(json.readString("status"))
            val cardsArr = json.optJSONArray("cards")
            val cards = if (cardsArr == null) {
                emptyList()
            } else {
                (0 until cardsArr.length()).mapNotNull { i ->
                    cardsArr.optJSONObject(i)?.let(AssistantAppCard::fromJson)
                }
            }
            return AssistantMessage(
                id = id,
                role = role,
                content = content,
                cards = cards,
                status = status,
                toolStatus = json.readString("toolStatus"),
            )
        }
    }
}

internal data class AssistantRunInput(
    val botId: String = BOT_ID,
    val threadId: String,
    val runId: String,
    val messages: List<InputMessage>,
) {
    data class InputMessage(
        val id: String,
        val role: AssistantMessage.Role,
        val content: String,
    )

    fun toJsonBytes(): ByteArray {
        if (botId != BOT_ID || messages.isEmpty() || messages.size > 32 ||
            messages.any { it.content.length > 8000 }
        ) {
            throw AssistantException(AssistantError.TOO_LONG)
        }
        val searchTool = JSONObject()
            .put("name", "search_apps")
            .put("description", "Search public approved YunLeFun apps and return up to six application cards.")
            .put(
                "parameters",
                JSONObject()
                    .put("type", "object")
                    .put(
                        "properties",
                        JSONObject()
                            .put("query", JSONObject().put("type", "string").put("description", "User intent or keywords."))
                            .put("category", JSONObject().put("type", "string").put("description", "Optional application category."))
                            .put("limit", JSONObject().put("type", "number").put("description", "Maximum cards, at most six.")),
                    )
                    .put("required", JSONArray().put("query")),
            )
        val payload = JSONObject()
            .put("botId", botId)
            .put("threadId", threadId)
            .put("runId", runId)
            .put(
                "messages",
                JSONArray().apply {
                    messages.forEach { m ->
                        put(JSONObject().put("id", m.id).put("role", m.role.key).put("content", m.content))
                    }
                },
            )
            .put("tools", JSONArray().put(searchTool))
            .put("context", JSONArray())
            .put("state", JSONObject())
            .put("forwardedProps", JSONObject().put("source", "apps.yunle.fun").put("platform", "android"))
        val bytes = payload.toString().toByteArray(Charsets.UTF_8)
        if (bytes.size > 128 * 1024) throw AssistantException(AssistantError.TOO_LONG)
        return bytes
    }

    companion object {
        const val BOT_ID = "agent-yunlefun-1g1ef4a470aefe98"
    }
}

internal data class AssistantEvent(
    val type: String?,
    val threadId: String?,
    val runId: String?,
    val messageId: String?,
    val delta: String?,
    val content: String?,
    val toolCallId: String?,
    val toolName: String?,
    val cards: List<AssistantAppCard>,
    val code: String?,
    val isReasoning: Boolean,
) {
    companion object {
        private val DONE_BYTES = "[DONE]".toByteArray(Charsets.UTF_8)
        private val CARD_KEYS = listOf("apps", "appCards", "cards", "items", "results", "data", "result", "payload")

        fun parse(rawData: ByteArray): AssistantEvent {
            if (rawData.size > 512 * 1024) throw AssistantException(AssistantError.TOO_LONG)
            if (rawData.contentEquals(DONE_BYTES)) {
                return AssistantEvent(
                    type = "_DONE",
                    threadId = null,
                    runId = null,
                    messageId = null,
                    delta = null,
                    content = null,
                    toolCallId = null,
                    toolName = null,
                    cards = emptyList(),
                    code = null,
                    isReasoning = false,
                )
            }
            val obj = runCatching { JSONObject(rawData.toString(Charsets.UTF_8)) }.getOrNull()
                ?: throw AssistantException(AssistantError.INVALID_RESPONSE)
            val type = obj.readString("type")
            val cards = if (type == "TOOL_CALL_RESULT") {
                extractCards(obj.opt("content"))
            } else {
                emptyList()
            }
            return AssistantEvent(
                type = type,
                threadId = obj.readString("threadId"),
                runId = obj.readString("runId"),
                messageId = obj.readString("messageId"),
                delta = obj.readString("delta"),
                content = obj.readString("content"),
                toolCallId = obj.readString("toolCallId"),
                toolName = obj.readString("toolCallName"),
                cards = cards,
                code = obj.readString("code"),
                isReasoning = !obj.readString("reasoning_content").isNullOrEmpty(),
            )
        }

        fun extractCards(value: Any?, depth: Int = 0): List<AssistantAppCard> {
            if (value == null || value === JSONObject.NULL || depth > 3) return emptyList()
            if (value is String) {
                val bytes = value.toByteArray(Charsets.UTF_8)
                if (bytes.size > 512 * 1024) throw AssistantException(AssistantError.TOO_LONG)
                val trimmed = value.trim()
                val parsed: Any? = when {
                    trimmed.startsWith("[") -> runCatching { JSONArray(trimmed) }.getOrNull()
                    trimmed.startsWith("{") -> runCatching { JSONObject(trimmed) }.getOrNull()
                    else -> null
                }
                return extractCards(parsed, depth + 1)
            }
            if (value is JSONArray) {
                if (value.length() > 6) throw AssistantException(AssistantError.INVALID_RESPONSE)
                val out = ArrayList<AssistantAppCard>(value.length())
                for (i in 0 until value.length()) {
                    val item = value.optJSONObject(i) ?: continue
                    val id = validField(item, "id") ?: validField(item, "appId")
                    val slug = validField(item, "slug") ?: id ?: continue
                    val name = validField(item, "name") ?: validField(item, "title") ?: continue
                    out.add(
                        AssistantAppCard(
                            applicationId = id,
                            slug = slug,
                            name = name,
                            reason = validField(item, "reason"),
                        ),
                    )
                }
                return out
            }
            if (value is JSONObject) {
                for (k in CARD_KEYS) {
                    if (value.has(k) && !value.isNull(k)) {
                        val nested = extractCards(value.opt(k), depth + 1)
                        if (nested.isNotEmpty()) return nested
                    }
                }
            }
            return emptyList()
        }

        private fun validField(obj: JSONObject, key: String): String? {
            val s = obj.readString(key) ?: return null
            return if (s.isNotEmpty() && s.length <= 500) s else null
        }
    }
}

internal class AssistantSSEDecoder {
    private val line = ByteArrayOutputStream()
    private val data = ByteArrayOutputStream()
    private var afterCr = false
    private var firstLine = true

    fun append(byteVal: Byte): ByteArray? {
        val code = byteVal.toInt() and 0xFF
        if (afterCr && code == 10) {
            afterCr = false
            return null
        }
        afterCr = false
        if (code == 10 || code == 13) {
            afterCr = code == 13
            return finishLine()
        }
        if (line.size() >= MAX_FRAME_BYTES) throw AssistantException(AssistantError.TOO_LONG)
        line.write(code)
        return null
    }

    private fun finishLine(): ByteArray? {
        var bytes = line.toByteArray()
        line.reset()
        if (firstLine && bytes.size >= 3 &&
            (bytes[0].toInt() and 0xFF) == 0xEF &&
            (bytes[1].toInt() and 0xFF) == 0xBB &&
            (bytes[2].toInt() and 0xFF) == 0xBF
        ) {
            bytes = bytes.copyOfRange(3, bytes.size)
        }
        firstLine = false
        val text = runCatching {
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
            decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        }.getOrNull() ?: throw AssistantException(AssistantError.INVALID_RESPONSE)

        if (bytes.isEmpty()) {
            if (data.size() == 0) return null
            val full = data.toByteArray()
            data.reset()
            return if (full.isNotEmpty() && full[full.lastIndex] == '\n'.code.toByte()) {
                full.copyOfRange(0, full.size - 1)
            } else {
                full
            }
        }
        if (text.startsWith("data:") || text == "data") {
            val valueStart = if (bytes.size > 5 && (bytes[5].toInt() and 0xFF) == 32) 6 else if (bytes.size >= 5) 5 else bytes.size
            val chunkLen = bytes.size - valueStart
            if (data.size() + chunkLen + 1 > MAX_FRAME_BYTES) throw AssistantException(AssistantError.TOO_LONG)
            data.write(bytes, valueStart, chunkLen)
            data.write(10)
        }
        return null
    }

    companion object {
        private const val MAX_FRAME_BYTES = 512 * 1024
    }
}

internal class AssistantRunAccumulator(
    val threadId: String,
    val runId: String,
) {
    var finished: Boolean = false
        private set
    private var started = false
    private val messages = mutableSetOf<String>()
    private val openMessages = mutableSetOf<String>()
    private val searches = mutableSetOf<String>()
    private val buffer = StringBuilder()
    val content: String get() = buffer.toString()
    val cards: MutableList<AssistantAppCard> = mutableListOf()
    var status: String? = "正在连接"
        private set

    fun apply(event: AssistantEvent) {
        if (finished) throw AssistantException(AssistantError.INVALID_RESPONSE)
        if (event.threadId != null && event.threadId != threadId) {
            throw AssistantException(AssistantError.INVALID_RESPONSE)
        }
        if (event.runId != null && event.runId != runId) {
            throw AssistantException(AssistantError.INVALID_RESPONSE)
        }
        if (event.type == "RUN_ERROR") {
            throw AssistantException(AssistantError.fromServerCode(event.code))
        }
        if (event.isReasoning) status = "正在思考"
        when (event.type) {
            "RUN_STARTED" -> {
                if (started || event.threadId != threadId || event.runId != runId) {
                    throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
                started = true
            }
            "TEXT_MESSAGE_START" -> {
                val id = event.messageId ?: throw AssistantException(AssistantError.INVALID_RESPONSE)
                if (!started || messages.size >= 32 || !messages.add(id)) {
                    throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
                openMessages.add(id)
            }
            "TEXT_MESSAGE_CONTENT" -> {
                val id = event.messageId
                val delta = event.delta
                if (!started || id == null || id !in openMessages || delta == null) {
                    throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
                buffer.append(delta)
                status = null
            }
            "TEXT_MESSAGE_END" -> {
                val id = event.messageId
                if (id == null || !openMessages.remove(id)) {
                    throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
            }
            "TOOL_CALL_START" -> {
                val id = event.toolCallId
                if (!started || id == null || searches.size >= 32) {
                    throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
                if (event.toolName == "search_apps") {
                    searches.add(id)
                    status = "正在检索应用"
                }
            }
            "TOOL_CALL_ARGS" -> status = "正在确认条件"
            "TOOL_CALL_END" -> status = "正在整理结果"
            "TOOL_CALL_RESULT" -> {
                val id = event.toolCallId
                if (id != null && searches.remove(id)) {
                    for (card in event.cards) {
                        if (cards.none { it.id == card.id }) cards.add(card)
                    }
                    if (cards.size > 6) throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
            }
            "RUN_FINISHED" -> {
                if (!started || openMessages.isNotEmpty() || event.runId != runId || event.threadId != threadId) {
                    throw AssistantException(AssistantError.INVALID_RESPONSE)
                }
                finished = true
                status = null
            }
            "_DONE" -> if (!finished) throw AssistantException(AssistantError.INTERRUPTED)
        }
    }
}
