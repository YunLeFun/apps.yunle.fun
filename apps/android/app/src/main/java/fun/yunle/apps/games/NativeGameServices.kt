package `fun`.yunle.apps.games

import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.readString
import `fun`.yunle.apps.webruntime.HostAuthorizationError
import `fun`.yunle.apps.webruntime.HostAuthorizationException
import `fun`.yunle.apps.webruntime.HostAuthorizationServing
import `fun`.yunle.apps.webruntime.HostSsoRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.Locale
import java.util.UUID

internal interface NativeGameCatalogServing {
    suspend fun catalog(): NativeGameCatalog
}

internal class NativeGameCatalogService(
    private val endpoint: String = "https://play.yunle.fun/native/catalog-v1.json",
) : NativeGameCatalogServing {
    override suspend fun catalog(): NativeGameCatalog = withContext(Dispatchers.IO) {
        val uri = runCatching { URI(endpoint) }.getOrNull()
        val isLocalLoopback = uri?.scheme == "http" && (uri.host == "127.0.0.1" || uri.host == "localhost")
        if (!NativeGame.isPublicHttps(endpoint) && !isLocalLoopback) {
            throw NativeGameException(NativeGameError.INVALID_CATALOG)
        }
        val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 15_000
            readTimeout = 20_000
            setRequestProperty("Accept", "application/json")
        }
        try {
            val status = conn.responseCode
            if (status != 200) throw NativeGameException(NativeGameError.INVALID_CATALOG)
            val contentType = conn.contentType?.lowercase(Locale.ROOT).orEmpty()
            if (!contentType.startsWith("application/json")) {
                throw NativeGameException(NativeGameError.INVALID_CATALOG)
            }
            val bytes = readLimited(conn, 1_048_576)
                ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
            NativeGameCatalog.decode(bytes.toString(Charsets.UTF_8))
        } catch (e: NativeGameException) {
            throw e
        } catch (t: Throwable) {
            throw NativeGameException(NativeGameError.INVALID_CATALOG, t)
        } finally {
            conn.disconnect()
        }
    }
}

internal class NativeGameCatalogStore(
    private val cacheFile: File,
    private val bundledLoader: () -> String?,
    private val service: NativeGameCatalogServing = NativeGameCatalogService(),
) {
    enum class Source { BUNDLED, SAVED, ONLINE }

    private val _catalog = MutableStateFlow<NativeGameCatalog?>(null)
    val catalog: StateFlow<NativeGameCatalog?> = _catalog.asStateFlow()

    private val _games = MutableStateFlow<List<NativeGame>>(emptyList())
    val games: StateFlow<List<NativeGame>> = _games.asStateFlow()

    private val _source = MutableStateFlow<Source?>(null)
    val source: StateFlow<Source?> = _source.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    @Volatile
    private var didAttemptLoad = false

    init {
        val saved = runCatching {
            if (cacheFile.isFile) NativeGameCatalog.decode(cacheFile.readText(Charsets.UTF_8)) else null
        }.getOrNull()
        if (saved != null) {
            _catalog.value = saved
            _games.value = saved.games.filter { it.matchesFirstRelease }
            _source.value = Source.SAVED
        } else {
            val bundled = runCatching {
                bundledLoader()?.let(NativeGameCatalog::decode)
            }.getOrNull()
            if (bundled != null) {
                _catalog.value = bundled
                _games.value = bundled.games.filter { it.matchesFirstRelease }
                _source.value = Source.BUNDLED
            }
        }
    }

    fun game(id: String): NativeGame? = _games.value.firstOrNull { it.gameId == id }

    suspend fun load(force: Boolean = false) {
        if (_isLoading.value || (!force && didAttemptLoad)) return
        didAttemptLoad = true
        _isLoading.value = true
        try {
            val next = service.catalog()
            _catalog.value = next
            _games.value = next.games.filter { it.matchesFirstRelease }
            _source.value = Source.ONLINE
            _error.value = null
            runCatching {
                withContext(Dispatchers.IO) {
                    writeAtomicUtf8(cacheFile, next.toJsonString())
                }
            }
        } catch (c: CancellationException) {
            didAttemptLoad = false
            throw c
        } catch (t: Throwable) {
            _error.value = NativeGameError.message(t)
        } finally {
            _isLoading.value = false
        }
    }
}

