package `fun`.yunle.apps

import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.assistant.AssistantAppCard
import `fun`.yunle.apps.assistant.AssistantError
import `fun`.yunle.apps.assistant.AssistantEvent
import `fun`.yunle.apps.assistant.AssistantException
import `fun`.yunle.apps.assistant.AssistantHistoryStore
import `fun`.yunle.apps.assistant.AssistantMessage
import `fun`.yunle.apps.assistant.AssistantRunAccumulator
import `fun`.yunle.apps.assistant.AssistantRunInput
import `fun`.yunle.apps.assistant.AssistantSSEDecoder
import `fun`.yunle.apps.assistant.AssistantService
import `fun`.yunle.apps.publishing.ApplicationAudience
import `fun`.yunle.apps.publishing.ApplicationDraft
import `fun`.yunle.apps.publishing.ApplicationDraftVault
import `fun`.yunle.apps.publishing.ApplicationIconNormalizer
import `fun`.yunle.apps.publishing.ApplicationIconRole
import `fun`.yunle.apps.publishing.ApplicationReviewStatus
import `fun`.yunle.apps.publishing.PublishingError
import `fun`.yunle.apps.publishing.PublishingException
import `fun`.yunle.apps.publishing.PublishingService
import `fun`.yunle.apps.publishing.SavedApplicationDraft
import `fun`.yunle.apps.wallet.PurchaseAccountToken
import `fun`.yunle.apps.wallet.PurchaseOwnershipJournal
import `fun`.yunle.apps.wallet.WalletError
import `fun`.yunle.apps.wallet.WalletException
import `fun`.yunle.apps.wallet.WalletService
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors

class M5AssistantWalletPublishingTest {
    private data class RecordedHttp(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
        val body: String,
    )

    private data class StubHttp(
        val status: Int = 200,
        val contentType: String = "application/json; charset=utf-8",
        val bodyBytes: ByteArray = "{}".toByteArray(Charsets.UTF_8),
    )

