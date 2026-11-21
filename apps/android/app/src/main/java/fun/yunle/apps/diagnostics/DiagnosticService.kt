package `fun`.yunle.apps.diagnostics

import `fun`.yunle.apps.account.AccountError
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AccountRequestBoundary
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.games.sha256Hex
import `fun`.yunle.apps.games.writeAtomicUtf8
import `fun`.yunle.apps.readString
import `fun`.yunle.apps.support.runInBoundary
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.Locale
import java.util.UUID

internal enum class DiagnosticLogLevel(val key: String, val label: String) {
    INFO("info", "信息"),
    WARN("warn", "警告"),
    ERROR("error", "错误");

    companion object {
        fun fromKey(key: String?): DiagnosticLogLevel? = entries.firstOrNull { it.key == key }
    }
}

internal data class DiagnosticLogEntry(
    val level: DiagnosticLogLevel,
    val message: String,
    val timestamp: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("level", level.key)
        .put("message", message)
        .put("timestamp", timestamp)

    companion object {
        fun fromJson(json: JSONObject): DiagnosticLogEntry? {
            val level = DiagnosticLogLevel.fromKey(json.readString("level")) ?: return null
            val message = json.readString("message") ?: return null
            val rawTs = json.opt("timestamp")
            if (rawTs is Boolean || rawTs !is Number) return null
            val ts = rawTs.toLong()
            if (ts <= 0L) return null
            return DiagnosticLogEntry(level = level, message = message, timestamp = ts)
        }
    }
}

internal data class DiagnosticClientContext(
    val appVersion: String,
    val buildNumber: String,
    val platform: String = "android",
    val route: String = "/",
    val timezone: String,
    val userAgent: String,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("appVersion", appVersion)
        .put("buildNumber", buildNumber)
        .put("platform", platform)
        .put("route", route)
        .put("timezone", timezone)
        .put("userAgent", userAgent)
}

internal data class DiagnosticUploadPayload(
    val startTime: Long,
    val endTime: Long,
    val issueDescription: String,
    val logs: List<DiagnosticLogEntry>,
    val client: DiagnosticClientContext,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("startTime", startTime)
        .put("endTime", endTime)
        .put("issueDescription", issueDescription)
        .put(
            "logs",
            JSONArray().apply {
                for (entry in logs) put(entry.toJson())
            },
        )
        .put("client", client.toJson())
}

internal data class DiagnosticUploadReceipt(
    val uploadId: String,
    val supportCode: String,
    val logCount: Int,
    val expiresAt: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("uploadId", uploadId)
        .put("supportCode", supportCode)
        .put("logCount", logCount)
        .put("expiresAt", expiresAt)

    companion object {
        fun fromJson(json: JSONObject): DiagnosticUploadReceipt {
            val uploadId = json.opt("uploadId") as? String ?: ""
            val supportCode = json.readString("supportCode")
                ?: throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
            val logCountRaw = json.opt("logCount")
            val expiresRaw = json.opt("expiresAt")
            if (logCountRaw is Boolean || logCountRaw !is Number ||
                expiresRaw is Boolean || expiresRaw !is Number
            ) {
                throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
            }
            return DiagnosticUploadReceipt(
                uploadId = uploadId,
                supportCode = supportCode,
                logCount = logCountRaw.toInt(),
                expiresAt = expiresRaw.toLong(),
            )
        }
    }
}

internal data class DiagnosticUploadConfirmation(
    val id: UUID,
    val payload: DiagnosticUploadPayload,
    val boundary: AccountRequestBoundary,
    val logScopeGeneration: UUID,
    val sizeBytes: Int,
)

