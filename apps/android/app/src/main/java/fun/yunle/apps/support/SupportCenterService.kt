package `fun`.yunle.apps.support

import `fun`.yunle.apps.account.AccountError
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AccountRequestBoundary
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.games.sha256Hex
import `fun`.yunle.apps.games.writeAtomicUtf8
import `fun`.yunle.apps.readString
import `fun`.yunle.apps.webruntime.HostAuthorizationError
import `fun`.yunle.apps.webruntime.HostAuthorizationException
import `fun`.yunle.apps.webruntime.HostAuthorizationServing
import `fun`.yunle.apps.webruntime.HostSsoRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
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
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.Locale
import java.util.UUID

internal interface SupportCenterServing {
    suspend fun connect(identity: AuthorizedAccount?, consent: Boolean = false): SupportAccess
    suspend fun disconnect(access: SupportAccess)
    suspend fun board(cursor: String? = null): SupportPage<SupportBoardItem>
    suspend fun dashboard(
        product: String? = null,
        cursor: String? = null,
        access: SupportAccess,
    ): SupportDashboard

    suspend fun submit(
        product: String,
        category: String,
        description: String,
        screenshots: List<FeedbackScreenshot> = emptyList(),
        key: String,
        access: SupportAccess,
        context: SupportFeedbackSubmission.Context? = null,
    ): SupportFeedbackReceipt
}

