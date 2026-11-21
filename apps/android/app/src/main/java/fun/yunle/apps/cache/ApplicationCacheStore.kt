package `fun`.yunle.apps.cache

import android.content.SharedPreferences
import `fun`.yunle.apps.CatalogApp
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
import java.util.Locale
import java.util.UUID

internal object ApplicationStaticResourcePolicy {
    private val ALLOWED_HOSTS = setOf("admin.yunle.fun", "support.yunle.fun")
    private val ALLOWED_EXTENSIONS = setOf(
        "js", "css", "woff", "woff2", "png", "jpg", "jpeg", "webp", "svg", "avif", "ico",
    )
    private val NUXT_PATH_RE = Regex("^/_nuxt/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+\\.[A-Za-z0-9]+$")
    private val REF_RE = Regex("""["'(\`]((?:\./|/_nuxt/|https://)[^\s"'`<>\)]+\.(?:js|css|woff2?|png|jpe?g|webp|svg|avif|ico))["'`\)]""")

    fun origin(rawUrl: String): String? {
        val uri = runCatching { URI(rawUrl) }.getOrNull() ?: return null
        val host = uri.host?.lowercase(Locale.ROOT) ?: return null
        if (!uri.scheme.equals("https", ignoreCase = true) ||
            uri.rawUserInfo != null ||
            uri.port !in listOf(-1, 443) ||
            host !in ALLOWED_HOSTS
        ) {
            return null
        }
        return "https://$host/"
    }

    fun supports(app: CatalogApp): Boolean {
        val url = app.launchUrl ?: return false
        return origin(url) != null
    }

    fun permits(rawUrl: String, expectedOrigin: String): Boolean {
        val uri = runCatching { URI(rawUrl) }.getOrNull() ?: return false
        val originUri = runCatching { URI(expectedOrigin) }.getOrNull() ?: return false
        if (!uri.scheme.equals(originUri.scheme, ignoreCase = true) ||
            !uri.host.orEmpty().equals(originUri.host.orEmpty(), ignoreCase = true) ||
            uri.rawUserInfo != null ||
            uri.rawQuery != null ||
            uri.rawFragment != null ||
            rawUrl.contains("%")
        ) {
            return false
        }
        val path = uri.rawPath.orEmpty()
        if (!NUXT_PATH_RE.matches(path)) return false
        val ext = path.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return ext in ALLOWED_EXTENSIONS
    }

    fun isPublic(
        statusCode: Int,
        cacheControlHeader: String?,
        setCookieHeader: String?,
        varyHeader: String?,
    ): Boolean {
        if (statusCode != 200 || setCookieHeader != null) return false
        val directives = cacheControlHeader.orEmpty()
            .lowercase(Locale.ROOT)
            .split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if ("public" !in directives) return false
        val forbidden = directives.any { d ->
            val key = d.substringBefore('=').trim()
            key == "private" || key == "no-store" || key == "no-cache"
        }
        if (forbidden) return false
        val hasPositiveMaxAge = directives.any { d ->
            val parts = d.split('=', limit = 2)
            parts.size == 2 && parts[0].trim() == "max-age" && (parts[1].trim().toIntOrNull() ?: 0) > 0
        }
        if (!hasPositiveMaxAge) return false
        val varyForbidden = varyHeader.orEmpty()
            .lowercase(Locale.ROOT)
            .split(',')
            .map { it.trim() }
            .any { it == "*" || it == "cookie" || it == "authorization" }
        return !varyForbidden
    }

    fun references(text: String, baseUrl: String, expectedOrigin: String): List<String> {
        val baseUri = runCatching { URI(baseUrl) }.getOrNull() ?: return emptyList()
        return REF_RE.findAll(text).mapNotNull { match ->
            val raw = match.groupValues[1]
            val resolved = runCatching { baseUri.resolve(raw).toString() }.getOrNull() ?: return@mapNotNull null
            resolved.takeIf { permits(it, expectedOrigin) }
        }.distinct().toList()
    }
}

