package `fun`.yunle.apps.cache

import android.content.SharedPreferences
import `fun`.yunle.apps.games.NativeGame
import `fun`.yunle.apps.games.sha256Hex
import `fun`.yunle.apps.games.writeAtomicUtf8
import `fun`.yunle.apps.readString
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
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
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.util.Locale
import java.util.UUID

internal enum class NativeGameResourceCacheError(val defaultMessage: String) {
    INVALID_MANIFEST("游戏资源清单暂不可用，请在线开玩。"),
    INVALID_RESOURCE("游戏资源来源或格式不受支持，请在线开玩。"),
    TOO_LARGE("这款游戏的资源超过 25 MB，暂不支持准备，可直接在线开玩。"),
    NOT_PUBLIC("部分游戏资源不允许公共缓存，请在线开玩。"),
    INTEGRITY("游戏资源版本校验失败，请稍后重新准备。"),
    BUSY("正在处理游戏资源，请完成或取消后再试。"),
    QUOTA("游戏资源准备已达到 200 MB，请先清理部分资源。"),
    DOWNLOAD_FAILED("游戏资源下载失败，请检查网络后重试。");
}

internal class NativeGameResourceCacheException(
    val error: NativeGameResourceCacheError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal object NativeGameResourcePolicy {
    const val MAX_BYTES = 25 * 1024 * 1024
    const val MAX_TOTAL_BYTES = 200L * 1024 * 1024
    private val SHA256_RE = Regex("^[0-9a-f]{64}$")
    private val PATH_RE = Regex("^/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*$")

    private val MIME_TYPES: Map<String, Set<String>> = mapOf(
        "js" to setOf("application/javascript", "text/javascript"),
        "mjs" to setOf("application/javascript", "text/javascript"),
        "css" to setOf("text/css"),
        "wasm" to setOf("application/wasm", "application/octet-stream"),
        "woff" to setOf("font/woff", "application/font-woff"),
        "woff2" to setOf("font/woff2"),
        "ttf" to setOf("font/ttf", "application/x-font-ttf"),
        "otf" to setOf("font/otf"),
        "png" to setOf("image/png"),
        "jpg" to setOf("image/jpeg"),
        "jpeg" to setOf("image/jpeg"),
        "webp" to setOf("image/webp"),
        "avif" to setOf("image/avif"),
        "svg" to setOf("image/svg+xml"),
        "gif" to setOf("image/gif"),
        "ico" to setOf("image/x-icon", "image/vnd.microsoft.icon"),
        "mp3" to setOf("audio/mpeg"),
        "ogg" to setOf("audio/ogg", "application/ogg"),
        "wav" to setOf("audio/wav", "audio/x-wav"),
        "m4a" to setOf("audio/mp4"),
        "aac" to setOf("audio/aac"),
        "glb" to setOf("model/gltf-binary", "application/octet-stream"),
        "gltf" to setOf("model/gltf+json", "application/json"),
        "bin" to setOf("application/octet-stream"),
        "ktx2" to setOf("image/ktx2", "application/octet-stream"),
        "basis" to setOf("application/octet-stream"),
        "json" to setOf("application/json"),
    )

    fun isDigest(value: String): Boolean = SHA256_RE.matches(value)

    fun publicUrl(raw: String, allowLocalHttp: Boolean = false): URI? {
        if (raw.any { it.code <= 32 || it.code in 127..159 } || raw.contains("%")) return null
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val host = uri.host?.lowercase(Locale.ROOT) ?: return null
        val validOrigin = (uri.scheme.equals("https", true) && uri.port in listOf(-1, 443) &&
            host in setOf("play.yunle.fun", "assets.play.yunle.fun")) ||
            (allowLocalHttp && uri.scheme.equals("http", true) && host == "127.0.0.1")
        if (!validOrigin || uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null) {
            return null
        }
        return uri
    }

    fun manifestUrl(raw: String, gameId: String, allowLocalHttp: Boolean = false): Boolean {
        if (!NativeGame.validIdentifier(gameId)) return false
        val uri = publicUrl(raw, allowLocalHttp) ?: return false
        val host = uri.host?.lowercase(Locale.ROOT)
        return (host == "play.yunle.fun" || (allowLocalHttp && host == "127.0.0.1")) &&
            uri.rawPath == "/native/resources/$gameId-v1.json"
    }

    fun resourceUrl(raw: String, gameId: String, allowLocalHttp: Boolean = false): Boolean {
        if (!NativeGame.validIdentifier(gameId)) return false
        val uri = publicUrl(raw, allowLocalHttp) ?: return false
        val path = uri.rawPath.orEmpty()
        if (!PATH_RE.matches(path)) return false
        val segments = path.split('/')
        if (segments.any { it == "." || it == ".." }) return false
        val host = uri.host?.lowercase(Locale.ROOT)
        val permittedPath = if (host == "play.yunle.fun" || (allowLocalHttp && host == "127.0.0.1")) {
            path.startsWith("/_nuxt/") || path.startsWith("/games/$gameId/")
        } else {
            path.startsWith("/games/$gameId/")
        }
        if (!permittedPath) return false
        val ext = path.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return ext in MIME_TYPES
    }

    fun acceptsType(contentType: String, rawUrl: String): Boolean {
        val mime = contentType.substringBefore(';').trim().lowercase(Locale.ROOT)
        val ext = runCatching { URI(rawUrl).rawPath }.getOrNull()
            ?.substringAfterLast('.', "")
            ?.lowercase(Locale.ROOT)
            ?: return false
        return MIME_TYPES[ext]?.contains(mime) == true
    }

    fun primaryMimeType(rawUrl: String): String {
        val ext = runCatching { URI(rawUrl).rawPath }.getOrNull()
            ?.substringAfterLast('.', "")
            ?.lowercase(Locale.ROOT)
            .orEmpty()
        return MIME_TYPES[ext]?.firstOrNull() ?: "application/octet-stream"
    }
}

internal data class NativeGameResourceManifest(
    val schemaVersion: Int,
    val gameId: String,
    val version: String,
    val generatedAt: String,
    val totalBytes: Int,
    val resources: List<Resource>,
) {
    data class Resource(
        val url: String,
        val sha256: String,
        val byteCount: Int,
        val contentType: String,
        val required: Boolean,
    )

    fun validate(gameId: String, allowLocalHttp: Boolean = false) {
        val validDate = runCatching { Instant.parse(generatedAt) }.isSuccess
        if (schemaVersion != 1 ||
            this.gameId != gameId ||
            !NativeGame.validIdentifier(gameId) ||
            !NativeGameResourcePolicy.isDigest(version) ||
            !validDate ||
            resources.isEmpty() ||
            resources.size > 512 ||
            totalBytes <= 0
        ) {
            throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST)
        }
        if (totalBytes > NativeGameResourcePolicy.MAX_BYTES) {
            throw NativeGameResourceCacheException(NativeGameResourceCacheError.TOO_LARGE)
        }
        var sum = 0
        val seen = mutableSetOf<String>()
        for (res in resources) {
            if (!NativeGameResourcePolicy.resourceUrl(res.url, gameId, allowLocalHttp) ||
                !res.required ||
                !NativeGameResourcePolicy.isDigest(res.sha256) ||
                res.byteCount <= 0 ||
                res.byteCount > NativeGameResourcePolicy.MAX_BYTES ||
                !NativeGameResourcePolicy.acceptsType(res.contentType, res.url) ||
                !seen.add(res.url)
            ) {
                throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_RESOURCE)
            }
            sum += res.byteCount
            if (sum > NativeGameResourcePolicy.MAX_BYTES) {
                throw NativeGameResourceCacheException(NativeGameResourceCacheError.TOO_LARGE)
            }
        }
        if (sum != totalBytes) {
            throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST)
        }
    }

    companion object {
        fun decode(
            payload: String,
            manifestUrl: String,
            gameId: String,
            allowLocalHttp: Boolean = false,
        ): NativeGameResourceManifest {
            if (payload.toByteArray(Charsets.UTF_8).size > 524_288 ||
                !NativeGameResourcePolicy.manifestUrl(manifestUrl, gameId, allowLocalHttp)
            ) {
                throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST)
            }
            val root = runCatching { JSONObject(payload) }.getOrNull()
                ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST)
            val arr = root.optJSONArray("resources")
                ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST)
            val resources = (0 until arr.length()).map { idx ->
                val obj = arr.optJSONObject(idx)
                    ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST)
                Resource(
                    url = obj.readString("url")
                        ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                    sha256 = obj.readString("sha256")
                        ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                    byteCount = obj.optInt("byteCount", -1),
                    contentType = obj.readString("contentType")
                        ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                    required = obj.opt("required") as? Boolean
                        ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                )
            }
            return NativeGameResourceManifest(
                schemaVersion = root.optInt("schemaVersion", -1),
                gameId = root.readString("gameId")
                    ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                version = root.readString("version")
                    ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                generatedAt = root.readString("generatedAt")
                    ?: throw NativeGameResourceCacheException(NativeGameResourceCacheError.INVALID_MANIFEST),
                totalBytes = root.optInt("totalBytes", -1),
                resources = resources,
            ).also { it.validate(gameId, allowLocalHttp) }
        }
    }
}