internal enum class DiagnosticError(val defaultMessage: String) {
    IDENTITY_CHANGED("账号已变化，请重新打开帮助与诊断页面。"),
    UNAUTHORIZED("登录状态已失效，请重新登录后再上传诊断日志。"),
    FORBIDDEN("当前账号暂不支持此操作。"),
    EMPTY_LOGS("所选时间范围内暂无可上传的诊断日志。"),
    INVALID_RANGE("请选择 24 小时以内、且在最近 7 天之内的有效时间范围。"),
    INVALID_INPUT("请补充不超过 500 个字符的问题描述后重试。"),
    TOO_LARGE("所选日志体积过大，请缩短时间范围后再试。"),
    THROTTLED("操作有些频繁，请稍后再试。"),
    CONFIRMATION_EXPIRED("上传确认已过期，请重新检查并确认本次日志内容。"),
    CANCELLED("已取消上传诊断日志。"),
    OUTCOME_UNKNOWN("上传请求可能已发出，但未收到确认结果。若需排查请稍后重试。"),
    STORAGE("本机保存的支持编号暂时无法写入，请妥善保存当前显示的支持编号。"),
    INVALID_RESPONSE("诊断服务返回了无法识别的内容，请稍后重试。"),
    UNAVAILABLE("暂时无法连接诊断服务，请检查网络后重试。");

    val isUnauthorized: Boolean get() = this == UNAUTHORIZED

    companion object {
        fun fromThrowable(t: Throwable): DiagnosticError = when (t) {
            is DiagnosticException -> t.error
            is AccountException -> when (t.error) {
                AccountError.SIGNED_OUT, AccountError.EXPIRED_SESSION -> UNAUTHORIZED
                AccountError.SESSION_CHANGED -> IDENTITY_CHANGED
                else -> UNAVAILABLE
            }
            is CancellationException -> CANCELLED
            else -> UNAVAILABLE
        }
    }
}

internal class DiagnosticException(
    val error: DiagnosticError,
    cause: Throwable? = null,
    serverMessage: String? = null,
) : Exception(serverMessage?.takeIf { it.isNotBlank() } ?: error.defaultMessage, cause) {
    override val message: String
        get() = super.message ?: error.defaultMessage
}

internal object DiagnosticText {
    private val CONTROL_CHARS_RE = Regex("[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F]")
    private val BEARER_RE = Regex("(?i)\\b(Bearer|Basic)\\s+[A-Za-z0-9._~+/=-]+")
    private val AUTH_HEADER_RE = Regex("(?i)\\bAuthorization\\s*:\\s*(?:(?:Bearer|Basic)\\s+)?[^\\s,;\"'\\]]+")
    private val JWT_RE = Regex("\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\b")
    private val SENSITIVE_KV_RE = Regex(
        "(?i)\\b(access_?token|refresh_?token|id_?token|identityAssertion|code_?verifier|client_?secret|csrf_?token|x-csrf-token|ticket|password|secret|token)\\b(\\s*[=:]\\s*)([^\\s&;,\"'\\]\\)]+)",
    )
    private val EMAIL_RE = Regex("\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b")
    private val PHONE_RE = Regex("(?<!\\d)1[3-9]\\d{9}(?!\\d)")

    fun redact(text: String, limit: Int = 1500): String {
        var sanitized = CONTROL_CHARS_RE.replace(text.replace('\n', ' ').replace('\r', ' '), " ")
        sanitized = AUTH_HEADER_RE.replace(sanitized, "Authorization: [REDACTED]")
        sanitized = BEARER_RE.replace(sanitized) { match -> "${match.groupValues[1]} [REDACTED]" }
        sanitized = JWT_RE.replace(sanitized, "[REDACTED_JWT]")
        sanitized = SENSITIVE_KV_RE.replace(sanitized) { match ->
            "${match.groupValues[1]}${match.groupValues[2]}[REDACTED]"
        }
        sanitized = EMAIL_RE.replace(sanitized, "[email]")
        sanitized = PHONE_RE.replace(sanitized, "[phone]")
        sanitized = sanitized.trim()
        if (sanitized.length <= limit) return sanitized
        var cut = limit
        if (cut > 0 && Character.isHighSurrogate(sanitized[cut - 1])) {
            cut -= 1
        }
        return sanitized.substring(0, cut.coerceAtLeast(0))
    }
}

