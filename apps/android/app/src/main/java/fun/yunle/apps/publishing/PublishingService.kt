package `fun`.yunle.apps.publishing

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.games.sha256Hex
import `fun`.yunle.apps.games.writeAtomicUtf8
import `fun`.yunle.apps.readString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID

internal interface PublishingServing {
    suspend fun access(identity: AuthorizedAccount): PublishingAccess
    suspend fun applications(identity: AuthorizedAccount): List<ManagedApplication>
    suspend fun save(
        id: String?,
        draft: ApplicationDraft,
        writeVersion: String? = null,
        identity: AuthorizedAccount,
    ): ManagedApplication

    suspend fun submit(
        id: String,
        makePublic: Boolean,
        shortName: String,
        writeVersion: String,
        identity: AuthorizedAccount,
    ): MarketSubmissionReceipt

    suspend fun delist(id: String, writeVersion: String, identity: AuthorizedAccount)
    suspend fun upload(pngBytes: ByteArray, role: ApplicationIconRole, identity: AuthorizedAccount): String
}

internal class PublishingService(
    private val origin: String = "https://apps.yunle.fun",
) : PublishingServing {
    private val baseUrl = origin.trimEnd('/')

    override suspend fun access(identity: AuthorizedAccount): PublishingAccess {
        val json = request("$baseUrl/api/apps/access", identity = identity)
        return PublishingAccess.fromJson(json)
    }

    override suspend fun applications(identity: AuthorizedAccount): List<ManagedApplication> {
        val json = request("$baseUrl/api/apps/mine", identity = identity)
        val arr = json.optJSONArray("items") ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
        if (arr.length() > 200) throw PublishingException(PublishingError.INVALID_RESPONSE)
        val items = (0 until arr.length()).map { idx ->
            val obj = arr.optJSONObject(idx) ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
            ManagedApplication.fromJson(obj).also { it.validate(owner = identity.userID) }
        }
        if (items.map { it.id }.toSet().size != items.size) {
            throw PublishingException(PublishingError.INVALID_RESPONSE)
        }
        return items
    }

    override suspend fun save(
        id: String?,
        draft: ApplicationDraft,
        writeVersion: String?,
        identity: AuthorizedAccount,
    ): ManagedApplication {
        if (id != null && (writeVersion == null || !PublishingValue.writeVersion(writeVersion))) {
            throw PublishingException(PublishingError.UNSUPPORTED_SERVER)
        }
        if (!draft.isValid) throw PublishingException(PublishingError.INVALID_INPUT)
        val url = if (id != null) {
            val seg = encodeSegment(id)
            "$baseUrl/api/apps/$seg/submissions"
        } else {
            "$baseUrl/api/apps/submissions"
        }
        val bodyBytes = draft.toSubmissionJson().toString().toByteArray(Charsets.UTF_8)
        val json = request(
            urlString = url,
            method = "POST",
            rawBody = bodyBytes,
            contentType = "application/json",
            writeVersion = writeVersion,
            identity = identity,
        )
        val appObj = json.optJSONObject("app") ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
        val subObj = json.optJSONObject("submission") ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
        val app = ManagedApplication.fromJson(appObj).also { it.validate(owner = identity.userID, expectedId = id) }
        val submission = ApplicationSubmission.fromJson(subObj)

        if (submission.appId != app.id ||
            submission.submitterUid != identity.userID ||
            app.latestSubmission?.submitterUid != identity.userID ||
            !PublishingValue.identifier(submission.id) ||
            submission.id != app.currentRevisionId ||
            submission.id != app.latestSubmission?.id ||
            submission.reviewStatus != ApplicationReviewStatus.DRAFT ||
            app.latestSubmission?.reviewStatus != ApplicationReviewStatus.DRAFT ||
            app.writeVersion == null ||
            submission.revision <= 0 ||
            app.latestSubmission?.revision != submission.revision ||
            app.publishedSubmissionId != submission.id ||
            app.publicationStatus != ApplicationPublicationStatus.PUBLISHED ||
            app.draft.name.trim() != draft.name.trim() ||
            app.draft.slug != draft.slug.trim() ||
            app.draft.audience != draft.audience
        ) {
            throw PublishingException(PublishingError.INVALID_RESPONSE)
        }
        return app
    }

    override suspend fun submit(
        id: String,
        makePublic: Boolean,
        shortName: String,
        writeVersion: String,
        identity: AuthorizedAccount,
    ): MarketSubmissionReceipt {
        val seg = encodeSegment(id)
        if (shortName.isNotEmpty() && !PublishingValue.slug(shortName)) {
            throw PublishingException(PublishingError.INVALID_INPUT)
        }
        val body = JSONObject()
            .put("makePublic", makePublic)
            .put("shortName", shortName)
            .toString()
            .toByteArray(Charsets.UTF_8)
        val json = request(
            urlString = "$baseUrl/api/apps/$seg/public-market",
            method = "POST",
            rawBody = body,
            contentType = "application/json",
            writeVersion = writeVersion,
            identity = identity,
        )
        val appId = json.readString("appId") ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
        val subId = json.readString("submissionId") ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
        val status = ApplicationReviewStatus.fromKey(json.readString("reviewStatus"))
        if (appId != id || !PublishingValue.identifier(subId) || status != ApplicationReviewStatus.PENDING) {
            throw PublishingException(PublishingError.INVALID_RESPONSE)
        }
        return MarketSubmissionReceipt(appId = appId, submissionId = subId, reviewStatus = status)
    }

    override suspend fun delist(id: String, writeVersion: String, identity: AuthorizedAccount) {
        val seg = encodeSegment(id)
        val json = request(
            urlString = "$baseUrl/api/apps/$seg",
            method = "DELETE",
            writeVersion = writeVersion,
            identity = identity,
        )
        if (json.opt("success") != true) throw PublishingException(PublishingError.INVALID_RESPONSE)
    }

    override suspend fun upload(
        pngBytes: ByteArray,
        role: ApplicationIconRole,
        identity: AuthorizedAccount,
    ): String {
        if (!ApplicationIconNormalizer.isNormalized1024Png(pngBytes)) {
            throw PublishingException(PublishingError.INVALID_INPUT)
        }
        val boundary = "YunleFun-${UUID.randomUUID()}"
        val out = ByteArrayOutputStream()
        out.write("--$boundary\r\nContent-Disposition: form-data; name=\"assetRole\"\r\n\r\n${role.key}\r\n".toByteArray(Charsets.UTF_8))
        out.write("--$boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"${role.key}.png\"\r\nContent-Type: image/png\r\n\r\n".toByteArray(Charsets.UTF_8))
        out.write(pngBytes)
        out.write("\r\n--$boundary--\r\n".toByteArray(Charsets.UTF_8))

        val json = request(
            urlString = "$baseUrl/api/apps/icon-assets",
            method = "POST",
            rawBody = out.toByteArray(),
            contentType = "multipart/form-data; boundary=$boundary",
            identity = identity,
        )
        val fileId = json.readString("fileID") ?: throw PublishingException(PublishingError.INVALID_RESPONSE)
        val returnedRole = json.readString("role")
        val w = json.optInt("width", -1)
        val h = json.optInt("height", -1)
        if (returnedRole != role.key || w != 1024 || h != 1024 || !fileId.startsWith("cloud://") || !PublishingValue.iconSource(fileId)) {
            throw PublishingException(PublishingError.INVALID_RESPONSE)
        }
        return fileId
    }

    private fun encodeSegment(id: String): String {
        if (!PublishingValue.identifier(id)) throw PublishingException(PublishingError.INVALID_INPUT)
        return URLEncoder.encode(id, Charsets.UTF_8.name()).replace("+", "%20")
    }

    private suspend fun request(
        urlString: String,
        method: String = "GET",
        rawBody: ByteArray? = null,
        contentType: String? = null,
        writeVersion: String? = null,
        identity: AuthorizedAccount,
    ): JSONObject = withContext(Dispatchers.IO) {
        if (writeVersion != null && !PublishingValue.writeVersion(writeVersion)) {
            throw PublishingException(PublishingError.UNSUPPORTED_SERVER)
        }
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 25_000
            readTimeout = 45_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
            if (writeVersion != null) {
                setRequestProperty("If-Match", "\"$writeVersion\"")
            }
            if (rawBody != null) {
                doOutput = true
                if (contentType != null) setRequestProperty("Content-Type", contentType)
            }
        }
        try {
            if (rawBody != null) {
                conn.outputStream.use { it.write(rawBody) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val out = ByteArrayOutputStream()
            stream?.use { input ->
                val buf = ByteArray(8192)
                while (true) {
                    val count = input.read(buf)
                    if (count == -1) break
                    if (out.size() + count > 4 * 1024 * 1024) {
                        throw PublishingException(PublishingError.INVALID_RESPONSE)
                    }
                    out.write(buf, 0, count)
                }
            }
            val text = out.toString(Charsets.UTF_8.name())
            when (code) {
                400 -> throw PublishingException(PublishingError.INVALID_INPUT)
                401 -> throw PublishingException(PublishingError.UNAUTHORIZED)
                403 -> {
                    val c = runCatching { JSONObject(text).optJSONObject("data")?.readString("code") }.getOrNull()
                    throw PublishingException(
                        when (c) {
                            "MEMBERSHIP_REQUIRED" -> PublishingError.MEMBERSHIP_REQUIRED
                            "WEB_BUILD_INVITE_NOT_MUTUAL" -> PublishingError.WEB_BUILD_INVITE_NOT_MUTUAL
                            "WEB_BUILD_INVITE_PEER_UNAVAILABLE" -> PublishingError.WEB_BUILD_INVITE_PEER_UNAVAILABLE
                            else -> PublishingError.FORBIDDEN
                        },
                    )
                }
                404 -> throw PublishingException(PublishingError.NOT_FOUND)
                409 -> {
                    val c = runCatching { JSONObject(text).optJSONObject("data")?.readString("code") }.getOrNull()
                    throw PublishingException(
                        when (c) {
                            "WEB_BUILD_ROOM_FULL" -> PublishingError.WEB_BUILD_ROOM_FULL
                            "WEB_BUILD_ALREADY_JOINED" -> PublishingError.WEB_BUILD_ALREADY_JOINED
                            else -> PublishingError.CONFLICT
                        },
                    )
                }
                412 -> throw PublishingException(PublishingError.CONFLICT)
                422 -> throw PublishingException(PublishingError.CONTENT_REJECTED)
                428 -> throw PublishingException(PublishingError.UNSUPPORTED_SERVER)
                429 -> throw PublishingException(PublishingError.THROTTLED)
                in 200..299 -> JSONObject(text)
                else -> throw PublishingException(PublishingError.UNAVAILABLE)
            }
        } catch (e: PublishingException) {
            throw e
        } catch (t: Throwable) {
            throw PublishingException(PublishingError.UNAVAILABLE, t)
        } finally {
            conn.disconnect()
        }
    }
}

internal object ApplicationIconNormalizer {
    private val PNG_SIG = byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10)
    private val IHDR_1024 = byteArrayOf(0, 0, 4, 0, 0, 0, 4, 0)

    fun isNormalized1024Png(bytes: ByteArray): Boolean {
        if (bytes.size !in 24..(4 * 1024 * 1024)) return false
        for (i in PNG_SIG.indices) {
            if (bytes[i] != PNG_SIG[i]) return false
        }
        for (i in IHDR_1024.indices) {
            if (bytes[16 + i] != IHDR_1024[i]) return false
        }
        return true
    }

    fun normalizeBitmapToPng1024(context: Context, uri: Uri): ByteArray {
        val rawBitmap = context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream)
        } ?: throw PublishingException(PublishingError.INVALID_INPUT)
        var square: Bitmap? = null
        var scaled: Bitmap? = null
        try {
            val side = minOf(rawBitmap.width, rawBitmap.height)
            if (side <= 0) throw PublishingException(PublishingError.INVALID_INPUT)
            val left = (rawBitmap.width - side) / 2
            val top = (rawBitmap.height - side) / 2
            square = Bitmap.createBitmap(rawBitmap, left, top, side, side)
            scaled = Bitmap.createScaledBitmap(square, 1024, 1024, true)
            val out = ByteArrayOutputStream()
            if (!scaled.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                throw PublishingException(PublishingError.INVALID_INPUT)
            }
            val pngBytes = out.toByteArray()
            if (!isNormalized1024Png(pngBytes)) throw PublishingException(PublishingError.INVALID_INPUT)
            return pngBytes
        } finally {
            if (scaled != null && scaled !== square && scaled !== rawBitmap) scaled.recycle()
            if (square != null && square !== rawBitmap) square.recycle()
            rawBitmap.recycle()
        }
    }
}