internal data class NativeGameResourceCacheEntry(
    val gameId: String,
    val profileKey: String,
    val version: String,
    val byteCount: Int,
    val resourceCount: Int,
    val preparedAtMillis: Long,
) {
    val id: String get() = "$profileKey:$gameId"

    fun toJson(): JSONObject = JSONObject()
        .put("gameId", gameId)
        .put("profileKey", profileKey)
        .put("version", version)
        .put("byteCount", byteCount)
        .put("resourceCount", resourceCount)
        .put("preparedAtMillis", preparedAtMillis)

    companion object {
        fun fromJson(json: JSONObject): NativeGameResourceCacheEntry? {
            val gId = json.readString("gameId") ?: return null
            val pKey = json.readString("profileKey") ?: return null
            val ver = json.readString("version") ?: return null
            val bytes = json.optInt("byteCount", -1)
            val count = json.optInt("resourceCount", -1)
            val ts = json.optLong("preparedAtMillis", -1L)
            if (!NativeGame.validIdentifier(gId) ||
                pKey.isEmpty() ||
                !NativeGameResourcePolicy.isDigest(ver) ||
                bytes !in 1..NativeGameResourcePolicy.MAX_BYTES ||
                count !in 1..512 ||
                ts <= 0L
            ) {
                return null
            }
            return NativeGameResourceCacheEntry(gId, pKey, ver, bytes, count, ts)
        }
    }
}