internal object DiagnosticUploadRules {
    const val RETENTION_MS = 7L * 24 * 60 * 60 * 1000
    const val CLOCK_SKEW_MS = 5L * 60 * 1000
    const val MAX_WINDOW_MS = 86_400_999L
    const val MAX_ENTRIES = 500
    const val MAX_ENTRY_RAW_LENGTH = 4000
    const val MAX_ISSUE_DESCRIPTION_LENGTH = 500
    const val MAX_BYTES = 256 * 1024
    const val MAX_BODY_BYTES = MAX_BYTES + 4096
    const val MAX_RESPONSE_BYTES = 16 * 1024

    private val SUPPORT_CODE_RE = Regex("^[A-Z0-9]{12}$")
    private val UPLOAD_ID_RE = Regex("^[A-Za-z0-9_-]{1,128}$")

    fun normalize(
        payload: DiagnosticUploadPayload,
        nowMillis: Long,
    ): DiagnosticUploadPayload {
        val start = payload.startTime
        val end = payload.endTime
        if (start > end || (end - start) > MAX_WINDOW_MS ||
            start < nowMillis - RETENTION_MS || end > nowMillis + CLOCK_SKEW_MS
        ) {
            throw DiagnosticException(DiagnosticError.INVALID_RANGE)
        }
        if (payload.logs.isEmpty()) throw DiagnosticException(DiagnosticError.EMPTY_LOGS)
        if (payload.logs.size > MAX_ENTRIES) throw DiagnosticException(DiagnosticError.TOO_LARGE)
        val rawDesc = payload.issueDescription.trim()
        if (rawDesc.length > MAX_ISSUE_DESCRIPTION_LENGTH) {
            throw DiagnosticException(DiagnosticError.INVALID_INPUT)
        }
        val normalizedLogs = payload.logs.map { entry ->
            if (entry.message.length > MAX_ENTRY_RAW_LENGTH) {
                throw DiagnosticException(DiagnosticError.TOO_LARGE)
            }
            if (entry.timestamp < start || entry.timestamp > end) {
                throw DiagnosticException(DiagnosticError.INVALID_RANGE)
            }
            val cleaned = DiagnosticText.redact(entry.message)
            if (cleaned.isBlank()) throw DiagnosticException(DiagnosticError.INVALID_INPUT)
            DiagnosticLogEntry(level = entry.level, message = cleaned, timestamp = entry.timestamp)
        }
        val client = DiagnosticClientContext(
            appVersion = DiagnosticText.redact(payload.client.appVersion, limit = 50),
            buildNumber = DiagnosticText.redact(payload.client.buildNumber, limit = 50),
            platform = DiagnosticText.redact(payload.client.platform, limit = 20),
            route = DiagnosticText.redact(payload.client.route, limit = 200),
            timezone = DiagnosticText.redact(payload.client.timezone, limit = 100),
            userAgent = DiagnosticText.redact(payload.client.userAgent, limit = 500),
        )
        val redactedDesc = DiagnosticText.redact(rawDesc, limit = MAX_ISSUE_DESCRIPTION_LENGTH).trim()
        val result = DiagnosticUploadPayload(
            startTime = start,
            endTime = end,
            issueDescription = redactedDesc,
            logs = normalizedLogs,
            client = client,
        )
        if (sizeBytes(result) > MAX_BYTES) {
            throw DiagnosticException(DiagnosticError.TOO_LARGE)
        }
        return result
    }

    fun sizeBytes(payload: DiagnosticUploadPayload): Int {
        val logsBytes = JSONArray().apply {
            for (entry in payload.logs) put(entry.toJson())
        }.toString().toByteArray(Charsets.UTF_8).size
        val clientBytes = payload.client.toJson().toString().toByteArray(Charsets.UTF_8).size
        val descBytes = payload.issueDescription.toByteArray(Charsets.UTF_8).size
        return logsBytes + clientBytes + descBytes
    }