internal enum class ApplicationCacheError(val defaultMessage: String) {
    UNSUPPORTED("仅支持公开免费应用，或一等站点（admin/support）静态资源缓存。"),
    INVALID_ARCHIVE("缓存内容不完整或校验失败，请重新下载。"),
    TOO_LARGE("这个应用的离线缓存超过 25 MB，暂时无法保存。"),
    QUOTA_EXCEEDED("离线缓存已达到 200 MB 上限，请先清理部分应用。"),
    NOT_CACHEABLE("这个网站不允许保存离线缓存，请在线使用。"),
    DOWNLOAD_FAILED("下载未完成，请检查网络后重试。原有缓存会继续保留。");
}

internal class ApplicationCacheException(
    val error: ApplicationCacheError,
    cause: Throwable? = null,
) : Exception(error.defaultMessage, cause)

internal data class ApplicationCacheEntry(
    val id: String,
    val appId: String,
    val appName: String,
    val launchUrl: String,
    val downloadedAtMillis: Long,
    val byteCount: Int,
    val resourceCount: Int,
    val kind: String? = null,
) {
    val isStaticResources: Boolean get() = kind == KIND_STATIC_RESOURCES

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("appId", appId)
        .put("appName", appName)
        .put("launchUrl", launchUrl)
        .put("downloadedAtMillis", downloadedAtMillis)
        .put("byteCount", byteCount)
        .put("resourceCount", resourceCount)
        .put("kind", kind ?: JSONObject.NULL)

    companion object {
        const val KIND_STATIC_RESOURCES = "public-resources-v1"

        fun fromJson(json: JSONObject): ApplicationCacheEntry? {
            val id = json.readString("id") ?: return null
            val appId = json.readString("appId") ?: return null
            val appName = json.readString("appName") ?: return null
            val launchUrl = json.readString("launchUrl") ?: return null
            val ts = json.optLong("downloadedAtMillis", -1L)
            val byteCount = json.optInt("byteCount", -1)
            val resCount = json.optInt("resourceCount", -1)
            if (id.length != 64 || ts <= 0L || byteCount <= 0 || resCount <= 0) return null
            return ApplicationCacheEntry(
                id = id,
                appId = appId,
                appName = appName,
                launchUrl = launchUrl,
                downloadedAtMillis = ts,
                byteCount = byteCount,
                resourceCount = resCount,
                kind = json.readString("kind"),
            )
        }

        fun key(app: CatalogApp): String {
            val launch = app.launchUrl.orEmpty()
            val staticOrigin = ApplicationStaticResourcePolicy.origin(launch)
            val parts = if (staticOrigin != null) {
                JSONArray().put(KIND_STATIC_RESOURCES).put(staticOrigin)
            } else {
                JSONArray().put(app.id).put("public").put(launch)
            }
            return sha256Hex(parts.toString().toByteArray(Charsets.UTF_8))
        }

        fun supports(app: CatalogApp): Boolean {
            val launch = app.launchUrl ?: return false
            if (ApplicationStaticResourcePolicy.origin(launch) != null) return true
            return app.accessMode == "public" &&
                !app.requiresMembership &&
                app.coinCost == 0 &&
                (app.audience == null || app.audience == "public")
        }
    }
}