internal data class NativeGameHistoryEntry(
    val gameId: String,
    val modeId: String,
    val lastReadyAtMillis: Long,
) {
    val id: String get() = gameId
}

internal class NativeGameHistoryStore(
    private val directory: File,
) {
    private val lock = Any()
    private val _entries = MutableStateFlow<List<NativeGameHistoryEntry>>(emptyList())
    val entries: StateFlow<List<NativeGameHistoryEntry>> = _entries.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    @Volatile
    var generation: UUID = UUID.randomUUID()
        private set

    @Volatile
    var accountId: String? = null
        private set

    @Volatile
    private var activated = false

    fun activate(accountId: String?) {
        synchronized(lock) {
            if (activated && this.accountId == accountId) return
            activated = true
            this.accountId = accountId
            generation = UUID.randomUUID()
            _entries.value = emptyList()
            _error.value = null
            val target = fileFor(accountId)
            if (!target.isFile) return
            try {
                val raw = target.readBytes()
                if (raw.size > 65_536) throw NativeGameException(NativeGameError.INVALID_CATALOG)
                val arr = JSONArray(raw.toString(Charsets.UTF_8))
                val restored = ArrayList<NativeGameHistoryEntry>(arr.length())
                val seen = mutableSetOf<String>()
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
                    val gId = obj.readString("gameId") ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
                    val mId = obj.readString("modeId") ?: throw NativeGameException(NativeGameError.INVALID_CATALOG)
                    val ts = obj.optLong("lastReadyAtMillis", -1L)
                    if (!NativeGame.validIdentifier(gId) ||
                        mId !in NativeGameMode.SUPPORTED_IDS ||
                        ts <= 0L ||
                        !seen.add(gId)
                    ) {
                        throw NativeGameException(NativeGameError.INVALID_CATALOG)
                    }
                    restored.add(NativeGameHistoryEntry(gId, mId, ts))
                }
                if (restored.size > 12) throw NativeGameException(NativeGameError.INVALID_CATALOG)
                _entries.value = restored.sortedByDescending { it.lastReadyAtMillis }
            } catch (_: Throwable) {
                _error.value = "本机最近游玩记录暂时无法读取。"
            }
        }
    }

    fun recordReady(
        gameId: String,
        modeId: String,
        accountId: String?,
        expectedGeneration: UUID? = null,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        synchronized(lock) {
            if (!activated ||
                this.accountId != accountId ||
                (expectedGeneration != null && expectedGeneration != generation) ||
                !NativeGame.validIdentifier(gameId) ||
                modeId !in NativeGameMode.SUPPORTED_IDS
            ) {
                return
            }
            val updated = (listOf(NativeGameHistoryEntry(gameId, modeId, nowMillis)) +
                _entries.value.filterNot { it.gameId == gameId })
                .sortedByDescending { it.lastReadyAtMillis }
                .take(12)
            _entries.value = updated
            val json = JSONArray().apply {
                updated.forEach { entry ->
                    put(
                        JSONObject()
                            .put("gameId", entry.gameId)
                            .put("modeId", entry.modeId)
                            .put("lastReadyAtMillis", entry.lastReadyAtMillis),
                    )
                }
            }
            try {
                writeAtomicUtf8(fileFor(accountId), json.toString())
                _error.value = null
            } catch (_: Throwable) {
                _error.value = "最近游玩已更新，本机暂时无法保存记录。"
            }
        }
    }

    private fun fileFor(accountId: String?): File {
        val scope = if (accountId != null) {
            "account-" + sha256Hex(accountId.toByteArray(Charsets.UTF_8))
        } else {
            "guest"
        }
        return File(directory, "$scope.json")
    }
}

internal interface NativePublicRoomServing {
    suspend fun rooms(): List<NativePublicRoom>
}