    fun validate(
        receipt: DiagnosticUploadReceipt,
        expectedCount: Int? = null,
        nowMillis: Long,
        startedMillis: Long? = null,
    ) {
        val validCode = SUPPORT_CODE_RE.matches(receipt.supportCode)
        val validUploadId = receipt.uploadId.isEmpty() || UPLOAD_ID_RE.matches(receipt.uploadId)
        val validCount = receipt.logCount in 1..MAX_ENTRIES &&
            (expectedCount == null || receipt.logCount == expectedCount)
        val validExpiry = receipt.expiresAt > nowMillis &&
            receipt.expiresAt <= nowMillis + RETENTION_MS + CLOCK_SKEW_MS &&
            (startedMillis == null || receipt.expiresAt >= startedMillis + RETENTION_MS - CLOCK_SKEW_MS)
        if (!validCode || !validUploadId || !validCount || !validExpiry) {
            throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
        }
    }
}

internal class DiagnosticLogStore(
    private val directory: File,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()
    private val _entries = MutableStateFlow<List<DiagnosticLogEntry>>(emptyList())
    val entries: StateFlow<List<DiagnosticLogEntry>> = _entries.asStateFlow()

    private val _storageError = MutableStateFlow<String?>(null)
    val storageError: StateFlow<String?> = _storageError.asStateFlow()

    @Volatile
    var scopeGeneration: UUID = UUID.randomUUID()
        private set

    @Volatile
    var accountID: String? = null
        private set

    @Volatile
    private var activated = false

    fun activateAccount(accountId: String?) {
        val nextScope = scopeKeyFor(accountId)
        synchronized(lock) {
            if (activated && this.accountID == accountId) return
            activated = true
            this.accountID = accountId
            scopeGeneration = UUID.randomUUID()
            _storageError.value = null
            val restored = readScopeEntriesLocked(nextScope, nowMillis())
            _entries.value = restored
        }
    }

    fun record(level: DiagnosticLogLevel, message: String) {
        val cleaned = DiagnosticText.redact(message, limit = 1500)
        if (cleaned.isBlank()) return
        val now = nowMillis()
        synchronized(lock) {
            val currentScope = scopeKeyFor(accountID)
            val cutoff = now - DiagnosticUploadRules.RETENTION_MS
            val kept = (_entries.value.filter { it.timestamp >= cutoff } +
                DiagnosticLogEntry(level = level, message = cleaned, timestamp = now))
                .takeLast(DiagnosticUploadRules.MAX_ENTRIES)
            _entries.value = kept
            writeScopeEntriesLocked(currentScope, kept)
        }
    }

    fun select(startTime: Long, endTime: Long): List<DiagnosticLogEntry> {
        val now = nowMillis()
        val cutoff = now - DiagnosticUploadRules.RETENTION_MS
        return _entries.value.filter { it.timestamp in cutoff..now && it.timestamp in startTime..endTime }
    }

    fun clear() {
        synchronized(lock) {
            val currentScope = scopeKeyFor(accountID)
            _entries.value = emptyList()
            _storageError.value = null
            runCatching {
                val target = fileFor(currentScope)
                if (target.exists()) target.delete()
            }
        }
    }

    private fun readScopeEntriesLocked(scope: String, now: Long): List<DiagnosticLogEntry> {
        val target = fileFor(scope)
        if (!target.isFile) return emptyList()
        return try {
            val bytes = target.readBytes()
            if (bytes.size > MAX_FILE_BYTES) {
                throw IllegalStateException("diagnostic file exceeds bound")
            }
            val obj = JSONObject(bytes.toString(Charsets.UTF_8))
            if (obj.optInt("version", 0) != 1 || obj.readString("scope") != scope) {
                emptyList()
            } else {
                val cutoff = now - DiagnosticUploadRules.RETENTION_MS
                val arr = obj.optJSONArray("entries") ?: JSONArray()
                (0 until arr.length()).mapNotNull { i ->
                    arr.optJSONObject(i)?.let(DiagnosticLogEntry::fromJson)
                }.filter { it.timestamp in cutoff..now }
                    .takeLast(DiagnosticUploadRules.MAX_ENTRIES)
            }
        } catch (_: Throwable) {
            _storageError.value = "此设备上的部分历史诊断日志已损坏，本次会话将重新记录。"
            emptyList()
        }
    }

    private fun writeScopeEntriesLocked(scope: String, list: List<DiagnosticLogEntry>) {
        try {
            val envelope = JSONObject()
                .put("version", 1)
                .put("scope", scope)
                .put(
                    "entries",
                    JSONArray().apply {
                        for (entry in list) put(entry.toJson())
                    },
                )
            val encoded = envelope.toString()
            if (encoded.toByteArray(Charsets.UTF_8).size > MAX_FILE_BYTES) {
                throw IllegalStateException("diagnostic envelope exceeds bound")
            }
            writeAtomicUtf8(fileFor(scope), encoded)
            _storageError.value = null
        } catch (_: Throwable) {
            _storageError.value = "诊断日志暂未保存到此设备。本次会话的记录仍保留在内存中，可稍后重试。"
        }
    }

    private fun scopeKeyFor(accountId: String?): String = if (accountId != null) {
        "account-" + sha256Hex(accountId.toByteArray(Charsets.UTF_8))
    } else {
        "guest"
    }

    private fun fileFor(scope: String): File = File(directory, "$scope.json")

    companion object {
        const val MAX_FILE_BYTES = 1024 * 1024
    }
}