internal class ApplicationCacheRepository(
    private val directory: File,
    private val totalLimitBytes: Long = DEFAULT_TOTAL_LIMIT_BYTES,
) {
    private val lock = Any()

    fun entries(): List<ApplicationCacheEntry> = synchronized(lock) {
        if (!directory.isDirectory) return emptyList()
        val files = directory.listFiles { _, name -> name.endsWith(".meta.json") }.orEmpty()
        files.mapNotNull { metaFile ->
            runCatching {
                val root = JSONObject(metaFile.readText(Charsets.UTF_8))
                val entry = ApplicationCacheEntry.fromJson(root.getJSONObject("entry")) ?: return@runCatching null
                val expectedId = metaFile.name.removeSuffix(".meta.json")
                val bin = File(directory, "$expectedId.bin")
                if (entry.id != expectedId || !bin.isFile) return@runCatching null
                entry
            }.getOrNull()
        }.sortedByDescending { it.downloadedAtMillis }
    }

    fun readPayload(app: CatalogApp): ByteArray? = synchronized(lock) {
        if (!ApplicationCacheEntry.supports(app)) return null
        val id = ApplicationCacheEntry.key(app)
        val metaFile = File(directory, "$id.meta.json")
        val binFile = File(directory, "$id.bin")
        if (!metaFile.isFile || !binFile.isFile) return null
        val root = runCatching { JSONObject(metaFile.readText(Charsets.UTF_8)) }.getOrNull()
            ?: throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        val entry = ApplicationCacheEntry.fromJson(root.optJSONObject("entry") ?: return null)
            ?: throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        val expectedDigest = root.readString("sha256")
            ?: throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        if (entry.id != id || (!entry.isStaticResources && entry.launchUrl != app.launchUrl)) {
            throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        }
        val bytes = binFile.readBytes()
        if (bytes.size != entry.byteCount || sha256Hex(bytes) != expectedDigest) {
            metaFile.delete()
            binFile.delete()
            throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        }
        return bytes
    }

    fun save(
        payloadBytes: ByteArray,
        resourceCount: Int,
        app: CatalogApp,
        kind: String? = null,
        nowMillis: Long = System.currentTimeMillis(),
    ): ApplicationCacheEntry = synchronized(lock) {
        if (!ApplicationCacheEntry.supports(app) || app.launchUrl == null) {
            throw ApplicationCacheException(ApplicationCacheError.UNSUPPORTED)
        }
        if (payloadBytes.isEmpty() || resourceCount <= 0) {
            throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        }
        if (payloadBytes.size > MAX_ARCHIVE_BYTES) {
            throw ApplicationCacheException(ApplicationCacheError.TOO_LARGE)
        }
        val id = ApplicationCacheEntry.key(app)
        val launch = if (kind == ApplicationCacheEntry.KIND_STATIC_RESOURCES) {
            ApplicationStaticResourcePolicy.origin(app.launchUrl) ?: app.launchUrl
        } else {
            app.launchUrl
        }
        val existingOtherBytes = entries().filterNot { it.id == id }.sumOf { it.byteCount.toLong() }
        if (existingOtherBytes + payloadBytes.size > totalLimitBytes) {
            throw ApplicationCacheException(ApplicationCacheError.QUOTA_EXCEEDED)
        }
        val entry = ApplicationCacheEntry(
            id = id,
            appId = app.id,
            appName = app.name,
            launchUrl = launch,
            downloadedAtMillis = nowMillis,
            byteCount = payloadBytes.size,
            resourceCount = resourceCount,
            kind = kind,
        )
        val meta = JSONObject()
            .put("version", 1)
            .put("sha256", sha256Hex(payloadBytes))
            .put("entry", entry.toJson())
        directory.mkdirs()
        val binTarget = File(directory, "$id.bin")
        val tmpBin = File(directory, ".$id.${UUID.randomUUID()}.bin.tmp")
        try {
            tmpBin.writeBytes(payloadBytes)
            Files.move(tmpBin.toPath(), binTarget.toPath(), StandardCopyOption.REPLACE_EXISTING)
            writeAtomicUtf8(File(directory, "$id.meta.json"), meta.toString())
        } finally {
            if (tmpBin.exists()) tmpBin.delete()
        }
        entry
    }

    fun remove(id: String) = synchronized(lock) {
        if (id.length != 64 || !id.all { it in '0'..'9' || it in 'a'..'f' }) {
            throw ApplicationCacheException(ApplicationCacheError.INVALID_ARCHIVE)
        }
        File(directory, "$id.meta.json").delete()
        File(directory, "$id.bin").delete()
    }

    fun removeAll() = synchronized(lock) {
        if (directory.exists()) directory.deleteRecursively()
    }

    companion object {
        const val MAX_ARCHIVE_BYTES = 25 * 1024 * 1024
        const val DEFAULT_TOTAL_LIMIT_BYTES = 200L * 1024 * 1024
    }
}