internal class SupportCenterService(
    private val authorization: HostAuthorizationServing,
    private val origin: String = DEFAULT_ORIGIN,
    private val exchangeUrl: String = DEFAULT_EXCHANGE_URL,
) : SupportCenterServing {
    private val baseUrl = origin.trimEnd('/')
    private val isLocalTestOrigin = SupportUrlRules.isLoopbackOrigin(baseUrl)
    private val rng = SecureRandom()

    init {
        require(baseUrl.startsWith("https://") || isLocalTestOrigin) {
            "SupportCenterService requires https origin or local loopback test origin"
        }
    }

    override suspend fun connect(identity: AuthorizedAccount?, consent: Boolean): SupportAccess {
        if (identity == null) {
            val (guestJson, cookies) = requestJson(
                path = "api/v1/feedback/guest",
                method = "POST",
                body = "{}",
            )
            val kind = guestJson.readString("kind")
            val csrf = guestJson.readString("csrfToken").orEmpty()
            val guestCookies = cookies.filter { it.name == GUEST_COOKIE_NAME }
            if (kind != "guest" || csrf.isEmpty() || csrf.toByteArray(Charsets.UTF_8).size > 1024 ||
                guestCookies.isEmpty()
            ) {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            return SupportAccess(userID = null, csrfToken = csrf, cookies = guestCookies)
        }

        val verifier = randomBase64Url()
        val nonce = randomBase64Url()
        val challenge = sha256Base64Url(verifier.toByteArray(Charsets.UTF_8))

        val ssoRequest = HostSsoRequest.parse(
            sourceOrigin = DEFAULT_ORIGIN,
            parameters = JSONObject()
                .put("clientId", "support-web")
                .put("redirectUri", "$DEFAULT_ORIGIN/")
                .put("nonce", nonce)
                .put("codeChallenge", challenge)
                .put("codeChallengeMethod", "S256")
                .put("scope", JSONArray().put("identity:bootstrap")),
        )

        val code = try {
            val policy = authorization.resolve(ssoRequest)
            if (policy.applicationID != "support") {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            if (policy.prompt != null && !consent) {
                throw SupportCenterException(SupportCenterError.CONSENT_REQUIRED)
            }
            authorization.issue(ssoRequest, identity)
        } catch (e: HostAuthorizationException) {
            when (e.error) {
                HostAuthorizationError.UNAUTHORIZED -> throw SupportCenterException(SupportCenterError.UNAUTHORIZED, e)
                HostAuthorizationError.INVALID_RESPONSE -> throw SupportCenterException(SupportCenterError.INVALID_RESPONSE, e)
                else -> throw SupportCenterException(SupportCenterError.UNAVAILABLE, e)
            }
        }

        val exchangeBody = JSONObject()
            .put("action", "exchangeSsoCode")
            .put("clientId", "support-web")
            .put("redirectUri", ssoRequest.redirectURI)
            .put("scope", "identity:bootstrap")
            .put("code", code.code)
            .put("nonce", nonce)
            .put("codeVerifier", verifier)
            .toString()

        val (exchangeJson, _) = sendAbsoluteJson(
            urlString = exchangeUrl,
            method = "POST",
            body = exchangeBody,
            expectedOrigin = DEFAULT_ORIGIN,
        )
        val assertion = exchangeJson.readString("identityAssertion").orEmpty()
        if (exchangeJson.opt("ok") != true || assertion.length !in 64..8192) {
            throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        }

        val sessionExchangeBody = JSONObject()
            .put("accessToken", identity.accessToken)
            .put("identityAssertion", assertion)
            .put("nonce", nonce)
            .toString()
        val (connectedJson, cookies) = requestJson(
            path = "api/v1/session/exchange",
            method = "POST",
            body = sessionExchangeBody,
        )
        val connectedUid = connectedJson.optJSONObject("user")?.readString("userId")
        val csrf = connectedJson.readString("csrfToken").orEmpty()
        val sessionCookies = cookies.filter {
            it.name == SESSION_COOKIE_NAME && (it.isHttpOnly || isLocalTestOrigin)
        }
        if (connectedJson.opt("ok") != true ||
            connectedUid != identity.userID ||
            csrf.isEmpty() ||
            sessionCookies.isEmpty()
        ) {
            throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        }
        return SupportAccess(userID = identity.userID, csrfToken = csrf, cookies = sessionCookies)
    }

    override suspend fun disconnect(access: SupportAccess) {
        if (access.userID == null || access.cookies.isEmpty()) return
        val (ackJson, _) = requestJson(
            path = "api/v1/session",
            method = "DELETE",
            body = null,
            access = access,
        )
        if (ackJson.opt("ok") != true) {
            throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        }
    }

    override suspend fun board(cursor: String?): SupportPage<SupportBoardItem> {
        val query = if (!cursor.isNullOrBlank()) {
            mapOf("cursor" to cursor)
        } else {
            emptyMap()
        }
        val (json, _) = requestJson(
            path = "api/v1/feedback",
            method = "GET",
            query = query,
        )
        val page = SupportDashboard.parseBoardPage(json)
        if (page.items.any { !SupportUrlRules.isValidIdentifier(it.id) }) {
            throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        }
        return page
    }

    override suspend fun dashboard(
        product: String?,
        cursor: String?,
        access: SupportAccess,
    ): SupportDashboard {
        val query = linkedMapOf<String, String>()
        if (!product.isNullOrBlank()) query["product"] = product
        if (!cursor.isNullOrBlank()) query["privateCursor"] = cursor
        val (json, _) = requestJson(
            path = "api/internal/v1/dashboard",
            method = "GET",
            query = query,
            access = access,
        )
        val dashboard = SupportDashboard.fromJson(json)
        val validPrivate = dashboard.privateFeedback.items.all {
            SupportUrlRules.isValidIdentifier(it.id) && it.productId == dashboard.productId
        }
        val validBoard = dashboard.feedback.items.all {
            SupportUrlRules.isValidIdentifier(it.id) && it.productId == dashboard.productId
        }
        if (!validPrivate || !validBoard) {
            throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        }
        return dashboard
    }

    override suspend fun submit(
        product: String,
        category: String,
        description: String,
        screenshots: List<FeedbackScreenshot>,
        key: String,
        access: SupportAccess,
        context: SupportFeedbackSubmission.Context?,
    ): SupportFeedbackReceipt {
        if (!SupportUrlRules.isValidIdempotencyKey(key)) {
            throw SupportCenterException(SupportCenterError.INVALID_INPUT)
        }
        val submission = SupportFeedbackSubmission.fromScreenshots(
            product = product,
            category = category,
            description = description,
            screenshots = screenshots,
            context = context,
        )
        submission.validate()
        val (json, _) = requestJson(
            path = "api/v1/private-feedback",
            method = "POST",
            body = submission.toJson().toString(),
            access = access,
            idempotencyKey = key,
        )
        val receiptObj = json.optJSONObject("receipt")
            ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        val receipt = SupportFeedbackReceipt.fromJson(receiptObj)
        if (!SupportUrlRules.isValidIdentifier(receipt.id) ||
            receipt.productId != submission.productId ||
            (receipt.ticketId != null && !SupportUrlRules.isValidIdentifier(receipt.ticketId))
        ) {
            throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
        }
        return receipt
    }

    private suspend fun requestJson(
        path: String,
        method: String,
        query: Map<String, String> = emptyMap(),
        body: String? = null,
        access: SupportAccess? = null,
        idempotencyKey: String? = null,
    ): Pair<JSONObject, List<SupportHttpCookie>> {
        val urlBuilder = StringBuilder("$baseUrl/${path.trimStart('/')}")
        if (query.isNotEmpty()) {
            urlBuilder.append('?')
            urlBuilder.append(
                query.entries.joinToString("&") { (k, v) ->
                    "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
                },
            )
        }
        return sendAbsoluteJson(
            urlString = urlBuilder.toString(),
            method = method,
            body = body,
            access = access,
            idempotencyKey = idempotencyKey,
            expectedOrigin = baseUrl,
            pathForStatus = path,
        )
    }

    private suspend fun sendAbsoluteJson(
        urlString: String,
        method: String,
        body: String? = null,
        access: SupportAccess? = null,
        idempotencyKey: String? = null,
        expectedOrigin: String = baseUrl,
        pathForStatus: String = urlString,
    ): Pair<JSONObject, List<SupportHttpCookie>> = withContext(Dispatchers.IO) {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Origin", expectedOrigin)
            if (access != null && access.cookies.isNotEmpty()) {
                setRequestProperty("Cookie", access.cookieHeader())
                if (method != "GET" && access.csrfToken.isNotEmpty()) {
                    setRequestProperty("x-csrf-token", access.csrfToken)
                }
            }
            if (!idempotencyKey.isNullOrBlank()) {
                setRequestProperty("idempotency-key", idempotencyKey)
            }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (body != null) {
                conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val status = conn.responseCode
            when (status) {
                401 -> throw SupportCenterException(SupportCenterError.UNAUTHORIZED)
                403 -> throw SupportCenterException(SupportCenterError.FORBIDDEN)
                413 -> throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
                429 -> throw SupportCenterException(SupportCenterError.THROTTLED)
                400 -> {
                    val err = if (pathForStatus.endsWith("private-feedback")) {
                        SupportCenterError.INVALID_SCREENSHOT
                    } else {
                        SupportCenterError.INVALID_INPUT
                    }
                    throw SupportCenterException(err)
                }
            }
            if (status !in 200..299) {
                throw SupportCenterException(SupportCenterError.UNAVAILABLE)
            }
            val contentType = conn.contentType?.lowercase(Locale.ROOT).orEmpty()
            if (!contentType.startsWith("application/json")) {
                throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            }
            val raw = readLimitedSupportBytes(conn, MAXIMUM_RESPONSE_BYTES)
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val parsed = runCatching { JSONObject(raw.toString(Charsets.UTF_8)) }.getOrNull()
                ?: throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
            val cookies = extractCookies(conn.headerFields, requireSecure = !isLocalTestOrigin)
            parsed to cookies
        } catch (e: SupportCenterException) {
            throw e
        } catch (t: Throwable) {
            throw SupportCenterException(SupportCenterError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }

    private fun randomBase64Url(): String {
        val bytes = ByteArray(32)
        rng.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    private fun sha256Base64Url(input: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }

    companion object {
        const val DEFAULT_ORIGIN = "https://support.yunle.fun"
        const val DEFAULT_EXCHANGE_URL = "https://api.yunle.fun/sso-ticket"
        const val GUEST_COOKIE_NAME = "__Host-ylf-support-guest"
        const val SESSION_COOKIE_NAME = "__Host-ylf-support-session"
        const val MAXIMUM_RESPONSE_BYTES = 2 * 1024 * 1024
    }
}

internal interface SupportTicketServing {
    suspend fun load(
        receipt: SupportFeedbackReceipt,
        cookies: List<SupportHttpCookie> = emptyList(),
    ): SupportTicketSnapshot

    suspend fun screenshotBytes(
        item: SupportTicketScreenshot,
        snapshot: SupportTicketSnapshot,
    ): ByteArray
}

internal class SupportTicketClient(
    private val origin: String = SupportCenterService.DEFAULT_ORIGIN,
) : SupportTicketServing {
    private val baseUrl = origin.trimEnd('/')
    private val isLocalTestOrigin = SupportUrlRules.isLoopbackOrigin(baseUrl)

    init {
        require(baseUrl.startsWith("https://") || isLocalTestOrigin) {
            "SupportTicketClient requires https origin or local loopback test origin"
        }
    }

    override suspend fun load(
        receipt: SupportFeedbackReceipt,
        cookies: List<SupportHttpCookie>,
    ): SupportTicketSnapshot {
        val ticketId = receipt.ticketId?.takeIf(SupportUrlRules::isValidIdentifier)
            ?: throw SupportTicketException(SupportTicketError.NOT_FOUND)
        val scopedCookies = if (cookies.isNotEmpty()) {
            cookies
        } else {
            val token = SupportUrlRules.extractAccessToken(
                SupportUrlRules.ticketUrl(receipt, origin = baseUrl, requiringGuestAccess = true),
            ) ?: throw SupportTicketException(SupportTicketError.EXPIRED)
            val accessBody = JSONObject().put("token", token).toString()
            val (accessBytes, responseCookies) = requestRaw(
                path = "api/v1/tickets/$ticketId/access",
                method = "POST",
                body = accessBody.toByteArray(Charsets.UTF_8),
                cookies = emptyList(),
                expectImage = false,
            )
            val accessJson = runCatching { JSONObject(accessBytes.toString(Charsets.UTF_8)) }.getOrNull()
                ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            val ticketCsrf = accessJson.readString("ticketCsrf").orEmpty()
            if (ticketCsrf.isEmpty() || ticketCsrf.toByteArray(Charsets.UTF_8).size > 1024) {
                throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            }
            val expectedCookieName = "__Host-ylf-ticket-$ticketId"
            val matched = responseCookies.filter {
                it.name == expectedCookieName && (it.isHttpOnly || isLocalTestOrigin)
            }
            if (matched.isEmpty()) {
                throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            }
            matched
        }

        val (detailBytes, _) = requestRaw(
            path = "api/v1/tickets/$ticketId",
            method = "GET",
            cookies = scopedCookies,
            expectImage = false,
        )
        val detailJson = runCatching { JSONObject(detailBytes.toString(Charsets.UTF_8)) }.getOrNull()
            ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        val detail = SupportTicketDetail.fromJson(detailJson)
        if (detail.ticket.id != ticketId || detail.ticket.productId != receipt.productId) {
            throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        }

        val (shotsBytes, _) = requestRaw(
            path = "api/v1/tickets/$ticketId/screenshots",
            method = "GET",
            cookies = scopedCookies,
            expectImage = false,
        )
        val shotsJson = runCatching { JSONObject(shotsBytes.toString(Charsets.UTF_8)) }.getOrNull()
            ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        val arr = shotsJson.optJSONArray("items")
            ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        if (arr.length() > FeedbackScreenshot.MAXIMUM_COUNT) {
            throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        }
        val screenshots = (0 until arr.length()).map { i ->
            val obj = arr.optJSONObject(i) ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            SupportTicketScreenshot.fromJson(obj)
        }
        if (screenshots.map { it.id }.toSet().size != screenshots.size) {
            throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        }
        return SupportTicketSnapshot(
            detail = detail,
            screenshots = screenshots,
            cookies = scopedCookies,
        )
    }

    override suspend fun screenshotBytes(
        item: SupportTicketScreenshot,
        snapshot: SupportTicketSnapshot,
    ): ByteArray {
        val ticketId = snapshot.detail.ticket.id
        if (item !in snapshot.screenshots ||
            !SupportUrlRules.isValidIdentifier(ticketId) ||
            !SupportUrlRules.isValidIdentifier(item.id)
        ) {
            throw SupportTicketException(SupportTicketError.NOT_FOUND)
        }
        val (bytes, _) = requestRaw(
            path = "api/v1/tickets/$ticketId/screenshots/${item.id}",
            method = "GET",
            cookies = snapshot.cookies,
            expectImage = true,
            exactImageBytes = item.sizeBytes,
        )
        if (!SupportUrlRules.isValidJpegBytes(bytes) || bytes.size != item.sizeBytes) {
            throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
        }
        return bytes
    }

    private suspend fun requestRaw(
        path: String,
        method: String,
        body: ByteArray? = null,
        cookies: List<SupportHttpCookie>,
        expectImage: Boolean,
        exactImageBytes: Int? = null,
    ): Pair<ByteArray, List<SupportHttpCookie>> = withContext(Dispatchers.IO) {
        val conn = (URL("$baseUrl/${path.trimStart('/')}").openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", if (expectImage) "image/jpeg" else "application/json")
            setRequestProperty("Origin", baseUrl)
            if (cookies.isNotEmpty()) {
                setRequestProperty("Cookie", cookies.joinToString("; ") { "${it.name}=${it.value}" })
            }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (body != null) {
                conn.outputStream.use { it.write(body) }
            }
            when (val status = conn.responseCode) {
                401, 403 -> throw SupportTicketException(SupportTicketError.EXPIRED)
                404 -> throw SupportTicketException(SupportTicketError.NOT_FOUND)
                429 -> throw SupportTicketException(SupportTicketError.THROTTLED)
                in 200..299 -> Unit
                else -> if (status in 400..499) {
                    throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                } else {
                    throw SupportTicketException(SupportTicketError.UNAVAILABLE)
                }
            }
            val contentType = conn.contentType?.lowercase(Locale.ROOT).orEmpty()
            if (expectImage) {
                if (!contentType.startsWith("image/jpeg")) {
                    throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
                }
            } else if (!contentType.startsWith("application/json")) {
                throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            }
            val maxBytes = exactImageBytes ?: SupportCenterService.MAXIMUM_RESPONSE_BYTES
            val raw = readLimitedSupportBytes(conn, maxBytes.coerceAtMost(SupportCenterService.MAXIMUM_RESPONSE_BYTES))
                ?: throw SupportTicketException(SupportTicketError.INVALID_RESPONSE)
            val responseCookies = extractCookies(conn.headerFields, requireSecure = !isLocalTestOrigin)
            raw to responseCookies
        } catch (e: SupportTicketException) {
            throw e
        } catch (t: Throwable) {
            throw SupportTicketException(SupportTicketError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }
}

internal class SharedFeedbackHistoryStore(
    private val file: File,
) {
    private val lock = Any()
    private val _records = MutableStateFlow<List<SharedFeedbackRecord>>(emptyList())
    val records: StateFlow<List<SharedFeedbackRecord>> = _records.asStateFlow()

    @Volatile
    private var ownerKey: String? = null

    @Volatile
    private var activated = false

    fun activate(userId: String?) {
        val nextOwner = scopeKey(userId)
        synchronized(lock) {
            val loaded = readFileLocked()
            val adopted = if (loaded != null) {
                if (loaded.ownerKey != null && loaded.ownerKey != nextOwner) {
                    emptyList()
                } else {
                    loaded.records
                }
            } else {
                emptyList()
            }
            activated = true
            ownerKey = nextOwner
            _records.value = adopted
            writeFileLocked(nextOwner, adopted)
        }
    }

    fun save(record: SharedFeedbackRecord, expectedUserId: String? = null): Boolean {
        if (!SupportUrlRules.isValidIdentifier(record.receipt.id) ||
            record.receipt.productId !in SupportProduct.submissionIDs ||
            record.createdAtMillis <= 0L
        ) {
            return false
        }
        synchronized(lock) {
            val targetOwner = if (activated) ownerKey else expectedUserId?.let(::scopeKey)
            val current = readFileLocked()
            val baseRecords = if (current == null) {
                emptyList()
            } else if (current.ownerKey != null && targetOwner != null && current.ownerKey != targetOwner) {
                emptyList()
            } else {
                current.records
            }
            val updated = (listOf(record) + baseRecords.filterNot { it.id == record.id })
                .take(MAXIMUM_RECORDS)
            ownerKey = targetOwner
            _records.value = updated
            return writeFileLocked(targetOwner, updated)
        }
    }

    fun clear() {
        synchronized(lock) {
            val currentOwner = ownerKey ?: scopeKey(null)
            _records.value = emptyList()
            writeFileLocked(currentOwner, emptyList())
        }
    }

    private data class StoredEnvelope(
        val ownerKey: String?,
        val records: List<SharedFeedbackRecord>,
    )

    private fun readFileLocked(): StoredEnvelope? {
        if (!file.isFile) return null
        return runCatching {
            val raw = file.readBytes()
            if (raw.size > MAXIMUM_FILE_BYTES) return null
            val json = JSONObject(raw.toString(Charsets.UTF_8))
            if (json.optInt("schemaVersion", 0) != 1) return null
            val storedOwner = json.readString("ownerKey")
            val arr = json.optJSONArray("records") ?: JSONArray()
            val parsed = (0 until arr.length()).mapNotNull { i ->
                arr.optJSONObject(i)?.let(SharedFeedbackRecord::fromJson)
            }.take(MAXIMUM_RECORDS)
            StoredEnvelope(ownerKey = storedOwner, records = parsed)
        }.getOrNull()
    }

    private fun writeFileLocked(owner: String?, list: List<SharedFeedbackRecord>): Boolean = runCatching {
        val obj = JSONObject()
            .put("schemaVersion", 1)
            .put("ownerKey", owner ?: JSONObject.NULL)
            .put(
                "records",
                JSONArray().apply {
                    for (rec in list) put(rec.toJson())
                },
            )
        writeAtomicUtf8(file, obj.toString())
        true
    }.getOrDefault(false)

    private fun scopeKey(userId: String?): String {
        val prefix = if (userId != null) "user:$userId" else "guest"
        return sha256Hex(prefix.toByteArray(Charsets.UTF_8))
    }

    companion object {
        const val MAXIMUM_RECORDS = 20
        private const val MAXIMUM_FILE_BYTES = 128 * 1024
    }
}

internal class SupportCenterController(
    private val accounts: AccountStore,
    private val service: SupportCenterServing,
    private val scope: CoroutineScope,
) {
    private val _board = MutableStateFlow<List<SupportBoardItem>>(emptyList())
    val board: StateFlow<List<SupportBoardItem>> = _board.asStateFlow()

    private val _boardCursor = MutableStateFlow<String?>(null)
    val boardCursor: StateFlow<String?> = _boardCursor.asStateFlow()

    private val _dashboard = MutableStateFlow<SupportDashboard?>(null)
    val dashboard: StateFlow<SupportDashboard?> = _dashboard.asStateFlow()

    private val _receipt = MutableStateFlow<SupportFeedbackReceipt?>(null)
    val receipt: StateFlow<SupportFeedbackReceipt?> = _receipt.asStateFlow()

    private val _connected = MutableStateFlow<SupportAccess?>(null)
    val connected: StateFlow<SupportAccess?> = _connected.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isSubmitting = MutableStateFlow(false)
    val isSubmitting: StateFlow<Boolean> = _isSubmitting.asStateFlow()

    private val _hasLoaded = MutableStateFlow(false)
    val hasLoaded: StateFlow<Boolean> = _hasLoaded.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _needsConsent = MutableStateFlow(false)
    val needsConsent: StateFlow<Boolean> = _needsConsent.asStateFlow()

    private var boundary: AccountRequestBoundary = accounts.currentBoundary
    private var operationId: UUID = UUID.randomUUID()
    private var lastSubmissionDigest: List<String> = emptyList()
    private var submissionKey: String = UUID.randomUUID().toString()

    fun identityChanged() {
        close()
        operationId = UUID.randomUUID()
        boundary = accounts.currentBoundary
        _board.value = emptyList()
        _boardCursor.value = null
        _dashboard.value = null
        _receipt.value = null
        _connected.value = null
        _isLoading.value = false
        _isSubmitting.value = false
        _hasLoaded.value = false
        _error.value = null
        _needsConsent.value = false
        lastSubmissionDigest = emptyList()
        submissionKey = UUID.randomUUID().toString()
    }

    fun close() {
        operationId = UUID.randomUUID()
        val prev = _connected.value
        _connected.value = null
        _dashboard.value = null
        _receipt.value = null
        _isLoading.value = false
        _isSubmitting.value = false
        if (prev != null && prev.userID != null) {
            scope.launch(Dispatchers.IO) {
                runCatching { service.disconnect(prev) }
            }
        }
    }

    fun clearReceipt() {
        _receipt.value = null
        _error.value = null
        lastSubmissionDigest = emptyList()
        submissionKey = UUID.randomUUID().toString()
    }

    suspend fun load(
        destination: SupportDestination,
        product: String? = null,
        more: Boolean = false,
        consent: Boolean = false,
    ) {
        if (accounts.currentBoundary != boundary) identityChanged()
        if (_isSubmitting.value) return
        val opBoundary = boundary
        val op = UUID.randomUUID()
        operationId = op
        _isLoading.value = true
        _error.value = null
        _needsConsent.value = false
        if (!more) {
            _hasLoaded.value = false
            _dashboard.value = null
        }
        try {
            when (destination) {
                SupportDestination.BOARD -> {
                    if (!more) {
                        _board.value = emptyList()
                        _boardCursor.value = null
                    }
                    val cursor = if (more) _boardCursor.value else null
                    val page = service.board(cursor = cursor)
                    checkCurrent(opBoundary, op)
                    val prevIds = _board.value.map { it.id }.toSet()
                    _board.value = if (more) {
                        _board.value + page.items.filterNot { it.id in prevIds }
                    } else {
                        page.items
                    }
                    _boardCursor.value = page.nextCursor
                    if (opBoundary.uid != null) {
                        val access = ensureConnection(opBoundary, op, consent)
                        checkCurrent(opBoundary, op)
                        _connected.value = access
                    }
                }
                SupportDestination.COMPOSE -> {
                    val access = ensureConnection(opBoundary, op, consent)
                    checkCurrent(opBoundary, op)
                    _connected.value = access
                }
                SupportDestination.MANAGE -> {
                    if (opBoundary.uid == null) {
                        throw SupportCenterException(SupportCenterError.UNAUTHORIZED)
                    }
                    val access = ensureConnection(opBoundary, op, consent)
                    checkCurrent(opBoundary, op)
                    _connected.value = access
                    val cursor = if (more) _dashboard.value?.privateFeedback?.nextCursor else null
                    val page = service.dashboard(product = product, cursor = cursor, access = access)
                    checkCurrent(opBoundary, op)
                    val merged = if (more) {
                        val prevPrivate = _dashboard.value?.privateFeedback?.items.orEmpty()
                        val prevIds = prevPrivate.map { it.id }.toSet()
                        page.copy(
                            privateFeedback = SupportPage(
                                items = prevPrivate + page.privateFeedback.items.filterNot { it.id in prevIds },
                                nextCursor = page.privateFeedback.nextCursor,
                            ),
                        )
                    } else {
                        page
                    }
                    _dashboard.value = merged
                }
            }
            _hasLoaded.value = true
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            if (operationId == op && accounts.currentBoundary == opBoundary) {
                val sc = t as? SupportCenterException
                if (sc?.error == SupportCenterError.UNAUTHORIZED) {
                    _connected.value = null
                }
                _needsConsent.value = sc?.error == SupportCenterError.CONSENT_REQUIRED
                _error.value = when (t) {
                    is SupportCenterException -> t.message
                    is AccountException -> t.error.message
                    else -> SupportCenterError.UNAVAILABLE.defaultMessage
                }
            }
        } finally {
            if (operationId == op) _isLoading.value = false
        }
    }

    suspend fun submit(
        product: String,
        category: String,
        description: String,
        screenshots: List<FeedbackScreenshot> = emptyList(),
        context: SupportFeedbackSubmission.Context? = null,
    ) {
        val currentAccess = _connected.value ?: return
        if (accounts.currentBoundary != boundary || _isLoading.value || _isSubmitting.value || _receipt.value != null) {
            return
        }
        val opBoundary = boundary
        val op = UUID.randomUUID()
        operationId = op
        _isSubmitting.value = true
        _error.value = null
        val trimmedDesc = description.trim()
        val digest = listOf(product, category, trimmedDesc) + screenshots.map { it.sha256Hex() }
        if (digest != lastSubmissionDigest) {
            lastSubmissionDigest = digest
            submissionKey = UUID.randomUUID().toString()
        }
        try {
            val result = service.submit(
                product = product,
                category = category,
                description = trimmedDesc,
                screenshots = screenshots,
                key = submissionKey,
                access = currentAccess,
                context = context,
            )
            checkCurrent(opBoundary, op)
            _receipt.value = result
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            if (operationId == op && accounts.currentBoundary == opBoundary) {
                val sc = t as? SupportCenterException
                if (sc?.error == SupportCenterError.UNAUTHORIZED) {
                    _connected.value = null
                }
                _error.value = when (t) {
                    is SupportCenterException -> t.message
                    else -> "提交结果尚未确认。请重试，未修改的内容会使用同一提交编号，避免重复反馈。"
                }
            }
        } finally {
            if (operationId == op) _isSubmitting.value = false
        }
    }

    private suspend fun ensureConnection(
        opBoundary: AccountRequestBoundary,
        op: UUID,
        consent: Boolean,
    ): SupportAccess {
        val existing = _connected.value
        if (existing != null && accounts.currentBoundary == opBoundary && boundary == opBoundary) {
            return existing
        }
        val access = if (opBoundary.uid != null) {
            var issued: SupportAccess? = null
            try {
                accounts.runInBoundary(
                    boundary = opBoundary,
                    isUnauthorized = { (it as? SupportCenterException)?.error?.isUnauthorized == true },
                    identityChangedError = { SupportCenterException(SupportCenterError.IDENTITY_CHANGED) },
                    unauthorizedError = { cause -> SupportCenterException(SupportCenterError.UNAUTHORIZED, cause) },
                ) { identity ->
                    val res = service.connect(identity = identity, consent = consent)
                    issued = res
                    res
                }
            } catch (t: Throwable) {
                val orphan = issued
                if (orphan != null && orphan.userID != null) {
                    scope.launch(Dispatchers.IO + NonCancellable) {
                        runCatching { service.disconnect(orphan) }
                    }
                }
                throw t
            }
        } else {
            service.connect(identity = null, consent = false)
        }
        if (operationId != op || accounts.currentBoundary != opBoundary) {
            if (access.userID != null) {
                scope.launch(Dispatchers.IO + NonCancellable) {
                    runCatching { service.disconnect(access) }
                }
            }
            throw SupportCenterException(SupportCenterError.IDENTITY_CHANGED)
        }
        return access
    }

    private fun checkCurrent(opBoundary: AccountRequestBoundary, op: UUID) {
        if (operationId != op || accounts.currentBoundary != opBoundary) {
            throw SupportCenterException(SupportCenterError.IDENTITY_CHANGED)
        }
    }
}

internal suspend fun <T> AccountStore.runInBoundary(
    boundary: AccountRequestBoundary,
    isUnauthorized: (Throwable) -> Boolean,
    identityChangedError: () -> Throwable,
    unauthorizedError: (Throwable) -> Throwable,
    block: suspend (AuthorizedAccount) -> T,
): T {
    if (currentBoundary != boundary) throw identityChangedError()
    var identity = try {
        authorization(forceRefresh = false)
    } catch (e: AccountException) {
        if (currentBoundary != boundary) throw identityChangedError()
        throw when (e.error) {
            AccountError.SIGNED_OUT, AccountError.EXPIRED_SESSION -> unauthorizedError(e)
            AccountError.SESSION_CHANGED -> identityChangedError()
            else -> e
        }
    }
    if (currentBoundary != boundary || identity.userID != boundary.uid) {
        throw identityChangedError()
    }
    return try {
        block(identity)
    } catch (t: Throwable) {
        if (currentBoundary != boundary) throw identityChangedError()
        if (!isUnauthorized(t)) throw t
        identity = try {
            authorization(forceRefresh = true)
        } catch (refreshErr: AccountException) {
            if (currentBoundary != boundary) throw identityChangedError()
            throw when (refreshErr.error) {
                AccountError.SIGNED_OUT, AccountError.EXPIRED_SESSION -> unauthorizedError(refreshErr)
                AccountError.SESSION_CHANGED -> identityChangedError()
                else -> refreshErr
            }
        }
        if (currentBoundary != boundary || identity.userID != boundary.uid) {
            throw identityChangedError()
        }
        block(identity)
    }
}

private fun extractCookies(
    headerFields: Map<String?, List<String>>,
    requireSecure: Boolean,
): List<SupportHttpCookie> {
    val result = mutableListOf<SupportHttpCookie>()
    for ((key, values) in headerFields) {
        if (!key.equals("Set-Cookie", ignoreCase = true)) continue
        for (rawHeader in values) {
            val parts = rawHeader.split(';')
            val nameValue = parts.firstOrNull()?.trim().orEmpty()
            val eqIdx = nameValue.indexOf('=')
            if (eqIdx <= 0) continue
            val cookieName = nameValue.substring(0, eqIdx).trim()
            val cookieVal = nameValue.substring(eqIdx + 1).trim()
            val attrs = parts.drop(1).map { it.trim().lowercase(Locale.ROOT) }
            val hasHttpOnly = attrs.any { it == "httponly" }
            val hasSecure = attrs.any { it == "secure" }
            if (requireSecure && !hasSecure) continue
            result.add(
                SupportHttpCookie(
                    name = cookieName,
                    value = cookieVal,
                    isHttpOnly = hasHttpOnly,
                    isSecure = hasSecure,
                ),
            )
        }
    }
    return result
}

private fun readLimitedSupportBytes(conn: HttpURLConnection, limit: Int): ByteArray? {
    val stream = conn.inputStream ?: return ByteArray(0)
    return stream.use { input ->
        val out = ByteArrayOutputStream()
        val buf = ByteArray(8192)
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
