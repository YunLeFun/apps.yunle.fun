package `fun`.yunle.apps

import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.diagnostics.DiagnosticClientContext
import `fun`.yunle.apps.diagnostics.DiagnosticError
import `fun`.yunle.apps.diagnostics.DiagnosticException
import `fun`.yunle.apps.diagnostics.DiagnosticLogEntry
import `fun`.yunle.apps.diagnostics.DiagnosticLogLevel
import `fun`.yunle.apps.diagnostics.DiagnosticLogStore
import `fun`.yunle.apps.diagnostics.DiagnosticService
import `fun`.yunle.apps.diagnostics.DiagnosticText
import `fun`.yunle.apps.diagnostics.DiagnosticUploadPayload
import `fun`.yunle.apps.diagnostics.DiagnosticUploadRules
import `fun`.yunle.apps.support.FeedbackScreenshot
import `fun`.yunle.apps.support.SharedFeedbackHistoryStore
import `fun`.yunle.apps.support.SharedFeedbackRecord
import `fun`.yunle.apps.support.SupportCenterError
import `fun`.yunle.apps.support.SupportCenterException
import `fun`.yunle.apps.support.SupportCenterService
import `fun`.yunle.apps.support.SupportFeedbackReceipt
import `fun`.yunle.apps.support.SupportFeedbackSubmission
import `fun`.yunle.apps.support.SupportTicketClient
import `fun`.yunle.apps.support.SupportTicketError
import `fun`.yunle.apps.support.SupportTicketException
import `fun`.yunle.apps.support.SupportUrlRules
import `fun`.yunle.apps.webruntime.HostAuthorizationServing
import `fun`.yunle.apps.webruntime.HostSsoCode
import `fun`.yunle.apps.webruntime.HostSsoPolicy
import `fun`.yunle.apps.webruntime.HostSsoRequest
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.BufferedInputStream
import java.io.Closeable
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors

class M6SupportDiagnosticsTest {
    private data class HttpReq(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
        val body: String,
    )

    private data class HttpRes(
        val status: Int = 200,
        val contentType: String = "application/json; charset=utf-8",
        val extraHeaders: List<Pair<String, String>> = emptyList(),
        val bodyBytes: ByteArray = "{}".toByteArray(Charsets.UTF_8),
    )

    private class LocalStubHttp(
        private val handler: (HttpReq) -> HttpRes,
    ) : Closeable {
        private val server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        private val pool = Executors.newCachedThreadPool()
        val requests = ConcurrentLinkedQueue<HttpReq>()
        val origin: String get() = "http://127.0.0.1:${server.localPort}"

        init {
            pool.execute {
                while (!server.isClosed) {
                    val socket = runCatching { server.accept() }.getOrNull() ?: break
                    pool.execute {
                        socket.use { s ->
                            val input = BufferedInputStream(s.getInputStream())
                            val buf = ArrayList<Byte>()
                            while (true) {
                                val b = input.read()
                                if (b == -1) return@use
                                buf.add(b.toByte())
                                val n = buf.size
                                if (n >= 4 &&
                                    buf[n - 4] == '\r'.code.toByte() &&
                                    buf[n - 3] == '\n'.code.toByte() &&
                                    buf[n - 2] == '\r'.code.toByte() &&
                                    buf[n - 1] == '\n'.code.toByte()
                                ) {
                                    break
                                }
                            }
                            val rawHeader = buf.toByteArray().toString(Charsets.UTF_8)
                            val lines = rawHeader.split("\r\n").filter { it.isNotEmpty() }
                            if (lines.isEmpty()) return@use
                            val parts = lines.first().split(' ')
                            val method = parts.getOrElse(0) { "GET" }
                            val path = parts.getOrElse(1) { "/" }
                            val headers = linkedMapOf<String, String>()
                            for (line in lines.drop(1)) {
                                val colon = line.indexOf(':')
                                if (colon > 0) {
                                    headers[line.substring(0, colon).trim().lowercase()] =
                                        line.substring(colon + 1).trim()
                                }
                            }
                            val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
                            val bodyBytes = ByteArray(contentLength)
                            var offset = 0
                            while (offset < contentLength) {
                                val r = input.read(bodyBytes, offset, contentLength - offset)
                                if (r <= 0) break
                                offset += r
                            }
                            val recorded = HttpReq(
                                method = method,
                                path = path,
                                headers = headers,
                                body = bodyBytes.toString(Charsets.UTF_8),
                            )
                            requests.add(recorded)
                            val res = handler(recorded)
                            val out = s.getOutputStream()
                            val headerBuilder = StringBuilder()
                                .append("HTTP/1.1 ").append(res.status).append(" OK\r\n")
                                .append("Content-Type: ").append(res.contentType).append("\r\n")
                                .append("Content-Length: ").append(res.bodyBytes.size).append("\r\n")
                            for ((k, v) in res.extraHeaders) {
                                headerBuilder.append(k).append(": ").append(v).append("\r\n")
                            }
                            headerBuilder.append("Connection: close\r\n\r\n")
                            out.write(headerBuilder.toString().toByteArray(Charsets.UTF_8))
                            out.write(res.bodyBytes)
                            out.flush()
                        }
                    }
                }
            }
        }

        override fun close() {
            runCatching { server.close() }
            pool.shutdownNow()
        }
    }