internal interface ApplicationArchiveDownloading {
    suspend fun download(app: CatalogApp, onProgress: (Float) -> Unit): Pair<ByteArray, Int>
}

internal class HttpApplicationArchiveDownloader : ApplicationArchiveDownloading {
    override suspend fun download(app: CatalogApp, onProgress: (Float) -> Unit): Pair<ByteArray, Int> =
        withContext(Dispatchers.IO) {
            val urlString = app.launchUrl ?: throw ApplicationCacheException(ApplicationCacheError.UNSUPPORTED)
            onProgress(0.15f)
            val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                instanceFollowRedirects = false
                useCaches = false
                connectTimeout = 20_000
                readTimeout = 30_000
                setRequestProperty("Accept", "text/html,application/xhtml+xml,application/json")
            }
            try {
                val status = conn.responseCode
                val cacheControl = conn.getHeaderField("Cache-Control")
                val setCookie = conn.getHeaderField("Set-Cookie")
                val vary = conn.getHeaderField("Vary")
                if (!ApplicationStaticResourcePolicy.isPublic(status, cacheControl, setCookie, vary)) {
                    throw ApplicationCacheException(ApplicationCacheError.NOT_CACHEABLE)
                }
                val bytes = readCappedBytes(conn)
                onProgress(1.0f)
                bytes to 1
            } catch (e: ApplicationCacheException) {
                throw e
            } catch (t: Throwable) {
                throw ApplicationCacheException(ApplicationCacheError.DOWNLOAD_FAILED, t)
            } finally {
                conn.disconnect()
            }
        }

    private fun readCappedBytes(conn: HttpURLConnection): ByteArray {
        conn.inputStream.use { stream ->
            val buf = ByteArray(8192)
            val out = ByteArrayOutputStream()
            while (true) {
                val n = stream.read(buf)
                if (n == -1) break
                if (out.size() + n > ApplicationCacheRepository.MAX_ARCHIVE_BYTES) {
                    throw ApplicationCacheException(ApplicationCacheError.TOO_LARGE)
                }
                out.write(buf, 0, n)
            }
            return out.toByteArray()
        }
    }
}

