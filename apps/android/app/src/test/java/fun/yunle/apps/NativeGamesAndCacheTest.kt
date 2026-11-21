package `fun`.yunle.apps

import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.cache.ApplicationCacheEntry
import `fun`.yunle.apps.cache.ApplicationCacheError
import `fun`.yunle.apps.cache.ApplicationCacheException
import `fun`.yunle.apps.cache.ApplicationCacheRepository
import `fun`.yunle.apps.cache.ApplicationStaticResourcePolicy
import `fun`.yunle.apps.cache.NativeGameResourceCacheError
import `fun`.yunle.apps.cache.NativeGameResourceCacheException
import `fun`.yunle.apps.cache.NativeGameResourceCacheStore
import `fun`.yunle.apps.cache.NativeGameResourcePolicy
import `fun`.yunle.apps.games.NativeGame
import `fun`.yunle.apps.games.NativeGameCatalog
import `fun`.yunle.apps.games.NativeGameError
import `fun`.yunle.apps.games.NativeGameException
import `fun`.yunle.apps.games.NativeGameHistoryStore
import `fun`.yunle.apps.games.NativeGameLaunchUrl
import `fun`.yunle.apps.games.NativeGameLifecycleEvent
import `fun`.yunle.apps.games.NativeGameRoomIntent
import `fun`.yunle.apps.games.NativePublicRoom
import `fun`.yunle.apps.games.NativePublicRoomError
import `fun`.yunle.apps.games.NativePublicRoomException
import `fun`.yunle.apps.games.NativeRoomCreationDraft
import `fun`.yunle.apps.games.NativeRoomCreationError
import `fun`.yunle.apps.games.NativeRoomCreationException
import `fun`.yunle.apps.games.NativeRoomCreationService
import `fun`.yunle.apps.games.sha256Hex
import `fun`.yunle.apps.webruntime.HostAuthorizationServing
import `fun`.yunle.apps.webruntime.HostSsoCode
import `fun`.yunle.apps.webruntime.HostSsoPolicy
import `fun`.yunle.apps.webruntime.HostSsoRequest
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
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors

class NativeGamesAndCacheTest {
    private data class Req(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
        val body: String,
    )

    private data class Res(
        val status: Int = 200,
        val contentType: String = "application/json; charset=utf-8",
        val extraHeaders: List<Pair<String, String>> = emptyList(),
        val bodyBytes: ByteArray = "{}".toByteArray(Charsets.UTF_8),
    )