internal interface DiagnosticServing {
    suspend fun upload(
        payload: DiagnosticUploadPayload,
        identity: AuthorizedAccount,
    ): DiagnosticUploadReceipt
}

internal class DiagnosticService(
    private val endpoint: String = DEFAULT_ENDPOINT,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) : DiagnosticServing {
    private val isLocalLoopback: Boolean

    init {
        val uri = runCatching { URI(endpoint) }.getOrNull()
        val host = uri?.host?.lowercase(Locale.ROOT)
        isLocalLoopback = uri?.scheme == "http" && (host == "127.0.0.1" || host == "localhost")
        require(endpoint.startsWith("https://") || isLocalLoopback) {
            "DiagnosticService requires https endpoint or local loopback test endpoint"
        }
    }

    override suspend fun upload(
        payload: DiagnosticUploadPayload,
        identity: AuthorizedAccount,
    ): DiagnosticUploadReceipt {
        val started = nowMillis()
        val frozen = DiagnosticUploadRules.normalize(payload, nowMillis = started)
        val encoded = frozen.toJson().toString().toByteArray(Charsets.UTF_8)
        if (encoded.size > DiagnosticUploadRules.MAX_BODY_BYTES) {
            throw DiagnosticException(DiagnosticError.TOO_LARGE)
        }

        val responseBytes = withContext(Dispatchers.IO) {
            val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
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
                conn.outputStream.use { it.write(encoded) }
                when (val status = conn.responseCode) {
                    401 -> throw DiagnosticException(DiagnosticError.UNAUTHORIZED)
                    403 -> throw DiagnosticException(DiagnosticError.FORBIDDEN)
                    413 -> throw DiagnosticException(DiagnosticError.TOO_LARGE)
                    429 -> throw DiagnosticException(DiagnosticError.THROTTLED)
                    400 -> throw DiagnosticException(DiagnosticError.INVALID_INPUT)
                    in 200..299 -> Unit
                    else -> if (status in 400..499) {
                        throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
                    } else {
                        throw DiagnosticException(DiagnosticError.UNAVAILABLE)
                    }
                }
                val contentType = conn.contentType?.lowercase(Locale.ROOT).orEmpty()
                if (!contentType.startsWith("application/json")) {
                    throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
                }
                readLimitedBytes(conn, DiagnosticUploadRules.MAX_RESPONSE_BYTES)
                    ?: throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
            } catch (e: DiagnosticException) {
                throw e
            } catch (t: Throwable) {
                throw DiagnosticException(DiagnosticError.UNAVAILABLE, t)
            } finally {
                conn.disconnect()
            }
        }

        val root = runCatching { JSONObject(responseBytes.toString(Charsets.UTF_8)) }.getOrNull()
            ?: throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
        if (root.optInt("code", -1) != 0) {
            throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
        }
        val dataObj = root.optJSONObject("data")
            ?: throw DiagnosticException(DiagnosticError.INVALID_RESPONSE)
        val receipt = DiagnosticUploadReceipt.fromJson(dataObj)
        DiagnosticUploadRules.validate(
            receipt = receipt,
            expectedCount = frozen.logs.count(),
            nowMillis = nowMillis(),
            startedMillis = started,
        )
        return receipt
    }

    private fun readLimitedBytes(conn: HttpURLConnection, limit: Int): ByteArray? {
        val stream = conn.inputStream ?: return ByteArray(0)
        return stream.use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(4096)
            var total = 0
            while (true) {
                val read = input.read(buf)
                if (read <= 0) break
                total += read
                if (total > limit) return null
                out.write(buf, 0, read)
            }
            out.toByteArray()
        }
    }

    companion object {
        const val DEFAULT_ENDPOINT = "https://www.yunle.fun/api/diagnostics/logs"
    }
}