internal class ApplicationCacheStore(
    private val repository: ApplicationCacheRepository,
    private val prefs: SharedPreferences,
    private val downloader: ApplicationArchiveDownloading = HttpApplicationArchiveDownloader(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var downloadJob: Job? = null

    private val _entries = MutableStateFlow<List<ApplicationCacheEntry>>(emptyList())
    val entries: StateFlow<List<ApplicationCacheEntry>> = _entries.asStateFlow()

    private val _downloadingId = MutableStateFlow<String?>(null)
    val downloadingId: StateFlow<String?> = _downloadingId.asStateFlow()

    private val _downloadingName = MutableStateFlow<String?>(null)
    val downloadingName: StateFlow<String?> = _downloadingName.asStateFlow()

    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress.asStateFlow()

    private val _isClearing = MutableStateFlow(false)
    val isClearing: StateFlow<Boolean> = _isClearing.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _automaticUpdatesEnabled = MutableStateFlow(prefs.getBoolean(KEY_AUTO_UPDATES, false))
    val automaticUpdatesEnabled: StateFlow<Boolean> = _automaticUpdatesEnabled.asStateFlow()

    private val _wifiOnly = MutableStateFlow(prefs.getBoolean(KEY_WIFI_ONLY, true))
    val wifiOnly: StateFlow<Boolean> = _wifiOnly.asStateFlow()

    private val _updatesReady = MutableStateFlow<Set<String>>(emptySet())
    val updatesReady: StateFlow<Set<String>> = _updatesReady.asStateFlow()

    private val runningRevisions = linkedMapOf<String, Long>()

    init {
        refresh()
    }

    val totalBytes: Long get() = _entries.value.sumOf { it.byteCount.toLong() }

    fun entry(app: CatalogApp): ApplicationCacheEntry? =
        _entries.value.firstOrNull { it.id == ApplicationCacheEntry.key(app) }

    fun refresh() {
        _entries.value = repository.entries()
    }

    fun setAutomaticUpdatesEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_AUTO_UPDATES, enabled).apply()
        _automaticUpdatesEnabled.value = enabled
    }

    fun setWifiOnly(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_WIFI_ONLY, enabled).apply()
        _wifiOnly.value = enabled
    }

    fun markSessionStarted(app: CatalogApp, revisionMillis: Long?) {
        val id = ApplicationCacheEntry.key(app)
        runningRevisions[id] = revisionMillis ?: Long.MIN_VALUE
        recomputeReady()
    }

    fun markSessionEnded(app: CatalogApp) {
        val id = ApplicationCacheEntry.key(app)
        runningRevisions.remove(id)
        _updatesReady.value = _updatesReady.value - id
    }

    fun download(app: CatalogApp) {
        if (_downloadingId.value != null || _isClearing.value || !ApplicationCacheEntry.supports(app)) return
        val id = ApplicationCacheEntry.key(app)
        _downloadingId.value = id
        _downloadingName.value = app.name
        _progress.value = 0f
        _message.value = null

        downloadJob = scope.launch {
            try {
                val (bytes, count) = downloader.download(app) { p -> _progress.value = p }
                val kind = if (ApplicationStaticResourcePolicy.supports(app)) {
                    ApplicationCacheEntry.KIND_STATIC_RESOURCES
                } else {
                    null
                }
                withContext(Dispatchers.IO) {
                    repository.save(bytes, count, app, kind = kind)
                    _entries.value = repository.entries()
                }
                recomputeReady()
                _message.value = "缓存已保存。下次重新打开应用时使用新缓存。"
            } catch (_: CancellationException) {
                _message.value = "已取消下载，原有缓存继续保留。"
            } catch (t: Throwable) {
                _message.value = (t as? ApplicationCacheException)?.error?.defaultMessage
                    ?: ApplicationCacheError.DOWNLOAD_FAILED.defaultMessage
            } finally {
                _downloadingId.value = null
                _downloadingName.value = null
                downloadJob = null
            }
        }
    }

    fun cancelDownload() {
        downloadJob?.cancel()
    }

    fun clear(id: String? = null) {
        if (_isClearing.value) return
        _isClearing.value = true
        _message.value = null
        val activeJob = downloadJob
        activeJob?.cancel()
        scope.launch {
            activeJob?.join()
            try {
                withContext(Dispatchers.IO) {
                    if (id != null) {
                        repository.remove(id)
                        _updatesReady.value = _updatesReady.value - id
                    } else {
                        repository.removeAll()
                        _updatesReady.value = emptySet()
                    }
                    _entries.value = repository.entries()
                }
                _message.value = "离线缓存已清理。下次重新打开应用时从网络加载，不会删除登录状态与用户数据。"
            } catch (_: Throwable) {
                _message.value = "缓存未能清理，请稍后重试。"
            } finally {
                _isClearing.value = false
            }
        }
    }

    private fun recomputeReady() {
        val ready = _entries.value.mapNotNull { entry ->
            val started = runningRevisions[entry.id] ?: return@mapNotNull null
            entry.id.takeIf { entry.downloadedAtMillis > started }
        }.toSet()
        _updatesReady.value = ready
    }

    companion object {
        private const val KEY_AUTO_UPDATES = "applicationCache.automaticUpdates"
        private const val KEY_WIFI_ONLY = "applicationCache.wifiOnly"
    }
}
