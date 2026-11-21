package `fun`.yunle.apps

import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.catalog.ApplicationAcquisitionError
import `fun`.yunle.apps.catalog.ApplicationAcquisitionException
import `fun`.yunle.apps.catalog.ApplicationAcquisitionService
import `fun`.yunle.apps.catalog.ApplicationAcquisitionState
import `fun`.yunle.apps.catalog.DeveloperProfileError
import `fun`.yunle.apps.catalog.DeveloperProfileException
import `fun`.yunle.apps.catalog.DeveloperProfileService
import `fun`.yunle.apps.catalog.PersonalMarketLaunchAuthorization
import `fun`.yunle.apps.catalog.WorkshopDiscoveryPayload
import `fun`.yunle.apps.catalog.WorkshopDiscoverySelection
import `fun`.yunle.apps.catalog.WorkshopDiscoveryService
import `fun`.yunle.apps.community.CommunityError
import `fun`.yunle.apps.community.CommunityException
import `fun`.yunle.apps.community.CommunityService
import `fun`.yunle.apps.community.CommunityValidation
import `fun`.yunle.apps.community.ReportDraft
import `fun`.yunle.apps.community.ReportReason
import `fun`.yunle.apps.community.ReportTarget
import `fun`.yunle.apps.community.ReportTargetType
import `fun`.yunle.apps.community.ReviewDraft
import `fun`.yunle.apps.community.ReviewStatus
import `fun`.yunle.apps.workshop.WorkshopDecision
import `fun`.yunle.apps.workshop.WorkshopDraft
import `fun`.yunle.apps.workshop.WorkshopError
import `fun`.yunle.apps.workshop.WorkshopException
import `fun`.yunle.apps.workshop.WorkshopJoinPolicy
import `fun`.yunle.apps.workshop.WorkshopLaunchAuthorization
import `fun`.yunle.apps.workshop.WorkshopMembershipStatus
import `fun`.yunle.apps.workshop.WorkshopService
import `fun`.yunle.apps.workshop.WorkshopStatus
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.BufferedInputStream
import java.io.Closeable
import java.net.InetAddress
import java.net.ServerSocket
import java.time.Instant
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors

class WorkshopCommunityAcquisitionTest {
    private data class RecordedRequest(
        val method: String,
        val path: String,
        val authorization: String?,
        val body: String,
    )

    private data class StubResponse(
        val status: Int = 200,
        val jsonBody: String = "{}",
    )