internal data class CachedWebResource(
    val file: File,
    val mimeType: String,
)

internal class NativeGameResourceCacheStore(
    private val rootDir: File,
    private val prefs: SharedPreferences? = null,
    private val allowLocalHttpForTesting: Boolean = false,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val lock = Any()
    private var activeJob: Job? = null

    private val _entries = MutableStateFlow<List<NativeGameResourceCacheEntry>>(emptyList())
    val entries: StateFlow<List<NativeGameResourceCacheEntry>> = _entries.asStateFlow()

    private val _downloadingGameId = MutableStateFlow<String?>(null)
    val downloadingGameId: StateFlow<String?> = _downloadingGameId.asStateFlow()

    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress.asStateFlow()

    private val _isClearing = MutableStateFlow(false)
    val isClearing: StateFlow<Boolean> = _isClearing.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _wifiOnly = MutableStateFlow(prefs?.getBoolean(KEY_WIFI_ONLY, true) ?: true)
    val wifiOnly: StateFlow<Boolean> = _wifiOnly.asStateFlow()

    init {
        loadEntriesFromDisk()
    }

    fun setWifiOnly(enabled: Boolean) {
        prefs?.edit()?.putBoolean(KEY_WIFI_ONLY, enabled)?.apply()
        _wifiOnly.value = enabled
    }

    fun entry(gameId: String, profileKey: String): NativeGameResourceCacheEntry? =
        _entries.value.firstOrNull { it.gameId == gameId && it.profileKey == profileKey }

    fun openCachedResource(url: String, gameId: String, profileKey: String): CachedWebResource? {
        if (!NativeGameResourcePolicy.resourceUrl(url, gameId, allowLocalHttpForTesting)) return null
        val gameDir = gameFilesDir(profileKey, gameId)
        val mapFile = File(gameDir, "manifest-map.json")
        if (!mapFile.isFile) return null
        val map = runCatching { JSONObject(mapFile.readText(Charsets.UTF_8)) }.getOrNull() ?: return null
        val info = map.optJSONObject(url) ?: return null
        val fileName = info.readString("file") ?: return null
        val mimeType = info.readString("mime") ?: NativeGameResourcePolicy.primaryMimeType(url)
        val resourceFile = File(gameDir, fileName)
        return if (resourceFile.isFile) CachedWebResource(resourceFile, mimeType) else null
    }

    fun download(manifestUrl: String, gameId: String, profileKey: String) {
        if (_downloadingGameId.value != null || _isClearing.value) {
            _error.value = NativeGameResourceCacheError.BUSY.defaultMessage
            return
        }
        _downloadingGameId.value = gameId
        _progress.value = 0f
        _error.value = null
        activeJob = scope.launch {
            try {
                performDownload(manifestUrl, gameId, profileKey) { p -> _progress.value = p }
            } catch (_: CancellationException) {
                _error.value = null
            } catch (e: NativeGameResourceCacheException) {
                _error.value = e.error.defaultMessage
            } catch (_: Throwable) {
                _error.value = NativeGameResourceCacheError.DOWNLOAD_FAILED.defaultMessage
            } finally {
                _downloadingGameId.value = null
                activeJob = null
            }
        }
    }

    suspend fun downloadBlocking(manifestUrl: String, gameId: String, profileKey: String): NativeGameResourceCacheEntry =
        performDownload(manifestUrl, gameId, profileKey) { p -> _progress.value = p }

    fun cancelDownload() {
        activeJob?.cancel()
    }

    fun clear(gameId: String? = null, profileKey: String? = null) {
        if (_isClearing.value) return
        _isClearing.value = true
        _error.value = null
        val job = activeJob
        job?.cancel()
        scope.launch {
            job?.join()
            withContext(Dispatchers.IO) {
                synchronized(lock) {
                    val remaining = _entries.value.filterNot { entry ->
                        (gameId == null || entry.gameId == gameId) &&
                            (profileKey == null || entry.profileKey == profileKey)
                    }
                    if (gameId != null && profileKey != null) {
                        gameFilesDir(profileKey, gameId).deleteRecursively()
                    } else if (profileKey != null) {
                        File(rootDir, "files/$profileKey").deleteRecursively()
                    } else {
                        File(rootDir, "files").deleteRecursively()
                    }
                    persistEntriesLocked(remaining)
                }
            }
            _isClearing.value = false
        }
    }

    private suspend fun performDownload(
        manifestUrl: String,
        gameId: String,
        profileKey: String,
        onProgress: (Float) -> Unit,
    ): NativeGameResourceCacheEntry = withContext(Dispatchers.IO) {
        val (manifestBytes, _, _) = fetchPublicBytes(
            urlString = manifestUrl,
            maxBytes = 524_288,
            expectPublic = false,
            errorIfFail = NativeGameResourceCacheError.INVALID_MANIFEST,
        )
        val manifest = NativeGameResourceManifest.decode(
            payload = manifestBytes.toString(Charsets.UTF_8),
            manifestUrl = manifestUrl,
            gameId = gameId,
            allowLocalHttp = allowLocalHttpForTesting,
        )
        val otherBytes = synchronized(lock) {
            _entries.value.filterNot { it.gameId == gameId && it.profileKey == profileKey }
                .sumOf { it.byteCount.toLong() }
        }
        if (otherBytes + manifest.totalBytes > NativeGameResourcePolicy.MAX_TOTAL_BYTES) {
            throw NativeGameResourceCacheException(NativeGameResourceCacheError.QUOTA)
        }

        val stageDir = File(rootDir, "stage-${UUID.randomUUID()}")
        stageDir.mkdirs()
        try {
            val map = JSONObject()
            manifest.resources.forEachIndexed { idx, res ->
                val (bytes, contentType, headersPublic) = fetchPublicBytes(
                    urlString = res.url,
                    maxBytes = res.byteCount,
                    expectPublic = true,
                    errorIfFail = NativeGameResourceCacheError.DOWNLOAD_FAILED,
                )
                if (!headersPublic || !NativeGameResourcePolicy.acceptsType(contentType, res.url)) {
                    throw NativeGameResourceCacheException(NativeGameResourceCacheError.NOT_PUBLIC)
                }
                if (bytes.size != res.byteCount || sha256Hex(bytes) != res.sha256) {
                    throw NativeGameResourceCacheException(NativeGameResourceCacheError.INTEGRITY)
                }
                val fileName = "${res.sha256}.res"
                File(stageDir, fileName).writeBytes(bytes)
                val mime = contentType.substringBefore(';').trim().lowercase(Locale.ROOT)
                map.put(res.url, JSONObject().put("file", fileName).put("mime", mime))
                onProgress((idx + 1).toFloat() / manifest.resources.size.toFloat())
            }
            writeAtomicUtf8(File(stageDir, "manifest-map.json"), map.toString())

            val finalDir = gameFilesDir(profileKey, gameId)
            val entry = NativeGameResourceCacheEntry(
                gameId = gameId,
                profileKey = profileKey,
                version = manifest.version,
                byteCount = manifest.totalBytes,
                resourceCount = manifest.resources.size,
                preparedAtMillis = System.currentTimeMillis(),
            )
            synchronized(lock) {
                finalDir.parentFile?.mkdirs()
                if (finalDir.exists()) finalDir.deleteRecursively()
                Files.move(stageDir.toPath(), finalDir.toPath(), StandardCopyOption.REPLACE_EXISTING)
                val next = (_entries.value.filterNot { it.gameId == gameId && it.profileKey == profileKey } + entry)
                    .sortedByDescending { it.preparedAtMillis }
                persistEntriesLocked(next)
            }
            entry
        } finally {
            if (stageDir.exists()) stageDir.deleteRecursively()
        }
    }

    private fun fetchPublicBytes(
        urlString: String,
        maxBytes: Int,
        expectPublic: Boolean,
        errorIfFail: NativeGameResourceCacheError,
    ): Triple<ByteArray, String, Boolean> {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 20_000
            readTimeout = 30_000
        }
        try {
            val status = conn.responseCode
            if (status != 200) throw NativeGameResourceCacheException(errorIfFail)
            val contentType = conn.contentType.orEmpty()
            val isPub = if (expectPublic) {
                ApplicationStaticResourcePolicy.isPublic(
                    statusCode = status,
                    cacheControlHeader = conn.getHeaderField("Cache-Control"),
                    setCookieHeader = conn.getHeaderField("Set-Cookie"),
                    varyHeader = conn.getHeaderField("Vary"),
                )
            } else {
                true
            }
            val bytes = conn.inputStream.use { stream ->
                val buf = ByteArray(8192)
                val out = ByteArrayOutputStream()
                while (true) {
                    val count = stream.read(buf)
                    if (count == -1) break
                    if (out.size() + count > maxBytes) {
                        throw NativeGameResourceCacheException(NativeGameResourceCacheError.INTEGRITY)
                    }
                    out.write(buf, 0, count)
                }
                out.toByteArray()
            }
            return Triple(bytes, contentType, isPub)
        } finally {
            conn.disconnect()
        }
    }

    private fun gameFilesDir(profileKey: String, gameId: String): File =
        File(rootDir, "files/$profileKey/$gameId")

    private fun loadEntriesFromDisk() {
        synchronized(lock) {
            val index = File(rootDir, "index.json")
            if (!index.isFile) return
            val decoded = runCatching {
                val arr = JSONArray(index.readText(Charsets.UTF_8))
                (0 until arr.length()).mapNotNull { i ->
                    arr.optJSONObject(i)?.let(NativeGameResourceCacheEntry::fromJson)
                }.filter { gameFilesDir(it.profileKey, it.gameId).isDirectory }
            }.getOrDefault(emptyList())
            _entries.value = decoded
        }
    }

    private fun persistEntriesLocked(next: List<NativeGameResourceCacheEntry>) {
        _entries.value = next
        val arr = JSONArray().apply { next.forEach { put(it.toJson()) } }
        writeAtomicUtf8(File(rootDir, "index.json"), arr.toString())
    }

    companion object {
        private const val KEY_WIFI_ONLY = "nativeGameResources.wifiOnly"
    }
}