    private class LocalStubServer(
        private val handler: (RecordedHttp) -> StubHttp,
    ) : Closeable {
        private val server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        private val pool = Executors.newCachedThreadPool()
        val requests = ConcurrentLinkedQueue<RecordedHttp>()
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
                            val lines = buf.toByteArray().toString(Charsets.UTF_8).split("\r\n").filter { it.isNotEmpty() }
                            val parts = lines.first().split(' ')
                            val headers = linkedMapOf<String, String>()
                            var contentLength = 0
                            for (line in lines.drop(1)) {
                                val idx = line.indexOf(':')
                                if (idx <= 0) continue
                                val k = line.substring(0, idx).trim().lowercase()
                                val v = line.substring(idx + 1).trim()
                                headers[k] = v
                                if (k == "content-length") contentLength = v.toIntOrNull() ?: 0
                            }
                            val body = ByteArray(contentLength)
                            var offset = 0
                            while (offset < contentLength) {
                                val read = input.read(body, offset, contentLength - offset)
                                if (read == -1) break
                                offset += read
                            }
                            val req = RecordedHttp(parts[0], parts[1], headers, body.toString(Charsets.UTF_8))
                            requests.add(req)
                            val res = handler(req)
                            val head = buildString {
                                append("HTTP/1.1 ${res.status} OK\r\n")
                                append("Content-Type: ${res.contentType}\r\n")
                                append("Content-Length: ${res.bodyBytes.size}\r\n")
                                append("Connection: close\r\n\r\n")
                            }.toByteArray(Charsets.US_ASCII)
                            s.getOutputStream().apply {
                                write(head)
                                write(res.bodyBytes)
                                flush()
                            }
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
    fun assistantSseDecoderAccumulatorCardResolutionAndHistory() = runBlocking {
        // BOM + CRLF + LF framing
        val rawStream = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) +
            ("data: {\"type\":\"RUN_STARTED\",\"threadId\":\"t1\",\"runId\":\"r1\"}\r\n\r\n" +
                "data: {\"type\":\"TEXT_MESSAGE_START\",\"messageId\":\"m1\"}\n\n" +
                "data: {\"type\":\"TEXT_MESSAGE_CONTENT\",\"messageId\":\"m1\",\"delta\":\"推荐\"}\r\r" +
                "data: {\"type\":\"TOOL_CALL_START\",\"toolCallId\":\"tc1\",\"toolCallName\":\"search_apps\"}\n\n" +
                "data: {\"type\":\"TOOL_CALL_RESULT\",\"toolCallId\":\"tc1\",\"content\":{\"apps\":[{\"id\":\"app_cook\",\"slug\":\"cook\",\"name\":\"今天来做菜\",\"reason\":\"精选\"}]}}\n\n" +
                "data: {\"type\":\"TEXT_MESSAGE_END\",\"messageId\":\"m1\"}\n\n" +
                "data: {\"type\":\"RUN_FINISHED\",\"threadId\":\"t1\",\"runId\":\"r1\"}\n\n")
                .toByteArray(Charsets.UTF_8)

        val decoder = AssistantSSEDecoder()
        val frames = mutableListOf<ByteArray>()
        for (b in rawStream) {
            decoder.append(b)?.let(frames::add)
        }
        assertEquals(7, frames.size)

        val acc = AssistantRunAccumulator(threadId = "t1", runId = "r1")
        frames.map(AssistantEvent::parse).forEach(acc::apply)
        assertTrue(acc.finished)
        assertEquals("推荐", acc.content)
        assertEquals(1, acc.cards.size)

        val publicApp = CatalogApp(
            id = "app_cook",
            key = "cook",
            name = "今天来做菜",
            description = "",
            author = "云乐坊",
            ownerLogin = "yunle",
            category = "生活",
            emoji = "🍳",
            launchUrl = "https://cook.yunle.fun/",
            logo = null,
            themeColor = null,
            trustedHosts = emptyList(),
            immersive = false,
            audience = "public",
        )
        val scopedWorkshopApp = publicApp.copy(id = "app_ws", key = "ws", accessWorkshopId = "2345AB")
        assertNotNull(acc.cards.first().resolve(listOf(publicApp, scopedWorkshopApp)))
        assertNull(AssistantAppCard("app_ws", "ws", "工坊", null).resolve(listOf(publicApp, scopedWorkshopApp)))

        // Live HTTP stream + 403 MEMBERSHIP_REQUIRED + History isolation
        val identity = AuthorizedAccount("u_ai", "tok_ai")
        var blockMembership = false
        LocalStubServer { req ->
            when {
                req.path.endsWith("/send-message") && blockMembership -> StubHttp(
                    status = 403,
                    bodyBytes = """{"code":"MEMBERSHIP_REQUIRED"}""".toByteArray(Charsets.UTF_8),
                )
                req.path.endsWith("/send-message") -> StubHttp(
                    contentType = "text/event-stream; charset=utf-8",
                    bodyBytes = ("data: {\"type\":\"RUN_STARTED\",\"threadId\":\"t2\",\"runId\":\"r2\"}\n\n" +
                        "data: {\"type\":\"RUN_FINISHED\",\"threadId\":\"t2\",\"runId\":\"r2\"}\n\n")
                        .toByteArray(Charsets.UTF_8),
                )
                else -> StubHttp(status = 404)
            }
        }.use { server ->
            val service = AssistantService(gatewayOrigin = server.origin, appsOrigin = server.origin)
            val input = AssistantRunInput(
                threadId = "t2",
                runId = "r2",
                messages = listOf(AssistantRunInput.InputMessage("u1", AssistantMessage.Role.USER, "hello")),
            )
            val events = service.streamEvents(input, identity).toList()
            assertEquals(listOf("RUN_STARTED", "RUN_FINISHED"), events.map { it.type })

            blockMembership = true
            try {
                service.streamEvents(input, identity).toList()
                fail("Expected MEMBERSHIP_REQUIRED")
            } catch (e: AssistantException) {
                assertEquals(AssistantError.MEMBERSHIP_REQUIRED, e.error)
            }
        }

        val dir = Files.createTempDirectory("yunle-ai-hist").toFile()
        try {
            val store = AssistantHistoryStore(dir)
            store.activate("u_1")
            store.save(listOf(AssistantMessage("m1", AssistantMessage.Role.USER, "hi")), "u_1")
            assertEquals(1, store.messages.value.size)
            store.activate("u_2")
            assertTrue(store.messages.value.isEmpty())
            store.activate("u_1")
            assertEquals("hi", store.messages.value.single().content)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun walletServiceAndOwnershipJournalVerification() = runBlocking {
        val identity = AuthorizedAccount("uid_wallet", "tok_wallet")
        assertEquals(PurchaseAccountToken.forUser("uid_wallet"), PurchaseAccountToken.forUser("uid_wallet"))

        LocalStubServer { req ->
            val body = JSONObject(req.body)
            when (req.path) {
                "/v1/functions/account-api" -> when (body.optString("action")) {
                    "getAccount" -> StubHttp(
                        bodyBytes = JSONObject()
                            .put("coin", 520L)
                            .put("membership", JSONObject().put("isActive", true).put("level", "basic").put("expireAt", 1_900_000_000_000L))
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                    "listTransactions" -> StubHttp(
                        bodyBytes = JSONObject()
                            .put(
                                "items",
                                JSONArray().put(
                                    JSONObject()
                                        .put("_id", "tx_1")
                                        .put("userId", "uid_wallet")
                                        .put("type", "recharge")
                                        .put("amount", 100L)
                                        .put("balanceAfter", 520L)
                                        .put("createdAt", 1_700_000_000_000L),
                                ),
                            )
                            .put("nextSkip", JSONObject.NULL)
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                    else -> StubHttp(status = 400)
                }
                "/v1/functions/wxpay-order" -> StubHttp(
                    bodyBytes = JSONObject().put("reconciled", 2).put("paid", 1).put("regranted", 1).toString().toByteArray(Charsets.UTF_8),
                )
                "/v1/functions/iap-order" -> StubHttp(
                    bodyBytes = JSONObject().put("granted", true).put("alreadyProcessed", false).put("outTradeNo", "iap_123456").toString().toByteArray(Charsets.UTF_8),
                )
                else -> StubHttp(status = 404)
            }
        }.use { server ->
            val wallet = WalletService(server.origin)
            val snap = wallet.account(identity)
            assertEquals(520L, snap.coin)
            assertTrue(snap.membership.isActive)

            val page = wallet.transactions(0, 20, identity)
            assertEquals(1, page.items.size)
            assertEquals("充值", page.items.single().title)

            val rec = wallet.reconcile(identity)
            assertEquals(1, rec.paid)

            val receipt = wallet.verify("123456", identity)
            assertEquals("iap_123456", receipt.outTradeNo)
        }

        val dir = Files.createTempDirectory("yunle-wallet-journal").toFile()
        try {
            val journal = PurchaseOwnershipJournal(File(dir, "journal.json"))
            journal.reserve("ord_1", "uid_a")
            journal.bind("ord_1", "uid_a")
            assertEquals("uid_a", journal.owner("ord_1"))
            try {
                journal.reserve("ord_1", "uid_b", allowUnconfirmedReassignment = true)
                fail("Expected confirmed binding fork forbidden")
            } catch (e: WalletException) {
                assertEquals(WalletError.FORBIDDEN, e.error)
            }
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun publishingServiceDraftValidationVaultAndPngNormalization() = runBlocking {
        val invalidDraft = ApplicationDraft(
            name = "外站作品",
            slug = "ext-app",
            websiteUrl = "https://example.com/",
            privacyPolicyUrl = "https://example.com/privacy",
            supportUrl = "https://example.com/support",
            audience = ApplicationAudience.PUBLIC,
        )
        assertFalse(invalidDraft.isValid)
        assertTrue(invalidDraft.copy(audience = ApplicationAudience.OWNER).isValid)

        val validDraft = ApplicationDraft(
            name = "云笔记",
            slug = "cloud-note",
            description = "轻量笔记",
            websiteUrl = "https://note.yunle.fun/",
            privacyPolicyUrl = "https://note.yunle.fun/privacy",
            supportUrl = "https://note.yunle.fun/support",
            audience = ApplicationAudience.PUBLIC,
        )
        assertTrue(validDraft.isValid)

        val writeVer = "a".repeat(64)
        val validPng = byteArrayOf(
            137.toByte(), 80, 78, 71, 13, 10, 26, 10,
            0, 0, 0, 13, 73, 72, 68, 82,
            0, 0, 4, 0, 0, 0, 4, 0,
            8, 6, 0, 0, 0,
        )
        assertTrue(ApplicationIconNormalizer.isNormalized1024Png(validPng))
        assertFalse(ApplicationIconNormalizer.isNormalized1024Png(byteArrayOf(1, 2, 3)))

        val identity = AuthorizedAccount("uid_pub", "tok_pub")
        var conflictSave = false
        val savedAppJson = JSONObject()
            .put("_id", "app_pub_1")
            .put("name", "云笔记")
            .put("slug", "cloud-note")
            .put("description", "轻量笔记")
            .put("websiteUrl", "https://note.yunle.fun/")
            .put("privacyPolicyUrl", "https://note.yunle.fun/privacy")
            .put("supportUrl", "https://note.yunle.fun/support")
            .put("audience", "public")
            .put("accessMode", "public")
            .put("isPublic", true)
            .put("status", "approved")
            .put("publicationStatus", "published")
            .put("ownerUid", "uid_pub")
            .put("writeVersion", writeVer)
            .put("currentRevisionId", "sub_1")
            .put("publishedSubmissionId", "sub_1")
            .put("updatedAt", 1_700_000_000_000L)
            .put(
                "latestSubmission",
                JSONObject()
                    .put("_id", "sub_1")
                    .put("appId", "app_pub_1")
                    .put("submitterUid", "uid_pub")
                    .put("revision", 1)
                    .put("reviewStatus", "draft")
                    .put("snapshot", validDraft.toLocalJson()),
            )

        LocalStubServer { req ->
            when {
                req.method == "GET" && req.path == "/api/apps/access" -> StubHttp(
                    bodyBytes = """{"writePreconditionVersion":1,"canSubmitFirstParty":true,"thirdPartyEnabled":false,"thirdPartyMessage":""}""".toByteArray(Charsets.UTF_8),
                )
                req.method == "GET" && req.path == "/api/apps/mine" -> StubHttp(
                    bodyBytes = JSONObject().put("items", JSONArray().put(savedAppJson)).toString().toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/api/apps/submissions" -> StubHttp(
                    bodyBytes = JSONObject()
                        .put("app", savedAppJson)
                        .put("submission", savedAppJson.getJSONObject("latestSubmission"))
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/api/apps/app_pub_1/submissions" -> if (conflictSave) {
                    StubHttp(status = 412)
                } else {
                    StubHttp(
                        bodyBytes = JSONObject()
                            .put("app", savedAppJson)
                            .put("submission", savedAppJson.getJSONObject("latestSubmission"))
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                }
                req.method == "POST" && req.path == "/api/apps/app_pub_1/public-market" -> StubHttp(
                    bodyBytes = """{"appId":"app_pub_1","submissionId":"sub_1","reviewStatus":"pending"}""".toByteArray(Charsets.UTF_8),
                )
                req.method == "DELETE" && req.path == "/api/apps/app_pub_1" -> StubHttp(
                    bodyBytes = """{"success":true}""".toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/api/apps/icon-assets" -> StubHttp(
                    bodyBytes = JSONObject()
                        .put("fileID", "cloud://env-1/app-icons/0123456789abcdef/11111111-2222-3333-4444-555555555555.png")
                        .put("role", "app-icon")
                        .put("width", 1024)
                        .put("height", 1024)
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                else -> StubHttp(status = 404)
            }
        }.use { server ->
            val service = PublishingService(server.origin)
            assertTrue(service.access(identity).canSubmitFirstParty)
            val created = service.save(null, validDraft, null, identity)
            assertEquals("app_pub_1", created.id)
            assertEquals(1, service.applications(identity).size)

            val sub = service.submit("app_pub_1", true, "cloud-note", writeVer, identity)
            assertEquals(ApplicationReviewStatus.PENDING, sub.reviewStatus)

            val uploaded = service.upload(validPng, ApplicationIconRole.APP_ICON, identity)
            assertTrue(uploaded.startsWith("cloud://"))

            conflictSave = true
            try {
                service.save("app_pub_1", validDraft, writeVer, identity)
                fail("Expected 412 CONFLICT")
            } catch (e: PublishingException) {
                assertEquals(PublishingError.CONFLICT, e.error)
            }

            service.delist("app_pub_1", writeVer, identity)
        }

        val dir = Files.createTempDirectory("yunle-draft-vault").toFile()
        try {
            val vault = ApplicationDraftVault(dir)
            vault.save(SavedApplicationDraft(validDraft, "sub_1", 100L, writeVer), "uid_pub", "app_pub_1")
            val loaded = vault.load("uid_pub", "app_pub_1")!!
            assertEquals("cloud-note", loaded.draft.slug)
            vault.remove("uid_pub", "app_pub_1")
            assertNull(vault.load("uid_pub", "app_pub_1"))

            vault.fileFor("uid_pub", "app_pub_1").apply {
                parentFile?.mkdirs()
                writeText("{corrupt", Charsets.UTF_8)
            }
            try {
                vault.save(SavedApplicationDraft(validDraft), "uid_pub", "app_pub_1")
                fail("Expected corrupt draft protection")
            } catch (e: PublishingException) {
                assertEquals(PublishingError.STORAGE, e.error)
            }
        } finally {
            dir.deleteRecursively()
        }
    }
}