internal class DiagnosticUploadStore(
    private val accounts: AccountStore,
    private val logs: DiagnosticLogStore,
    private val service: DiagnosticServing,
    private val receiptDirectory: File,
    private val scope: CoroutineScope,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val _isUploading = MutableStateFlow(false)
    val isUploading: StateFlow<Boolean> = _isUploading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _storageNotice = MutableStateFlow<String?>(null)
    val storageNotice: StateFlow<String?> = _storageNotice.asStateFlow()

    private val _receipt = MutableStateFlow<DiagnosticUploadReceipt?>(null)
    val receipt: StateFlow<DiagnosticUploadReceipt?> = _receipt.asStateFlow()

    private var prepared: DiagnosticUploadConfirmation? = null
    private var inFlight: DiagnosticUploadConfirmation? = null
    private var inFlightStarted = false
    private var uploadJob: Job? = null

    init {
        loadSavedReceipt()
    }

    fun prepare(
        startTime: Long,
        endTime: Long,
        issueDescription: String,
        client: DiagnosticClientContext,
    ): DiagnosticUploadConfirmation {
        if (inFlight != null) throw DiagnosticException(DiagnosticError.INVALID_INPUT)
        prepared = null
        val boundary = accounts.currentBoundary
        val uid = boundary.uid
        if (uid == null || accounts.user?.isUsable != true || logs.accountID != uid) {
            throw DiagnosticException(DiagnosticError.IDENTITY_CHANGED)
        }
        val now = nowMillis()
        val payload = DiagnosticUploadRules.normalize(
            DiagnosticUploadPayload(
                startTime = startTime,
                endTime = endTime,
                issueDescription = issueDescription,
                logs = logs.select(startTime, endTime),
                client = client,
            ),
            nowMillis = now,
        )
        val confirmation = DiagnosticUploadConfirmation(
            id = UUID.randomUUID(),
            payload = payload,
            boundary = boundary,
            logScopeGeneration = logs.scopeGeneration,
            sizeBytes = DiagnosticUploadRules.sizeBytes(payload),
        )
        prepared = confirmation
        _error.value = null
        return confirmation
    }

    fun upload(confirmation: DiagnosticUploadConfirmation) {
        if (inFlight != null) return
        val now = nowMillis()
        val stillValid = prepared == confirmation &&
            isCurrentConfirmation(confirmation) &&
            runCatching { DiagnosticUploadRules.normalize(confirmation.payload, now) == confirmation.payload }
                .getOrDefault(false)
        if (!stillValid) {
            if (accounts.currentBoundary == confirmation.boundary && _error.value == null) {
                _error.value = DiagnosticError.CONFIRMATION_EXPIRED.defaultMessage
            }
            return
        }
        prepared = null
        inFlight = confirmation
        inFlightStarted = false
        _isUploading.value = true
        _error.value = null
        val started = nowMillis()

        val job = scope.launch {
            try {
                val uploaded = accounts.runInBoundary(
                    boundary = confirmation.boundary,
                    isUnauthorized = { (it as? DiagnosticException)?.error?.isUnauthorized == true },
                    identityChangedError = { DiagnosticException(DiagnosticError.IDENTITY_CHANGED) },
                    unauthorizedError = { cause -> DiagnosticException(DiagnosticError.UNAUTHORIZED, cause) },
                ) { identity ->
                    ensureActiveConfirmation(confirmation)
                    inFlightStarted = true
                    val res = service.upload(confirmation.payload, identity)
                    ensureActiveConfirmation(confirmation)
                    res
                }
                ensureActiveConfirmation(confirmation)
                DiagnosticUploadRules.validate(
                    receipt = uploaded,
                    expectedCount = confirmation.payload.logs.size,
                    nowMillis = nowMillis(),
                    startedMillis = started,
                )
                _receipt.value = uploaded
                val uid = confirmation.boundary.uid
                if (uid != null && saveReceiptFile(uid, uploaded)) {
                    _storageNotice.value = null
                } else {
                    _storageNotice.value = DiagnosticError.STORAGE.defaultMessage
                }
            } catch (t: Throwable) {
                if (inFlight?.id == confirmation.id && isCurrentConfirmation(confirmation)) {
                    val mapped = DiagnosticError.fromThrowable(t)
                    val finalErr = if (!inFlightStarted && mapped == DiagnosticError.OUTCOME_UNKNOWN) {
                        DiagnosticError.UNAVAILABLE
                    } else {
                        mapped
                    }
                    _error.value = finalErr.defaultMessage
                }
            } finally {
                if (inFlight?.id == confirmation.id) {
                    inFlight = null
                    uploadJob = null
                    _isUploading.value = false
                }
            }
        }
        uploadJob = job
    }

    fun invalidateConfirmation() {
        prepared = null
        if (inFlight != null) cancelUpload()
    }

    fun cancelUpload() {
        prepared = null
        val active = inFlight ?: return
        uploadJob?.cancel()
        uploadJob = null
        inFlight = null
        _isUploading.value = false
        if (accounts.currentBoundary == active.boundary) {
            _error.value = if (inFlightStarted) {
                DiagnosticError.OUTCOME_UNKNOWN.defaultMessage
            } else {
                DiagnosticError.CANCELLED.defaultMessage
            }
        }
    }

    fun identityChanged() {
        prepared = null
        uploadJob?.cancel()
        uploadJob = null
        inFlight = null
        _isUploading.value = false
        _error.value = null
        _receipt.value = null
        _storageNotice.value = null
        loadSavedReceipt()
    }

    private fun isCurrentConfirmation(confirmation: DiagnosticUploadConfirmation): Boolean =
        accounts.currentBoundary == confirmation.boundary &&
            accounts.user?.isUsable == true &&
            logs.accountID == confirmation.boundary.uid &&
            logs.scopeGeneration == confirmation.logScopeGeneration

    private fun ensureActiveConfirmation(confirmation: DiagnosticUploadConfirmation) {
        if (inFlight?.id != confirmation.id || !isCurrentConfirmation(confirmation)) {
            throw DiagnosticException(DiagnosticError.CONFIRMATION_EXPIRED)
        }
    }

    private fun loadSavedReceipt() {
        val uid = accounts.currentBoundary.uid ?: return
        if (accounts.user?.isUsable != true) return
        val file = receiptFile(uid)
        if (!file.isFile) return
        try {
            val json = JSONObject(file.readText(Charsets.UTF_8))
            if (json.readString("owner") != uid) return
            val saved = DiagnosticUploadReceipt.fromJson(json.getJSONObject("receipt"))
            val now = nowMillis()
            if (saved.expiresAt <= now) {
                file.delete()
                return
            }
            DiagnosticUploadRules.validate(saved, nowMillis = now)
            _receipt.value = saved
        } catch (_: Throwable) {
            _storageNotice.value = "本机保存的支持编号暂时无法读取，请保留已复制的信息。"
        }
    }

    private fun saveReceiptFile(ownerUid: String, receipt: DiagnosticUploadReceipt): Boolean = runCatching {
        val obj = JSONObject()
            .put("version", 1)
            .put("owner", ownerUid)
            .put("receipt", receipt.toJson())
        writeAtomicUtf8(receiptFile(ownerUid), obj.toString())
        true
    }.getOrDefault(false)

    private fun receiptFile(ownerUid: String): File =
        File(receiptDirectory, "receipt-${sha256Hex(ownerUid.toByteArray(Charsets.UTF_8))}.json")
}
