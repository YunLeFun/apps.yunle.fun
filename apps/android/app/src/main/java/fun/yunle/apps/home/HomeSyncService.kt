package `fun`.yunle.apps.home

import `fun`.yunle.apps.account.AuthorizedAccount
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

internal interface HomeSyncServing {
    suspend fun load(identity: AuthorizedAccount): RemoteHomeScreen
    suspend fun save(write: HomeScreenWrite, identity: AuthorizedAccount): RemoteHomeScreen
}

internal class HomeSyncService(
    private val origin: String = DEFAULT_ORIGIN,
) : HomeSyncServing {
    private val endpoint: String = "${origin.trimEnd('/')}/api/home-screen"
    private val readEndpoint: String = "$endpoint?schema=${HomeScreenWrite.SCHEMA_VERSION}"

    override suspend fun load(identity: AuthorizedAccount): RemoteHomeScreen =
        request(identity = identity, write = null)

    override suspend fun save(write: HomeScreenWrite, identity: AuthorizedAccount): RemoteHomeScreen {
        write.configuration.validate()
        val saved = request(identity = identity, write = write)
        if (!saved.carriesSources) {
            throw HomeSyncException(HomeSyncError.UNSUPPORTED_SCHEMA)
        }
        if (saved.revision == null || !write.configuration.matches(saved)) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }
        return saved
    }

    private suspend fun request(
        identity: AuthorizedAccount,
        write: HomeScreenWrite?,
    ): RemoteHomeScreen = withContext(Dispatchers.IO) {
        val targetUrl = URL(if (write == null) readEndpoint else endpoint)
        require(targetUrl.protocol.equals("https", ignoreCase = true))
        val connection = targetUrl.openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = if (write == null) "GET" else "PUT"
            connection.connectTimeout = 20_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Authorization", "Bearer ${identity.accessToken}")
            if (write != null) {
                val payload = write.toJson().toString().toByteArray(Charsets.UTF_8)
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setFixedLengthStreamingMode(payload.size)
                connection.outputStream.use { it.write(payload) }
            }

            val status = connection.responseCode
            val contentType = connection.contentType.orEmpty().substringBefore(';').trim().lowercase()
            val stream = if (status in 200..299) connection.inputStream else (connection.errorStream ?: connection.inputStream)
            val rawBytes = stream?.use { readBounded(it, MAXIMUM_RESPONSE_BYTES) }
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)

            if (contentType != "application/json") {
                throw HomeSyncException(
                    when (status) {
                        401 -> HomeSyncError.UNAUTHORIZED
                        403 -> HomeSyncError.FORBIDDEN
                        else -> HomeSyncError.INVALID_RESPONSE
                    },
                )
            }

            if (status == 401) throw HomeSyncException(HomeSyncError.UNAUTHORIZED)
            if (status == 403) throw HomeSyncException(HomeSyncError.FORBIDDEN)

            val json = runCatching { JSONObject(rawBytes.toString(Charsets.UTF_8)) }.getOrNull()
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)

            if (status == 409) {
                val data = json.optJSONObject("data")
                val code = data?.optString("code")
                val currentJson = data?.optJSONObject("current")
                if (code == "HOME_CONFLICT" && currentJson != null) {
                    val remote = RemoteHomeScreen.fromJson(currentJson)
                    throw HomeSyncException(HomeSyncError.CONFLICT, remoteConflict = remote)
                }
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }

            if (status !in 200..299) {
                throw HomeSyncException(HomeSyncError.UNAVAILABLE)
            }

            RemoteHomeScreen.fromJson(json)
        } catch (e: HomeSyncException) {
            throw e
        } catch (t: Throwable) {
            throw HomeSyncException(HomeSyncError.UNAVAILABLE, cause = t)
        } finally {
            connection.disconnect()
        }
    }

    private fun readBounded(stream: InputStream, maxBytes: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val read = stream.read(buffer)
            if (read <= 0) break
            total += read
            if (total > maxBytes) return null
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    companion object {
        const val DEFAULT_ORIGIN = "https://apps.yunle.fun"
        private const val MAXIMUM_RESPONSE_BYTES = 2 * 1024 * 1024
    }
}