internal data class SavedApplicationDraft(
    val draft: ApplicationDraft,
    val baseRevision: String? = null,
    val baseUpdatedAtMillis: Long? = null,
    val baseWriteVersion: String? = null,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("draft", draft.toLocalJson())
        .put("baseRevision", baseRevision ?: JSONObject.NULL)
        .put("baseUpdatedAtMillis", baseUpdatedAtMillis ?: JSONObject.NULL)
        .put("baseWriteVersion", baseWriteVersion ?: JSONObject.NULL)

    companion object {
        fun fromJson(json: JSONObject): SavedApplicationDraft = SavedApplicationDraft(
            draft = ApplicationDraft.fromJson(json.getJSONObject("draft")),
            baseRevision = json.readString("baseRevision"),
            baseUpdatedAtMillis = if (json.has("baseUpdatedAtMillis") && !json.isNull("baseUpdatedAtMillis")) {
                json.optLong("baseUpdatedAtMillis")
            } else {
                null
            },
            baseWriteVersion = json.readString("baseWriteVersion"),
        )
    }
}

internal class ApplicationDraftVault(
    private val directory: File,
) {
    private val lock = Any()

    fun load(owner: String, appId: String?): SavedApplicationDraft? = synchronized(lock) {
        val target = fileFor(owner, appId)
        if (!target.isFile) return null
        return try {
            val root = JSONObject(target.readText(Charsets.UTF_8))
            val version = root.optInt("version", -1)
            val storedOwner = root.readString("owner")
            val storedAppId = root.readString("appId")
            if (version != 1 || storedOwner != owner || storedAppId != appId) {
                throw PublishingException(PublishingError.STORAGE)
            }
            SavedApplicationDraft.fromJson(root.getJSONObject("saved"))
        } catch (e: PublishingException) {
            throw e
        } catch (t: Throwable) {
            throw PublishingException(PublishingError.STORAGE, t)
        }
    }

    fun save(saved: SavedApplicationDraft, owner: String, appId: String?) = synchronized(lock) {
        load(owner, appId)
        val root = JSONObject()
            .put("version", 1)
            .put("owner", owner)
            .put("appId", appId ?: JSONObject.NULL)
            .put("saved", saved.toJson())
        try {
            writeAtomicUtf8(fileFor(owner, appId), root.toString())
        } catch (t: Throwable) {
            throw PublishingException(PublishingError.STORAGE, t)
        }
    }

    fun remove(owner: String, appId: String?) = synchronized(lock) {
        load(owner, appId)
        val target = fileFor(owner, appId)
        if (target.exists() && !target.delete()) {
            throw PublishingException(PublishingError.STORAGE)
        }
    }

    fun fileFor(owner: String, appId: String?): File {
        val raw = owner.toByteArray(Charsets.UTF_8) + byteArrayOf(0) + (appId ?: "__new__").toByteArray(Charsets.UTF_8)
        return File(directory, "${sha256Hex(raw)}.json")
    }
}