    @Test
    fun supportCenterGuestSignedInBoardAndValidation() = runBlocking {
        var promptMode: String? = "consent"
        val identity = AuthorizedAccount(
            userID = "user_m6",
            accessToken = "tok_m6_secret",
        )
        val fakeAuth = object : HostAuthorizationServing {
            override suspend fun resolve(request: HostSsoRequest): HostSsoPolicy {
                assertEquals("support-web", request.clientID)
                return HostSsoPolicy(
                    applicationID = "support",
                    applicationName = "云乐坊支持中心",
                    applicationOrigin = request.sourceOrigin,
                    applicationIconURL = null,
                    permissionDescription = "账号标识、昵称和头像",
                    prompt = promptMode,
                    version = "1",
                    registrationFingerprint = "a".repeat(64),
                )
            }

            override suspend fun issue(request: HostSsoRequest, identity: AuthorizedAccount): HostSsoCode =
                HostSsoCode(code = "s".repeat(43), expiresAt = null)
        }

        val fakeJpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x01, 0x02)

        LocalStubHttp { req ->
            when {
                req.method == "POST" && req.path == "/sso-ticket" -> HttpRes(
                    bodyBytes = JSONObject()
                        .put("ok", true)
                        .put("identityAssertion", "z".repeat(80))
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/api/v1/feedback/guest" -> HttpRes(
                    extraHeaders = listOf(
                        "Set-Cookie" to "__Host-ylf-support-guest=guest_cookie_1; Path=/; HttpOnly; SameSite=Lax",
                    ),
                    bodyBytes = JSONObject()
                        .put("kind", "guest")
                        .put("csrfToken", "csrf_guest_1")
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/api/v1/session/exchange" -> HttpRes(
                    extraHeaders = listOf(
                        "Set-Cookie" to "__Host-ylf-support-session=sess_cookie_9; Path=/; HttpOnly; SameSite=Lax",
                    ),
                    bodyBytes = JSONObject()
                        .put("ok", true)
                        .put("user", JSONObject().put("userId", "user_m6"))
                        .put("csrfToken", "csrf_user_9")
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/api/v1/private-feedback" -> {
                    assertEquals("csrf_guest_1", req.headers["x-csrf-token"])
                    assertEquals("__Host-ylf-support-guest=guest_cookie_1", req.headers["cookie"])
                    assertNotNull(req.headers["idempotency-key"])
                    val sent = JSONObject(req.body)
                    assertEquals("www", sent.getString("productId"))
                    assertEquals("apps-android-share", sent.getJSONObject("context").getString("source"))
                    assertEquals(1, sent.getJSONArray("screenshots").length())
                    HttpRes(
                        bodyBytes = JSONObject()
                            .put(
                                "receipt",
                                JSONObject()
                                    .put("id", "fb_101")
                                    .put("productId", "www")
                                    .put("ticketId", "tk_101")
                                    .put("ticketUrl", "http://127.0.0.1/tickets/tk_101#access=secret123"),
                            )
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                }
                req.method == "GET" && req.path.startsWith("/api/v1/feedback") -> HttpRes(
                    bodyBytes = JSONObject()
                        .put(
                            "items",
                            JSONArray().put(
                                JSONObject()
                                    .put("id", "board_1")
                                    .put("productId", "cook")
                                    .put("title", "支持深色模式")
                                    .put("publicContent", "希望新增深色模式切换")
                                    .put("publicStatus", "planned")
                                    .put("voteCount", 42)
                                    .put("officialResponse", "即将上线"),
                            ),
                        )
                        .put("nextCursor", "cur_2")
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "GET" && req.path.startsWith("/api/internal/v1/dashboard") -> {
                    assertEquals("__Host-ylf-support-session=sess_cookie_9", req.headers["cookie"])
                    HttpRes(
                        bodyBytes = JSONObject()
                            .put("productId", "www")
                            .put("productIds", JSONArray().put("www").put("cook"))
                            .put("feedback", JSONObject().put("items", JSONArray()).put("nextCursor", JSONObject.NULL))
                            .put(
                                "privateFeedback",
                                JSONObject()
                                    .put(
                                        "items",
                                        JSONArray().put(
                                            JSONObject()
                                                .put("id", "priv_1")
                                                .put("productId", "www")
                                                .put("description", "登录页面提示")
                                                .put("status", "reviewing")
                                                .put("category", "problem")
                                                .put("createdAt", "2026-11-21T10:00:00Z")
                                                .put("ticketId", "tk_101")
                                                .put(
                                                    "context",
                                                    JSONObject()
                                                        .put("source", "apps-android-share")
                                                        .put("version", "1.2.0"),
                                                ),
                                        ),
                                    )
                                    .put("nextCursor", JSONObject.NULL),
                            )
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                }
                req.method == "DELETE" && req.path == "/api/v1/session" -> HttpRes(
                    bodyBytes = """{"ok":true}""".toByteArray(Charsets.UTF_8),
                )
                else -> HttpRes(status = 404)
            }
        }.use { server ->
            val service = SupportCenterService(
                authorization = fakeAuth,
                origin = server.origin,
                exchangeUrl = "${server.origin}/sso-ticket",
            )

            // 1. Guest session & submission with screenshot
            val guest = service.connect(identity = null)
            assertNull(guest.userID)
            val shot = FeedbackScreenshot(data = fakeJpeg, width = 100, height = 100)
            val receipt = service.submit(
                product = "www",
                category = "problem",
                description = "反馈测试内容超过五个字符",
                screenshots = listOf(shot),
                key = UUID.randomUUID().toString(),
                access = guest,
                context = SupportFeedbackSubmission.Context(source = "apps-android-share", version = "1.0"),
            )
            assertEquals("fb_101", receipt.id)
            assertEquals("tk_101", receipt.ticketId)

            // 2. Board pagination
            val boardPage = service.board()
            assertEquals(1, boardPage.items.size)
            assertEquals("已计划", boardPage.items.first().statusTitle)
            assertEquals("cur_2", boardPage.nextCursor)

            // 3. Consent gate & signed-in session + dashboard + disconnect
            try {
                service.connect(identity = identity, consent = false)
                fail("Expected consent required")
            } catch (e: SupportCenterException) {
                assertEquals(SupportCenterError.CONSENT_REQUIRED, e.error)
            }
            promptMode = null
            val userAccess = service.connect(identity = identity, consent = true)
            assertEquals("user_m6", userAccess.userID)
            val dashboard = service.dashboard(product = "www", access = userAccess)
            assertEquals(1, dashboard.privateFeedback.items.size)
            val priv = dashboard.privateFeedback.items.first()
            assertEquals("Android 系统分享 · 1.2.0", priv.sourceSummary)
            assertEquals("处理中", priv.statusTitle)
            service.disconnect(userAccess)
            assertTrue(server.requests.any { it.method == "DELETE" && it.path == "/api/v1/session" })

            // 4. Input validation
            try {
                service.submit(
                    product = "www",
                    category = "problem",
                    description = "短",
                    key = UUID.randomUUID().toString(),
                    access = guest,
                )
                fail("Expected invalid input")
            } catch (e: SupportCenterException) {
                assertEquals(SupportCenterError.INVALID_INPUT, e.error)
            }
        }
    }

    @Test
    fun supportTicketClientGuestTokenAndScreenshotValidation() = runBlocking {
        val jpegBytes = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x11, 0x22, 0x33)
        var returnBadImage = false

        LocalStubHttp { req ->
            when {
                req.method == "POST" && req.path == "/api/v1/tickets/tk_101/access" -> {
                    assertEquals("secret123", JSONObject(req.body).getString("token"))
                    HttpRes(
                        extraHeaders = listOf(
                            "Set-Cookie" to "__Host-ylf-ticket-tk_101=tk_cookie_ok; Path=/; HttpOnly",
                        ),
                        bodyBytes = """{"ticketCsrf":"tk_csrf_1"}""".toByteArray(Charsets.UTF_8),
                    )
                }
                req.method == "GET" && req.path == "/api/v1/tickets/tk_101" -> {
                    assertEquals("__Host-ylf-ticket-tk_101=tk_cookie_ok", req.headers["cookie"])
                    HttpRes(
                        bodyBytes = JSONObject()
                            .put(
                                "ticket",
                                JSONObject()
                                    .put("id", "tk_101")
                                    .put("number", "10042")
                                    .put("title", "截图工单标题")
                                    .put("productId", "www")
                                    .put("status", "in_progress")
                                    .put("createdAt", "2026-11-21T10:00:00Z")
                                    .put("updatedAt", "2026-11-21T10:05:00Z"),
                            )
                            .put(
                                "messages",
                                JSONArray().put(
                                    JSONObject()
                                        .put("id", "msg_1")
                                        .put("content", "收到您的截图，正在核实")
                                        .put("createdAt", "2026-11-21T10:05:00Z")
                                        .put("author", "team"),
                                ),
                            )
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                }
                req.method == "GET" && req.path == "/api/v1/tickets/tk_101/screenshots" -> HttpRes(
                    bodyBytes = JSONObject()
                        .put(
                            "items",
                            JSONArray().put(
                                JSONObject()
                                    .put("id", "shot_1")
                                    .put("mimeType", "image/jpeg")
                                    .put("width", 1080)
                                    .put("height", 1920)
                                    .put("sizeBytes", jpegBytes.size),
                            ),
                        )
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "GET" && req.path == "/api/v1/tickets/tk_101/screenshots/shot_1" -> HttpRes(
                    contentType = "image/jpeg",
                    bodyBytes = if (returnBadImage) byteArrayOf(1, 2, 3, 4, 5, 6, 7) else jpegBytes,
                )
                else -> HttpRes(status = 404)
            }
        }.use { server ->
            val client = SupportTicketClient(origin = server.origin)
            val receipt = SupportFeedbackReceipt(
                id = "fb_101",
                productId = "www",
                ticketId = "tk_101",
                ticketUrl = "${server.origin}/tickets/tk_101#access=secret123",
            )
            assertNotNull(SupportUrlRules.ticketUrl(receipt, origin = server.origin, requiringGuestAccess = true))

            val snapshot = client.load(receipt)
            assertEquals("10042", snapshot.detail.ticket.number)
            assertEquals("处理中", snapshot.detail.ticket.statusTitle)
            assertEquals(1, snapshot.detail.messages.size)
            assertEquals(1, snapshot.screenshots.size)

            val downloaded = client.screenshotBytes(snapshot.screenshots.first(), snapshot)
            assertTrue(downloaded.contentEquals(jpegBytes))

            returnBadImage = true
            try {
                client.screenshotBytes(snapshot.screenshots.first(), snapshot)
                fail("Expected invalid JPEG magic rejection")
            } catch (e: SupportTicketException) {
                assertEquals(SupportTicketError.INVALID_RESPONSE, e.error)
            }

            // Missing fragment access token without cookies fails as EXPIRED
            try {
                client.load(receipt.copy(ticketUrl = "${server.origin}/tickets/tk_101"))
                fail("Expected EXPIRED when no access token")
            } catch (e: SupportTicketException) {
                assertEquals(SupportTicketError.EXPIRED, e.error)
            }
        }
    }

    @Test
    fun sharedFeedbackHistoryAdoptionCapAndAccountReset() {
        val tempDir = Files.createTempDirectory("yunle-share-hist").toFile()
        try {
            val file = File(tempDir, "history.json")
            val store = SharedFeedbackHistoryStore(file)

            // Pre-activation guest share can be adopted once on login
            val initialRec = SharedFeedbackRecord(
                receipt = SupportFeedbackReceipt(
                    id = "fb_0",
                    productId = "www",
                    ticketId = "tk_0",
                    ticketUrl = "https://support.yunle.fun/tickets/tk_0#access=t0",
                ),
                createdAtMillis = 1000L,
            )
            assertTrue(store.save(initialRec))
            store.activate("uid_A")
            assertEquals(1, store.records.value.size)

            // Cap at MAXIMUM_RECORDS = 20
            for (i in 1..25) {
                store.save(
                    SharedFeedbackRecord(
                        receipt = SupportFeedbackReceipt(
                            id = "fb_$i",
                            productId = "cook",
                            ticketId = "tk_$i",
                            ticketUrl = "https://support.yunle.fun/tickets/tk_$i#access=t$i",
                        ),
                        createdAtMillis = 1000L + i,
                    ),
                )
            }
            assertEquals(SharedFeedbackHistoryStore.MAXIMUM_RECORDS, store.records.value.size)
            assertEquals("fb_25", store.records.value.first().id)

            // Switching to another account clears records
            store.activate("uid_B")
            assertTrue(store.records.value.isEmpty())
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun diagnosticRedactionScopeRotationAndUploadValidation() = runBlocking {
        // Redaction tests
        val rawText = "Authorization: Bearer abc.def.ghi token=supersecret eyJhbGciOiJIUzI1NiJ9.payload123.sig123456 user@example.com 13812345678\u0007"
        val redacted = DiagnosticText.redact(rawText)
        assertFalse(redacted.contains("abc.def.ghi"))
        assertFalse(redacted.contains("supersecret"))
        assertFalse(redacted.contains("payload123"))
        assertFalse(redacted.contains("user@example.com"))
        assertFalse(redacted.contains("13812345678"))
        assertTrue(redacted.contains("[REDACTED]"))
        assertTrue(redacted.contains("[email]"))
        assertTrue(redacted.contains("[phone]"))

        // Scope generation A -> B -> A rotation & 500-entry cap
        val tempDir = Files.createTempDirectory("yunle-diag-test").toFile()
        var currentTime = 1_700_000_000_000L
        try {
            val logs = DiagnosticLogStore(File(tempDir, "logs")) { currentTime }
            logs.activateAccount("user_A")
            val genA1 = logs.scopeGeneration
            logs.record(DiagnosticLogLevel.INFO, "step 1 Bearer secret123")
            assertEquals(1, logs.entries.value.size)
            assertFalse(logs.entries.value.first().message.contains("secret123"))

            logs.activateAccount("user_B")
            val genB = logs.scopeGeneration
            assertNotEquals(genA1, genB)
            assertTrue(logs.entries.value.isEmpty())

            logs.activateAccount("user_A")
            val genA2 = logs.scopeGeneration
            assertNotEquals(genA1, genA2)
            assertEquals(1, logs.entries.value.size)

            // Upload service & receipt validation
            val client = DiagnosticClientContext(
                appVersion = "1.0.0",
                buildNumber = "10",
                platform = "android",
                route = "/me/diagnostics",
                timezone = "Asia/Shanghai",
                userAgent = "YunleFun-Android/1.0.0",
            )
            var badCode = false
            LocalStubHttp { req ->
                assertEquals("POST", req.method)
                assertEquals("/api/diagnostics/logs", req.path)
                assertEquals("Bearer tok_diag", req.headers["authorization"])
                val body = JSONObject(req.body)
                assertEquals(1, body.getJSONArray("logs").length())
                HttpRes(
                    bodyBytes = JSONObject()
                        .put("code", 0)
                        .put(
                            "data",
                            JSONObject()
                                .put("uploadId", "up_123")
                                .put("supportCode", if (badCode) "bad" else "ABCD1234EFGH")
                                .put("logCount", 1)
                                .put("expiresAt", currentTime + DiagnosticUploadRules.RETENTION_MS),
                        )
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
            }.use { server ->
                val diagService = DiagnosticService(
                    endpoint = "${server.origin}/api/diagnostics/logs",
                    nowMillis = { currentTime },
                )
                val receipt = diagService.upload(
                    payload = DiagnosticUploadPayload(
                        startTime = currentTime - 60_000L,
                        endTime = currentTime,
                        issueDescription = "上传排查",
                        logs = logs.entries.value,
                        client = client,
                    ),
                    identity = AuthorizedAccount(
                        userID = "user_A",
                        accessToken = "tok_diag",
                    ),
                )
                assertEquals("ABCD1234EFGH", receipt.supportCode)
                assertEquals(1, receipt.logCount)

                // Invalid support code rejected
                badCode = true
                try {
                    diagService.upload(
                        payload = DiagnosticUploadPayload(
                            startTime = currentTime - 60_000L,
                            endTime = currentTime,
                            issueDescription = "校验失败用例",
                            logs = logs.entries.value,
                            client = client,
                        ),
                        identity = AuthorizedAccount(
                            userID = "user_A",
                            accessToken = "tok_diag",
                        ),
                    )
                    fail("Expected invalid supportCode rejection")
                } catch (e: DiagnosticException) {
                    assertEquals(DiagnosticError.INVALID_RESPONSE, e.error)
                }

                // >24h window rejected before network call
                try {
                    DiagnosticUploadRules.normalize(
                        DiagnosticUploadPayload(
                            startTime = currentTime - 90_000_000L,
                            endTime = currentTime,
                            issueDescription = "超出时间范围",
                            logs = listOf(DiagnosticLogEntry(DiagnosticLogLevel.INFO, "ok", currentTime)),
                            client = client,
                        ),
                        nowMillis = currentTime,
                    )
                    fail("Expected >24h INVALID_RANGE")
                } catch (e: DiagnosticException) {
                    assertEquals(DiagnosticError.INVALID_RANGE, e.error)
                }
            }
        } finally {
            tempDir.deleteRecursively()
        }
    }
}