internal class NativePublicRoomService(
    private val endpoint: String = "https://api.play.yunle.fun/v1/rooms/public",
) : NativePublicRoomServing {
    override suspend fun rooms(): List<NativePublicRoom> = withContext(Dispatchers.IO) {
        val uri = runCatching { URI(endpoint) }.getOrNull()
        val isLocalLoopback = uri?.scheme == "http" && (uri.host == "127.0.0.1" || uri.host == "localhost")
        if (!NativeGame.isPublicHttps(endpoint) && !isLocalLoopback) {
            throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
        }
        val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 15_000
            readTimeout = 20_000
            setRequestProperty("Accept", "application/json")
        }
        try {
            val status = conn.responseCode
            if (status != 200) throw NativePublicRoomException(NativePublicRoomError.UNAVAILABLE)
            val contentType = conn.contentType?.lowercase(Locale.ROOT).orEmpty()
            if (!contentType.startsWith("application/json")) {
                throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            }
            val bytes = readLimited(conn, 65_536)
                ?: throw NativePublicRoomException(NativePublicRoomError.INVALID_RESPONSE)
            NativePublicRoom.decodeList(bytes.toString(Charsets.UTF_8))
        } catch (e: NativePublicRoomException) {
            throw e
        } catch (t: Throwable) {
            throw NativePublicRoomException(NativePublicRoomError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }
}

internal interface NativeRoomCreating {
    suspend fun create(
        draft: NativeRoomCreationDraft,
        idempotencyKey: UUID,
        identity: AuthorizedAccount,
        consent: Boolean,
        isCurrent: suspend () -> Boolean = { true },
    ): NativeGameRoomIntent
}

internal class NativeRoomCreationService(
    private val authorization: HostAuthorizationServing,
    private val origin: String = "https://play.yunle.fun",
    private val apiOrigin: String = "https://api.play.yunle.fun",
    private val exchangeUrl: String = "https://api.yunle.fun/sso-ticket",
) : NativeRoomCreating {
    private val rng = SecureRandom()

    override suspend fun create(
        draft: NativeRoomCreationDraft,
        idempotencyKey: UUID,
        identity: AuthorizedAccount,
        consent: Boolean,
        isCurrent: suspend () -> Boolean,
    ): NativeGameRoomIntent {
        val payload = draft.payloadJson()
        val verifier = randomBase64Url()
        val nonce = randomBase64Url()
        val challenge = sha256Base64Url(verifier.toByteArray(Charsets.UTF_8))

        val ssoRequest = HostSsoRequest.parse(
            sourceOrigin = origin,
            parameters = JSONObject()
                .put("clientId", "play-web")
                .put("redirectUri", "$origin/")
                .put("nonce", nonce)
                .put("codeChallenge", challenge)
                .put("codeChallengeMethod", "S256")
                .put("scope", JSONArray().put("identity:bootstrap")),
        )

        val code = try {
            val policy = authorization.resolve(ssoRequest)
            if (policy.applicationID != "play") {
                throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
            }
            if (policy.prompt != null && !consent) {
                throw NativeRoomCreationException(NativeRoomCreationError.CONSENT_REQUIRED)
            }
            authorization.issue(ssoRequest, identity)
        } catch (e: HostAuthorizationException) {
            when (e.error) {
                HostAuthorizationError.UNAUTHORIZED -> throw NativeRoomCreationException(NativeRoomCreationError.UNAUTHORIZED, e)
                HostAuthorizationError.INVALID_RESPONSE -> throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE, e)
                else -> throw NativeRoomCreationException(NativeRoomCreationError.UNAVAILABLE, e)
            }
        }

        val exchangeBody = JSONObject()
            .put("action", "exchangeSsoCode")
            .put("clientId", "play-web")
            .put("redirectUri", ssoRequest.redirectURI)
            .put("scope", "identity:bootstrap")
            .put("code", code.code)
            .put("nonce", nonce)
            .put("codeVerifier", verifier)
            .toString()
        val (exchangeJson, _) = sendJson(exchangeUrl, "POST", exchangeBody)
        val assertion = exchangeJson.readString("identityAssertion").orEmpty()
        if (exchangeJson.opt("ok") != true || assertion.length !in 64..8192) {
            throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
        }

        val sessionExchangeBody = JSONObject()
            .put("accessToken", identity.accessToken)
            .put("identityAssertion", assertion)
            .put("nonce", nonce)
            .toString()
        val (connectedJson, sessionHeaders) = sendJson(
            urlString = "${apiOrigin.trimEnd('/')}/v1/session/exchange",
            method = "POST",
            body = sessionExchangeBody,
        )
        val connectedUserId = connectedJson.optJSONObject("user")?.readString("userId")
        val sessionCookie = extractPlaySessionCookie(sessionHeaders)
        if (connectedJson.opt("ok") != true || connectedUserId != identity.userID || sessionCookie == null) {
            throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
        }

        try {
            if (!isCurrent()) throw NativeRoomCreationException(NativeRoomCreationError.IDENTITY_CHANGED)
            val (createdJson, _) = sendJson(
                urlString = "${apiOrigin.trimEnd('/')}/v1/rooms",
                method = "POST",
                body = payload,
                cookie = sessionCookie,
                idempotencyKey = idempotencyKey.toString().lowercase(Locale.ROOT),
            )
            val roomObj = createdJson.optJSONObject("room")
            val inviteCode = roomObj?.readString("inviteCode")
            val capacity = roomObj?.optInt("roomCapacity", -1) ?: -1
            if (createdJson.opt("ok") != true || capacity != 4 || inviteCode == null) {
                throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
            }
            val intent = NativeGameRoomIntent.parseInput(inviteCode)
            if (intent.inviteCode != inviteCode) {
                throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
            }
            return intent
        } finally {
            withContext(NonCancellable) {
                runCatching {
                    sendJson(
                        urlString = "${apiOrigin.trimEnd('/')}/v1/session",
                        method = "DELETE",
                        body = null,
                        cookie = sessionCookie,
                    )
                }
            }
        }
    }

    private suspend fun sendJson(
        urlString: String,
        method: String,
        body: String?,
        cookie: String? = null,
        idempotencyKey: String? = null,
    ): Pair<JSONObject, List<String>> = withContext(Dispatchers.IO) {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Origin", origin)
            if (cookie != null) setRequestProperty("Cookie", cookie)
            if (idempotencyKey != null) setRequestProperty("Idempotency-Key", idempotencyKey)
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
                401 -> throw NativeRoomCreationException(NativeRoomCreationError.UNAUTHORIZED)
                403 -> throw NativeRoomCreationException(NativeRoomCreationError.FORBIDDEN)
                in 200..299 -> Unit
                else -> throw NativeRoomCreationException(NativeRoomCreationError.UNAVAILABLE)
            }
            val contentType = conn.contentType?.lowercase(Locale.ROOT).orEmpty()
            if (!contentType.startsWith("application/json")) {
                throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
            }
            val bytes = readLimited(conn, 1_048_576)
                ?: throw NativeRoomCreationException(NativeRoomCreationError.INVALID_RESPONSE)
            val setCookies = conn.headerFields
                .entries
                .firstOrNull { it.key.equals("Set-Cookie", ignoreCase = true) }
                ?.value
                .orEmpty()
            JSONObject(bytes.toString(Charsets.UTF_8)) to setCookies
        } catch (e: NativeRoomCreationException) {
            throw e
        } catch (t: Throwable) {
            throw NativeRoomCreationException(NativeRoomCreationError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }

    private fun extractPlaySessionCookie(setCookieHeaders: List<String>): String? {
        val matches = setCookieHeaders.mapNotNull { header ->
            val segments = header.split(';').map { it.trim() }
            val nv = segments.firstOrNull() ?: return@mapNotNull null
            val eqIdx = nv.indexOf('=')
            if (eqIdx <= 0) return@mapNotNull null
            val name = nv.substring(0, eqIdx).trim()
            val value = nv.substring(eqIdx + 1).trim()
            if (name != "__Host-ylf_play_session" || value.isEmpty()) return@mapNotNull null
            val attrs = segments.drop(1).map { it.lowercase(Locale.ROOT) }
            val hasSecure = attrs.contains("secure")
            val hasHttpOnly = attrs.contains("httponly")
            val hasRootPath = attrs.contains("path=/")
            val hasDomain = attrs.any { it.startsWith("domain=") }
            if (!hasSecure || !hasHttpOnly || !hasRootPath || hasDomain) return@mapNotNull null
            "$name=$value"
        }
        return matches.singleOrNull()
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
}

private fun readLimited(conn: HttpURLConnection, limit: Int): ByteArray? {
    conn.inputStream.use { stream ->
        val buffer = ByteArray(8192)
        val out = ByteArrayOutputStream()
        while (true) {
            val count = stream.read(buffer)
            if (count == -1) break
            if (out.size() + count > limit) return null
            out.write(buffer, 0, count)
        }
        return out.toByteArray()
    }
}

internal fun writeAtomicUtf8(target: File, text: String) {
    target.parentFile?.mkdirs()
    val tmp = File(target.parentFile, ".${target.name}.${UUID.randomUUID()}.tmp")
    try {
        tmp.writeText(text, Charsets.UTF_8)
        Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
    } finally {
        if (tmp.exists()) tmp.delete()
    }
}

internal fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