    private class StubHttpServer(
        private val handler: (Req) -> Res,
    ) : Closeable {
        private val server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        private val pool = Executors.newCachedThreadPool()
        val requests = ConcurrentLinkedQueue<Req>()
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
                            val first = lines.first().split(' ')
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
                                val n = input.read(body, offset, contentLength - offset)
                                if (n == -1) break
                                offset += n
                            }
                            val req = Req(first[0], first[1], headers, body.toString(Charsets.UTF_8))
                            requests.add(req)
                            val res = handler(req)
                            val head = buildString {
                                append("HTTP/1.1 ${res.status} OK\r\n")
                                append("Content-Type: ${res.contentType}\r\n")
                                append("Content-Length: ${res.bodyBytes.size}\r\n")
                                res.extraHeaders.forEach { (k, v) -> append("$k: $v\r\n") }
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

    private fun bundledCatalogFile(): File {
        val candidates = listOf(
            File("src/main/assets/native-game-catalog-v1.json"),
            File("app/src/main/assets/native-game-catalog-v1.json"),
            File("apps/android/app/src/main/assets/native-game-catalog-v1.json"),
        )
        return candidates.first { it.isFile }
    }

    @Test
    fun bundledCatalogDecodesAndRejectsInvalidSchemas() {
        val raw = bundledCatalogFile().readText(Charsets.UTF_8)
        val catalog = NativeGameCatalog.decode(raw)
        assertEquals(1, catalog.schemaVersion)
        assertTrue(catalog.games.map { it.gameId }.toSet().containsAll(NativeGame.FIRST_RELEASE_IDS))

        val badVersion = JSONObject(raw).put("schemaVersion", 2).toString()
        try {
            NativeGameCatalog.decode(badVersion)
            fail("Expected unsupported catalog")
        } catch (e: NativeGameException) {
            assertEquals(NativeGameError.UNSUPPORTED_CATALOG, e.error)
        }

        val badUrlObj = JSONObject(raw)
        badUrlObj.getJSONArray("games").getJSONObject(0)
            .getJSONArray("launchModes").getJSONObject(0)
            .put("launchURL", "https://evil.example/games/gomoku/computer")
        try {
            NativeGameCatalog.decode(badUrlObj.toString())
            fail("Expected invalid launch url")
        } catch (e: NativeGameException) {
            assertEquals(NativeGameError.INVALID_LAUNCH, e.error)
        }
    }

    @Test
    fun roomIntentsPublicRoomsAndLifecycleValidation() {
        val fromCode = NativeGameRoomIntent.parseInput("ab12cd", NativeGameRoomIntent.Role.PLAYER)
        assertEquals("AB12CD", fromCode.inviteCode)
        assertEquals("https://play.yunle.fun/room/AB12CD", fromCode.url)

        val spectator = NativeGameRoomIntent.parseInput("https://play.yunle.fun/room/XY89ZZ?role=spectator")
        assertEquals(NativeGameRoomIntent.Role.SPECTATOR, spectator.role)
        assertEquals("XY89ZZ", spectator.inviteCode)

        val publicJson = JSONObject()
            .put("ok", true)
            .put(
                "rooms",
                JSONArray()
                    .put(JSONObject().put("inviteCode", "RM0001").put("gameId", "gomoku").put("status", "waiting").put("memberCount", 1).put("capacity", 4))
                    .put(JSONObject().put("inviteCode", "RM0002").put("gameId", JSONObject.NULL).put("status", "playing").put("memberCount", 4).put("capacity", 8)),
            )
            .toString()
        val rooms = NativePublicRoom.decodeList(publicJson)
        assertEquals(2, rooms.size)
        assertFalse(rooms[0].isSpectating)
        assertEquals("加入房间", rooms[0].actionTitle)
        assertTrue(rooms[1].isSpectating)
        assertEquals("观战", rooms[1].actionTitle)

        try {
            NativePublicRoom.decodeList("""{"ok":true,"rooms":[{"inviteCode":"RM0001","status":"waiting","memberCount":4,"capacity":4}]}""")
            fail("Expected invalid full room")
        } catch (e: NativePublicRoomException) {
            assertEquals(NativePublicRoomError.INVALID_RESPONSE, e.error)
        }

        val launchId = UUID.randomUUID()
        val ctxUrl = NativeGameLaunchUrl.addingContext("https://play.yunle.fun/games/gomoku/computer", launchId, "gomoku", "computer")!!
        val extracted = NativeGameLaunchUrl.extractContext(ctxUrl)!!
        assertEquals(launchId, extracted.launchId)
        assertEquals("gomoku", extracted.gameId)
        assertEquals("computer", extracted.modeId)
        assertEquals("https://play.yunle.fun/games/gomoku/computer", NativeGameLaunchUrl.publicUrl(ctxUrl))

        val validEvent = JSONObject()
            .put("schemaVersion", 1)
            .put("launchId", launchId.toString())
            .put("gameId", "gomoku")
            .put("modeId", "computer")
            .put("state", "room-ready")
            .put("elapsedMilliseconds", 420.5)
            .put("room", JSONObject().put("inviteCode", "RM0001").put("role", "player").put("state", "playing").put("gameId", "gomoku"))
        assertNotNull(NativeGameLifecycleEvent.parse(validEvent, "https://play.yunle.fun", launchId, "gomoku", "computer"))
        assertNull(NativeGameLifecycleEvent.parse(validEvent, "https://evil.example", launchId, "gomoku", "computer"))
        assertNull(NativeGameLifecycleEvent.parse(validEvent, "https://play.yunle.fun", UUID.randomUUID(), "gomoku", "computer"))
    }

    @Test
    fun nativeRoomCreationFourStepSsoAndIdempotency() = runBlocking {
        val identity = AuthorizedAccount("user_9", "access_tok_9")
        val fakeAuth = object : HostAuthorizationServing {
            var promptMode: String? = "consent"
            override suspend fun resolve(request: HostSsoRequest): HostSsoPolicy {
                assertEquals("play-web", request.clientID)
                return HostSsoPolicy(
                    applicationID = "play",
                    applicationName = "云乐坊游戏大厅",
                    applicationOrigin = request.sourceOrigin,
                    applicationIconURL = null,
                    permissionDescription = "账号标识、昵称和头像",
                    prompt = promptMode,
                    version = "1",
                    registrationFingerprint = "a".repeat(64),
                )
            }

            override suspend fun issue(request: HostSsoRequest, identity: AuthorizedAccount): HostSsoCode =
                HostSsoCode(code = "c".repeat(43), expiresAt = null)
        }

        StubHttpServer { req ->
            when {
                req.method == "POST" && req.path == "/sso-ticket" -> Res(
                    bodyBytes = JSONObject()
                        .put("ok", true)
                        .put("identityAssertion", "a".repeat(80))
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/v1/session/exchange" -> Res(
                    extraHeaders = listOf("Set-Cookie" to "__Host-ylf_play_session=play_sess_abc; Path=/; HttpOnly; Secure; SameSite=Lax"),
                    bodyBytes = JSONObject()
                        .put("ok", true)
                        .put("user", JSONObject().put("userId", "user_9"))
                        .toString()
                        .toByteArray(Charsets.UTF_8),
                )
                req.method == "POST" && req.path == "/v1/rooms" -> {
                    assertEquals("__Host-ylf_play_session=play_sess_abc", req.headers["cookie"])
                    assertNotNull(req.headers["idempotency-key"])
                    Res(
                        bodyBytes = JSONObject()
                            .put("ok", true)
                            .put("room", JSONObject().put("inviteCode", "PLAY88").put("roomCapacity", 4))
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                }
                req.method == "DELETE" && req.path == "/v1/session" -> Res(
                    bodyBytes = """{"ok":true}""".toByteArray(Charsets.UTF_8),
                )
                else -> Res(status = 404)
            }
        }.use { server ->
            val service = NativeRoomCreationService(
                authorization = fakeAuth,
                origin = "https://play.yunle.fun",
                apiOrigin = server.origin,
                exchangeUrl = "${server.origin}/sso-ticket",
            )
            val draft = NativeRoomCreationDraft(gameId = "gomoku", isPublic = true)
            val key = UUID.randomUUID()

            try {
                service.create(draft, key, identity, consent = false)
                fail("Expected consent required")
            } catch (e: NativeRoomCreationException) {
                assertEquals(NativeRoomCreationError.CONSENT_REQUIRED, e.error)
            }

            val intent = service.create(draft, key, identity, consent = true)
            assertEquals("PLAY88", intent.inviteCode)
            assertEquals("https://play.yunle.fun/room/PLAY88", intent.url)
            assertTrue(server.requests.any { it.method == "DELETE" && it.path == "/v1/session" })
        }
    }

    @Test
    fun historyStoreGameResourceCacheAndAppCachePolicies() = runBlocking {
        val tempRoot = Files.createTempDirectory("yunle-m4-test").toFile()
        try {
            val history = NativeGameHistoryStore(File(tempRoot, "history"))
            history.activate(null)
            history.recordReady("gomoku", "computer", null, nowMillis = 1_000L)
            history.activate("user_a")
            assertTrue(history.entries.value.isEmpty())
            val staleGen = history.generation
            history.recordReady("gomoku", "online", "user_a", expectedGeneration = staleGen, nowMillis = 2_000L)
            assertEquals(1, history.entries.value.size)
            history.activate(null)
            assertEquals(1_000L, history.entries.value.single().lastReadyAtMillis)

            // Static Resource Policy & Cache Repository
            assertTrue(ApplicationStaticResourcePolicy.isPublic(200, "public, max-age=3600", null, "Accept-Encoding"))
            assertFalse(ApplicationStaticResourcePolicy.isPublic(200, "private, public, max-age=3600", null, null))
            assertFalse(ApplicationStaticResourcePolicy.isPublic(200, "public, max-age=3600", "sid=1", null))
            assertFalse(ApplicationStaticResourcePolicy.isPublic(200, "public, max-age=3600", null, "Cookie"))

            val refs = ApplicationStaticResourcePolicy.references(
                text = """<script src="/_nuxt/entry.js"></script><img src="https://admin.yunle.fun/_nuxt/logo.png?bad=1">""",
                baseUrl = "https://admin.yunle.fun/",
                expectedOrigin = "https://admin.yunle.fun/",
            )
            assertEquals(listOf("https://admin.yunle.fun/_nuxt/entry.js"), refs)

            val repo = ApplicationCacheRepository(File(tempRoot, "appcache"), totalLimitBytes = 20L)
            val app = CatalogApp(
                id = "tool_1",
                key = "tool-1",
                name = "公开工具",
                description = "",
                author = "yunle",
                ownerLogin = "yunle",
                category = "效率",
                emoji = "🛠",
                launchUrl = "https://tool1.yunle.fun/",
                logo = null,
                themeColor = null,
                trustedHosts = emptyList(),
                immersive = false,
                accessMode = "public",
                audience = "public",
            )
            val saved = repo.save("hello-cache".toByteArray(Charsets.UTF_8), 1, app)
            assertEquals(11, saved.byteCount)
            assertEquals("hello-cache", repo.readPayload(app)?.toString(Charsets.UTF_8))

            // Tamper test
            val id = ApplicationCacheEntry.key(app)
            File(tempRoot, "appcache/$id.bin").writeBytes("corrupt".toByteArray(Charsets.UTF_8))
            try {
                repo.readPayload(app)
                fail("Expected corrupt cache rejection")
            } catch (e: ApplicationCacheException) {
                assertEquals(ApplicationCacheError.INVALID_ARCHIVE, e.error)
            }

            // Game Resource Cache download + digest verification + interception lookup
            val scriptBytes = "console.log('gomoku-ok');".toByteArray(Charsets.UTF_8)
            val scriptSha = sha256Hex(scriptBytes)
            var tamperBytes = false
            StubHttpServer { req ->
                when (req.path) {
                    "/native/resources/gomoku-v1.json" -> Res(
                        bodyBytes = JSONObject()
                            .put("schemaVersion", 1)
                            .put("gameId", "gomoku")
                            .put("version", "b".repeat(64))
                            .put("generatedAt", "2026-11-21T00:00:00Z")
                            .put("totalBytes", scriptBytes.size)
                            .put(
                                "resources",
                                JSONArray().put(
                                    JSONObject()
                                        .put("url", "${req.headers["host"]?.let { "http://$it" } ?: "http://127.0.0.1"}/games/gomoku/main.js")
                                        .put("sha256", scriptSha)
                                        .put("byteCount", scriptBytes.size)
                                        .put("contentType", "application/javascript")
                                        .put("required", true),
                                ),
                            )
                            .toString()
                            .toByteArray(Charsets.UTF_8),
                    )
                    "/games/gomoku/main.js" -> Res(
                        contentType = "application/javascript; charset=utf-8",
                        extraHeaders = listOf("Cache-Control" to "public, max-age=31536000, immutable"),
                        bodyBytes = if (tamperBytes) "tampered!!".padEnd(scriptBytes.size, 'x').toByteArray(Charsets.UTF_8) else scriptBytes,
                    )
                    else -> Res(status = 404)
                }
            }.use { server ->
                val gameCache = NativeGameResourceCacheStore(
                    rootDir = File(tempRoot, "gamecache"),
                    allowLocalHttpForTesting = true,
                )
                assertTrue(NativeGameResourcePolicy.manifestUrl("${server.origin}/native/resources/gomoku-v1.json", "gomoku", allowLocalHttp = true))
                val entry = gameCache.downloadBlocking(
                    manifestUrl = "${server.origin}/native/resources/gomoku-v1.json",
                    gameId = "gomoku",
                    profileKey = "prof_1",
                )
                assertEquals(1, entry.resourceCount)
                val cached = gameCache.openCachedResource("${server.origin}/games/gomoku/main.js", "gomoku", "prof_1")
                assertNotNull(cached)
                assertEquals("application/javascript", cached?.mimeType)

                tamperBytes = true
                try {
                    gameCache.downloadBlocking(
                        manifestUrl = "${server.origin}/native/resources/gomoku-v1.json",
                        gameId = "gomoku",
                        profileKey = "prof_2",
                    )
                    fail("Expected SHA-256 integrity failure")
                } catch (e: NativeGameResourceCacheException) {
                    assertEquals(NativeGameResourceCacheError.INTEGRITY, e.error)
                }
            }
        } finally {
            tempRoot.deleteRecursively()
        }
    }
}