    private class LocalStubServer(
        private val handler: (RecordedRequest) -> StubResponse,
    ) : Closeable {
        private val server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        private val pool = Executors.newCachedThreadPool()
        val requests = ConcurrentLinkedQueue<RecordedRequest>()
        val origin: String get() = "http://127.0.0.1:${server.localPort}"

        init {
            pool.execute {
                while (!server.isClosed) {
                    val socket = runCatching { server.accept() }.getOrNull() ?: break
                    pool.execute {
                        socket.use { s ->
                            val input = BufferedInputStream(s.getInputStream())
                            val headerBytes = ArrayList<Byte>()
                            while (true) {
                                val b = input.read()
                                if (b == -1) return@use
                                headerBytes.add(b.toByte())
                                val n = headerBytes.size
                                if (n >= 4 &&
                                    headerBytes[n - 4] == '\r'.code.toByte() &&
                                    headerBytes[n - 3] == '\n'.code.toByte() &&
                                    headerBytes[n - 2] == '\r'.code.toByte() &&
                                    headerBytes[n - 1] == '\n'.code.toByte()
                                ) {
                                    break
                                }
                            }
                            val headerText = headerBytes.toByteArray().toString(Charsets.UTF_8)
                            val lines = headerText.split("\r\n").filter { it.isNotEmpty() }
                            val parts = lines.first().split(' ')
                            val method = parts[0]
                            val path = parts[1]
                            var contentLength = 0
                            var auth: String? = null
                            for (line in lines.drop(1)) {
                                val idx = line.indexOf(':')
                                if (idx <= 0) continue
                                val k = line.substring(0, idx).trim().lowercase()
                                val v = line.substring(idx + 1).trim()
                                if (k == "content-length") contentLength = v.toIntOrNull() ?: 0
                                if (k == "authorization") auth = v
                            }
                            val bodyBytes = ByteArray(contentLength)
                            var offset = 0
                            while (offset < contentLength) {
                                val read = input.read(bodyBytes, offset, contentLength - offset)
                                if (read == -1) break
                                offset += read
                            }
                            val req = RecordedRequest(
                                method = method,
                                path = path,
                                authorization = auth,
                                body = bodyBytes.toString(Charsets.UTF_8),
                            )
                            requests.add(req)
                            val res = handler(req)
                            val payload = res.jsonBody.toByteArray(Charsets.UTF_8)
                            val headers = buildString {
                                append("HTTP/1.1 ${res.status} OK\r\n")
                                append("Content-Type: application/json; charset=utf-8\r\n")
                                append("Content-Length: ${payload.size}\r\n")
                                append("Connection: close\r\n\r\n")
                            }.toByteArray(Charsets.US_ASCII)
                            s.getOutputStream().apply {
                                write(headers)
                                write(payload)
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

    private fun workshopJson(
        id: String = "2345AB",
        ownerUid: String = "owner_1",
        joinPolicy: String = "approval",
        status: String = "active",
    ) = JSONObject()
        .put("_id", id)
        .put("ownerUid", ownerUid)
        .put("name", "云端工作台")
        .put("description", "测试简介")
        .put("joinPolicy", joinPolicy)
        .put("status", status)
        .put("createdAt", 1_700_000_000_000L)
        .put("updatedAt", 1_700_000_100_000L)

    private fun membershipJson(
        workshopId: String = "2345AB",
        uid: String = "guest_1",
        status: String = "pending",
    ) = JSONObject()
        .put("workshopId", workshopId)
        .put("userUid", uid)
        .put("userName", "访客甲")
        .put("status", status)
        .put("requestedAt", 1_700_000_050_000L)
        .put("joinedAt", if (status == "active") 1_700_000_060_000L else JSONObject.NULL)
        .put("updatedAt", 1_700_000_100_000L)

    private fun scopedAppJson(
        id: String = "ws_app_1",
        audience: String = "workshop",
        accessMode: String = "invite_only",
        requiresMembership: Boolean = false,
        coinCost: Int = 0,
    ) = JSONObject()
        .put("_id", id)
        .put("name", "精选应用")
        .put("audience", audience)
        .put("isPublic", audience == "public")
        .put("status", "approved")
        .put("publicationStatus", "published")
        .put("accessMode", accessMode)
        .put("requiresMembership", requiresMembership)
        .put("coinCost", coinCost)
        .put("websiteUrl", "https://tool.yunle.fun/")
        .put("ownerLogin", "alice")
        .put("trustedHosts", JSONArray().put("tool.yunle.fun"))

    @Test
    fun workshopCrudJoinDecideAndLaunchAuthorization() = runBlocking {
        val owner = AuthorizedAccount("owner_1", "tok_owner")
        val guest = AuthorizedAccount("guest_1", "tok_guest")
        LocalStubServer { req ->
            when {
                req.method == "GET" && req.path == "/api/workshops/mine" -> StubResponse(
                    jsonBody = JSONObject().put(
                        "management",
                        JSONObject()
                            .put("workshop", workshopJson())
                            .put("pending", JSONArray().put(membershipJson()))
                            .put("guests", JSONArray())
                            .put("blocked", JSONArray()),
                    ).toString(),
                )
                req.method == "POST" && req.path == "/api/workshops" -> StubResponse(
                    jsonBody = JSONObject().put("workshop", workshopJson()).toString(),
                )
                req.method == "POST" && req.path == "/api/workshops/2345AB/join" -> StubResponse(
                    jsonBody = JSONObject().put("status", "pending").put("joined", false).toString(),
                )
                req.method == "POST" && req.path == "/api/workshops/2345AB/members/guest_1" -> StubResponse(
                    jsonBody = JSONObject().put("membership", membershipJson(status = "active")).toString(),
                )
                req.method == "POST" && req.path == "/api/workshops/2345AB/leave" -> StubResponse(
                    jsonBody = JSONObject().put("membership", membershipJson(status = "left")).toString(),
                )
                req.method == "GET" && req.path == "/api/workshops/2345AB" -> StubResponse(
                    jsonBody = JSONObject()
                        .put("surface", "workshop")
                        .put("access", "active")
                        .put("workshop", workshopJson())
                        .put("apps", JSONArray().put(scopedAppJson()))
                        .toString(),
                )
                else -> StubResponse(status = 404)
            }
        }.use { server ->
            val service = WorkshopService(server.origin)
            val created = service.create(WorkshopDraft(name = "云端工作台", description = "测试"), owner)
            assertEquals("2345AB", created.id)

            val mgmt = service.mine(owner)!!
            assertEquals(1, mgmt.pending.size)

            val joinRes = service.join("2345AB", guest)
            assertEquals(WorkshopMembershipStatus.PENDING, joinRes.status)

            val approved = service.decide("2345AB", mgmt.pending.first(), WorkshopDecision.APPROVE, owner)
            assertEquals(WorkshopMembershipStatus.ACTIVE, approved.status)

            val page = service.page("2345ab", guest)
            assertTrue(page.permitsApps)
            assertNotNull(page.apps.first().launchUrl)

            val authorized = WorkshopLaunchAuthorization.resolve(page.apps.first(), guest, service)
            assertEquals("https://tool.yunle.fun/", authorized.launchUrl)

            val left = service.leave("2345AB", guest)
            assertEquals(WorkshopMembershipStatus.LEFT, left.status)
        }
    }

    @Test
    fun communityUsesAppKeyNotSlugAndValidatesSummaryAndReports() = runBlocking {
        val identity = AuthorizedAccount("u1", "tok_1")
        val sampleApp = CatalogApp(
            id = "app_record_id",
            key = "market-short",
            slug = "workshop-local-slug",
            name = "示例应用",
            description = "",
            author = "作者",
            ownerLogin = "alice",
            category = "工具",
            emoji = "🧰",
            launchUrl = "https://tool.yunle.fun/",
            logo = null,
            themeColor = null,
            trustedHosts = emptyList(),
            immersive = false,
        )
        assertEquals("market-short", CommunityValidation.appKeyFor(sampleApp))

        LocalStubServer { req ->
            when {
                req.method == "GET" && req.path == "/api/reviews?appKey=market-short" -> StubResponse(
                    jsonBody = JSONObject()
                        .put("code", 0)
                        .put(
                            "data",
                            JSONObject()
                                .put(
                                    "summary",
                                    JSONObject()
                                        .put("average", 4.5)
                                        .put("count", 2)
                                        .put(
                                            "distribution",
                                            JSONObject()
                                                .put("1", 0)
                                                .put("2", 0)
                                                .put("3", 0)
                                                .put("4", 1)
                                                .put("5", 1),
                                        ),
                                )
                                .put(
                                    "reviews",
                                    JSONArray().put(
                                        JSONObject()
                                            .put("_id", "rev_1")
                                            .put("appKey", "market-short")
                                            .put("authorName", "Tester")
                                            .put("rating", 5)
                                            .put("content", "非常好用")
                                            .put("createdAt", 1_700_000_000_000L)
                                            .put("updatedAt", 1_700_000_000_000L)
                                            .put("publishedAt", 1_700_000_000_000L),
                                    ),
                                )
                                .put("myReview", JSONObject.NULL),
                        )
                        .toString(),
                )
                req.method == "POST" && req.path == "/api/reviews" -> StubResponse(
                    jsonBody = JSONObject()
                        .put("code", 0)
                        .put(
                            "data",
                            JSONObject()
                                .put("status", "published")
                                .put("message", "评论已发布")
                                .put(
                                    "review",
                                    JSONObject()
                                        .put("_id", "rev_2")
                                        .put("appKey", "market-short")
                                        .put("authorName", "我")
                                        .put("rating", 4)
                                        .put("content", "稳定流畅")
                                        .put("status", "published")
                                        .put("createdAt", 1_700_000_010_000L)
                                        .put("updatedAt", 1_700_000_010_000L)
                                        .put("publishedAt", 1_700_000_010_000L),
                                ),
                        )
                        .toString(),
                )
                req.method == "DELETE" && req.path == "/api/reviews/rev_2" -> StubResponse(
                    jsonBody = JSONObject().put("code", 0).toString(),
                )
                req.method == "POST" && req.path == "/api/reports" -> StubResponse(
                    status = 409,
                    jsonBody = JSONObject().put("message", "你已举报过该内容").toString(),
                )
                req.method == "GET" && req.path == "/api/reports" -> StubResponse(
                    jsonBody = JSONObject()
                        .put("code", 0)
                        .put(
                            "data",
                            JSONObject().put(
                                "reports",
                                JSONArray().put(
                                    JSONObject()
                                        .put("_id", "rep_1")
                                        .put("targetType", "app")
                                        .put("targetId", "market-short")
                                        .put("appKey", "market-short")
                                        .put("appName", "示例应用")
                                        .put("reason", "spam")
                                        .put("status", "open")
                                        .put("createdAt", 1_700_000_020_000L),
                                ),
                            ),
                        )
                        .toString(),
                )
                else -> StubResponse(status = 404)
            }
        }.use { server ->
            val service = CommunityService(server.origin)
            val list = service.listReviews("market-short", null)
            assertEquals(4.5, list.summary.average, 0.0001)
            assertEquals(1, list.reviews.size)

            val sub = service.submitReview("market-short", ReviewDraft(rating = 4, content = "稳定流畅"), identity)
            assertEquals(ReviewStatus.PUBLISHED, sub.status)
            assertEquals("rev_2", sub.review.id)

            service.deleteReview("rev_2", identity)

            val reports = service.myReports(identity)
            assertEquals(1, reports.size)
            assertEquals("示例应用", reports.first().appName)

            try {
                service.submitReport(
                    ReportTarget(ReportTargetType.APP, "market-short", "示例应用", "market-short"),
                    ReportDraft(reason = ReportReason.SPAM, detail = "测试"),
                    identity,
                )
                fail("Expected 409 Conflict")
            } catch (e: CommunityException) {
                assertEquals(CommunityError.CONFLICT, e.error)
                assertEquals("你已举报过该内容", e.message)
            }
        }
    }

    @Test
    fun developerProfileAcquisitionAndDiscoveryValidation() = runBlocking {
        val identity = AuthorizedAccount("u_buyer", "tok_buyer")
        var rejectScopedItem = false
        var acquisitionScenario = "check_purchase"
        val nowMillis = Instant.parse("2026-11-18T08:00:00Z").toEpochMilli() // Wed GMT+8 -> Mon 2026-11-16 00:00+08:00
        val weekStart = WorkshopDiscoverySelection.gmtPlus8MondayStartMillis(nowMillis)
        assertEquals(Instant.parse("2026-11-15T16:00:00Z").toEpochMilli(), weekStart)

        LocalStubServer { req ->
            when {
                req.method == "GET" && req.path == "/api/markets/personal/alice" -> {
                    val item = if (rejectScopedItem) {
                        scopedAppJson(id = "bad_scoped", audience = "workshop")
                    } else {
                        scopedAppJson(id = "pub_free", audience = "public", accessMode = "public")
                    }
                    StubResponse(
                        jsonBody = JSONObject()
                            .put("ownerLogin", "alice")
                            .put("items", JSONArray().put(item))
                            .toString(),
                    )
                }
                req.method == "POST" && req.path == "/api/apps/acquisition" -> when (acquisitionScenario) {
                    "check_purchase" -> StubResponse(
                        jsonBody = JSONObject()
                            .put("userId", "u_buyer")
                            .put("application", scopedAppJson(id = "paid_1", audience = "public", accessMode = "login_required", coinCost = 30))
                            .put("state", "purchase_required")
                            .put("reason", "purchase")
                            .put("coinCost", 30)
                            .put("balance", 100)
                            .toString(),
                    )
                    "purchase_ok" -> StubResponse(
                        jsonBody = JSONObject()
                            .put("userId", "u_buyer")
                            .put("application", scopedAppJson(id = "paid_1", audience = "public", accessMode = "login_required", coinCost = 30))
                            .put("state", "allowed")
                            .put("reason", "purchased")
                            .put("coinCost", 30)
                            .put("balance", 70)
                            .toString(),
                    )
                    else -> StubResponse(
                        status = 409,
                        jsonBody = JSONObject()
                            .put("message", "应用价格已变化")
                            .put("data", JSONObject().put("code", "APP_PRICE_CHANGED"))
                            .toString(),
                    )
                }
                req.method == "GET" && req.path == "/api/catalog/discovery" -> StubResponse(
                    jsonBody = JSONObject()
                        .put("schemaVersion", 1)
                        .put("generatedAt", nowMillis)
                        .put(
                            "featured",
                            JSONArray().put(
                                JSONObject()
                                    .put("appId", "pub_free")
                                    .put("title", "今日推荐")
                                    .put("startsAt", nowMillis - 10_000L)
                                    .put("expiresAt", nowMillis + 60_000L),
                            ),
                        )
                        .put(
                            "weeklyChart",
                            JSONObject()
                                .put("weekStart", weekStart)
                                .put(
                                    "items",
                                    JSONArray().put(
                                        JSONObject().put("appId", "pub_free").put("rank", 1),
                                    ),
                                ),
                        )
                        .toString(),
                )
                else -> StubResponse(status = 404)
            }
        }.use { server ->
            val devService = DeveloperProfileService(server.origin)
            val profile = devService.profile("alice")
            assertEquals("alice", profile.ownerLogin)
            assertEquals(1, profile.items.size)
            assertEquals("alice", profile.items.first().personalMarketOwnerLogin)
            assertTrue(profile.items.first().trustedHosts.isEmpty())

            val resolved = PersonalMarketLaunchAuthorization.resolve(profile.items.first(), devService)
            assertEquals("https://tool.yunle.fun/", resolved.launchUrl)

            rejectScopedItem = true
            try {
                devService.profile("alice")
                fail("Expected INVALID_RESPONSE for workshop-scoped item")
            } catch (e: DeveloperProfileException) {
                assertEquals(DeveloperProfileError.INVALID_RESPONSE, e.error)
            }

            val acqService = ApplicationAcquisitionService(server.origin)
            val checkQuote = acqService.check("paid_1", identity)
            assertEquals(ApplicationAcquisitionState.PURCHASE_REQUIRED, checkQuote.state)
            assertEquals(30, checkQuote.coinCost)
            assertNull(checkQuote.application.launchUrl)

            acquisitionScenario = "purchase_ok"
            val purchasedQuote = acqService.purchase("paid_1", 30, identity)
            assertEquals(ApplicationAcquisitionState.ALLOWED, purchasedQuote.state)
            assertEquals(70, purchasedQuote.balance)
            assertEquals("https://tool.yunle.fun/", purchasedQuote.application.launchUrl)

            acquisitionScenario = "price_changed"
            try {
                acqService.purchase("paid_1", 30, identity)
                fail("Expected PRICE_CHANGED")
            } catch (e: ApplicationAcquisitionException) {
                assertEquals(ApplicationAcquisitionError.PRICE_CHANGED, e.error)
            }

            val discoveryService = WorkshopDiscoveryService(server.origin)
            val payload: WorkshopDiscoveryPayload = discoveryService.fetch()
            val selection = WorkshopDiscoverySelection.select(payload, profile.items, nowMillis)
            assertEquals(listOf("pub_free"), selection.featuredApps.map { it.id })
            assertEquals(listOf("pub_free"), selection.weeklyChartApps.map { it.id })
        }
    }
}
