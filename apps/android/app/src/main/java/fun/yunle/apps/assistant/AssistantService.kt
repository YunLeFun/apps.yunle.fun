package `fun`.yunle.apps.assistant

import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.account.CloudbaseAuthService
import `fun`.yunle.apps.games.sha256Hex
import `fun`.yunle.apps.games.writeAtomicUtf8
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

internal interface AssistantServing {
    fun streamEvents(input: AssistantRunInput, identity: AuthorizedAccount): Flow<AssistantEvent>
    suspend fun search(query: String, identity: AuthorizedAccount): List<AssistantAppCard>
}

internal class AssistantService(
    private val gatewayOrigin: String = CloudbaseAuthService.GATEWAY_ORIGIN,
    private val appsOrigin: String = "https://apps.yunle.fun",
) : AssistantServing {
    private val baseGateway = gatewayOrigin.trimEnd('/')
    private val baseApps = appsOrigin.trimEnd('/')

    override fun streamEvents(input: AssistantRunInput, identity: AuthorizedAccount): Flow<AssistantEvent> = flow {
        val bodyBytes = input.toJsonBytes()
        val url = "$baseGateway/v1/aibot/bots/${AssistantRunInput.BOT_ID}/send-message"
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            instanceFollowRedirects = false
            useCaches = false
            doOutput = true
            connectTimeout = 20_000
            readTimeout = 90_000
            setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "text/event-stream")
        }
        try {
            conn.outputStream.use { it.write(bodyBytes) }
            val code = conn.responseCode
            if (code != 200) {
                val errText = runCatching {
                    conn.errorStream?.use { stream ->
                        val cap = ByteArray(8192)
                        val n = stream.read(cap)
                        if (n > 0) String(cap, 0, n, Charsets.UTF_8) else ""
                    }
                }.getOrNull().orEmpty()
                val errJson = runCatching { JSONObject(errText) }.getOrNull()
                val errCode = errJson?.optString("code").orEmpty()
                when (code) {
                    401 -> throw AssistantException(AssistantError.UNAUTHORIZED)
                    429 -> throw AssistantException(AssistantError.QUOTA)
                    403 -> throw AssistantException(
                        if (errCode == "MEMBERSHIP_REQUIRED") AssistantError.MEMBERSHIP_REQUIRED else AssistantError.FORBIDDEN,
                    )
                    else -> throw AssistantException(AssistantError.UNAVAILABLE)
                }
            }
            val contentType = conn.contentType?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT)
            if (contentType != "text/event-stream") {
                throw AssistantException(AssistantError.INVALID_RESPONSE)
            }
            val decoder = AssistantSSEDecoder()
            var totalBytes = 0
            BufferedInputStream(conn.inputStream).use { input ->
                val buf = ByteArray(1024)
                while (currentCoroutineContext().isActive) {
                    val read = input.read(buf)
                    if (read == -1) break
                    for (i in 0 until read) {
                        totalBytes++
                        if (totalBytes > MAX_STREAM_BYTES) throw AssistantException(AssistantError.TOO_LONG)
                        val frame = decoder.append(buf[i])
                        if (frame != null) {
                            val event = AssistantEvent.parse(frame)
                            emit(event)
                            if (event.type == "RUN_FINISHED" || event.type == "RUN_ERROR" || event.type == "_DONE") {
                                return@flow
                            }
                        }
                    }
                }
            }
        } catch (c: CancellationException) {
            throw c
        } catch (e: AssistantException) {
            throw e
        } catch (t: Throwable) {
            throw AssistantException(AssistantError.INTERRUPTED, t)
        } finally {
            conn.disconnect()
        }
    }.flowOn(Dispatchers.IO)

    override suspend fun search(query: String, identity: AuthorizedAccount): List<AssistantAppCard> =
        withContext(Dispatchers.IO) {
            val conn = (URL("$baseApps/api/agent/search-apps").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                instanceFollowRedirects = false
                useCaches = false
                doOutput = true
                connectTimeout = 15_000
                readTimeout = 20_000
                setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
            }
            try {
                val payload = JSONObject()
                    .put("query", query.take(120))
                    .put("limit", 6)
                    .toString()
                    .toByteArray(Charsets.UTF_8)
                conn.outputStream.use { it.write(payload) }
                val code = conn.responseCode
                if (code == 401) throw AssistantException(AssistantError.UNAUTHORIZED)
                if (code != 200) throw AssistantException(AssistantError.UNAVAILABLE)
                val out = ByteArrayOutputStream()
                conn.inputStream.use { input ->
                    val buf = ByteArray(8192)
                    while (true) {
                        val n = input.read(buf)
                        if (n == -1) break
                        if (out.size() + n > 512 * 1024) throw AssistantException(AssistantError.TOO_LONG)
                        out.write(buf, 0, n)
                    }
                }
                val json = JSONObject(out.toString(Charsets.UTF_8.name()))
                if (json.optInt("code", -1) != 0) throw AssistantException(AssistantError.UNAVAILABLE)
                AssistantEvent.extractCards(json.opt("data"))
            } catch (e: AssistantException) {
                throw e
            } catch (t: Throwable) {
                throw AssistantException(AssistantError.UNAVAILABLE, t)
            } finally {
                conn.disconnect()
            }
        }

    companion object {
        private const val MAX_STREAM_BYTES = 2 * 1024 * 1024
    }
}

internal class AssistantHistoryStore(
    private val directory: File,
) {
    private val lock = Any()
    private val _messages = MutableStateFlow<List<AssistantMessage>>(emptyList())
    val messages: StateFlow<List<AssistantMessage>> = _messages.asStateFlow()

    @Volatile
    var accountId: String? = null
        private set

    fun activate(accountId: String?) {
        synchronized(lock) {
            this.accountId = accountId
            _messages.value = emptyList()
            if (accountId == null) return
            val target = fileFor(accountId)
            if (!target.isFile) return
            val restored = runCatching {
                val arr = JSONArray(target.readText(Charsets.UTF_8))
                (0 until arr.length()).mapNotNull { idx ->
                    arr.optJSONObject(idx)?.let(AssistantMessage::fromJson)
                }.takeLast(MAX_MESSAGES)
            }.getOrDefault(emptyList())
            _messages.value = restored
        }
    }

    fun save(next: List<AssistantMessage>, forAccountId: String?) {
        synchronized(lock) {
            if (forAccountId == null || this.accountId != forAccountId) return
            val trimmed = next.takeLast(MAX_MESSAGES)
            _messages.value = trimmed
            val json = JSONArray().apply { trimmed.forEach { put(it.toJson()) } }
            runCatching { writeAtomicUtf8(fileFor(forAccountId), json.toString()) }
        }
    }

    fun clear(forAccountId: String?) {
        synchronized(lock) {
            if (forAccountId == null || this.accountId != forAccountId) return
            _messages.value = emptyList()
            fileFor(forAccountId).delete()
        }
    }

    private fun fileFor(uid: String): File =
        File(directory, "account-${sha256Hex(uid.toByteArray(Charsets.UTF_8))}.json")

    companion object {
        private const val MAX_MESSAGES = 50
    }
}
