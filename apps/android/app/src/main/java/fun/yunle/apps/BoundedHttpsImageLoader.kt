package `fun`.yunle.apps

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.LruCache
import android.view.View
import android.widget.ImageView
import `fun`.yunle.apps.media.SvgIconDecoder
import `fun`.yunle.apps.media.SvgResourcePolicy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * Loads small, trusted-surface images without allowing redirects, unbounded
 * downloads, or an oversized compressed image to expand at decode time.
 */
internal object BoundedHttpsImageLoader {
    private val bitmapCache = LruCache<String, Bitmap>(32)

    suspend fun loadBitmap(source: String?): Bitmap? {
        val safeSource = source?.takeIf(::isHttpsImageUrl) ?: return null
        bitmapCache.get(safeSource)?.let { return it }
        return withContext(Dispatchers.IO) {
            bitmapCache.get(safeSource)?.let { return@withContext it }
            fetch(safeSource)?.also { bitmapCache.put(safeSource, it) }
        }
    }

    fun load(
        activity: Activity,
        source: String?,
        imageView: ImageView,
        fallback: View,
    ) {
        val safeSource = source?.takeIf(::isHttpsImageUrl) ?: return
        bitmapCache.get(safeSource)?.let { cached ->
            imageView.setImageBitmap(cached)
            imageView.visibility = View.VISIBLE
            fallback.visibility = View.GONE
            return
        }

        Thread {
            val bitmap = fetch(safeSource) ?: return@Thread
            bitmapCache.put(safeSource, bitmap)
            activity.runOnUiThread {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    imageView.setImageBitmap(bitmap)
                    imageView.visibility = View.VISIBLE
                    fallback.visibility = View.GONE
                }
            }
        }.start()
    }

    private fun isHttpsImageUrl(source: String): Boolean {
        val uri = Uri.parse(source)
        return uri.scheme?.lowercase() == "https" && !uri.host.isNullOrBlank()
    }

    private fun fetch(source: String): Bitmap? = runCatching {
        var currentUrl = URL(source)
        repeat(MAX_REDIRECTS + 1) { redirectIndex ->
            if (!currentUrl.protocol.equals("https", ignoreCase = true) || currentUrl.host.isNullOrBlank()) {
                return@runCatching null
            }
            val connection = currentUrl.openConnection() as HttpsURLConnection
            try {
                connection.connectTimeout = 4_000
                connection.readTimeout = 4_000
                connection.instanceFollowRedirects = false
                connection.connect()
                val code = connection.responseCode
                if (code in REDIRECT_STATUS_CODES && redirectIndex < MAX_REDIRECTS) {
                    val location = connection.getHeaderField("Location")?.trim()
                        ?.takeIf { it.isNotEmpty() } ?: return@runCatching null
                    val nextUrl = URL(currentUrl, location)
                    if (!nextUrl.protocol.equals("https", ignoreCase = true) || nextUrl.host.isNullOrBlank()) {
                        return@runCatching null
                    }
                    currentUrl = nextUrl
                    return@repeat
                }
                if (code !in 200..299) return@runCatching null
                val mimeType = connection.contentType.orEmpty().substringBefore(';').trim().lowercase()
                if (mimeType !in ALLOWED_IMAGE_MIME_TYPES) return@runCatching null
                val maximumBytes = if (mimeType == SVG_MIME_TYPE) SvgResourcePolicy.MAXIMUM_BYTES else MAXIMUM_IMAGE_BYTES
                if (connection.contentLengthLong > maximumBytes) return@runCatching null
                val bytes = connection.inputStream.use {
                    readBounded(it, maximumBytes)
                } ?: return@runCatching null
                if (mimeType == SVG_MIME_TYPE) {
                    return@runCatching SvgIconDecoder.decode(bytes, maximumPixelSize = MAXIMUM_DECODED_DIMENSION.toInt())
                }
                return@runCatching decodeBoundedImage(bytes)
            } finally {
                connection.disconnect()
            }
        }
        null
    }.getOrNull()

    private fun readBounded(stream: InputStream, maximumBytes: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            if (total > maximumBytes) return null
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    /** Parses dimensions before decoding only the thumbnail required by native UI. */
    private fun decodeBoundedImage(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val width = bounds.outWidth.toLong()
        val height = bounds.outHeight.toLong()
        if (
            width <= 0L ||
            height <= 0L ||
            width > MAXIMUM_SOURCE_DIMENSION ||
            height > MAXIMUM_SOURCE_DIMENSION ||
            width > MAXIMUM_SOURCE_PIXELS / height
        ) {
            return null
        }

        var sampleSize = 1
        while (
            width / sampleSize.toLong() > MAXIMUM_DECODED_DIMENSION ||
            height / sampleSize.toLong() > MAXIMUM_DECODED_DIMENSION
        ) {
            sampleSize *= 2
        }
        return BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        )
    }

    private const val SVG_MIME_TYPE = "image/svg+xml"
    private val ALLOWED_IMAGE_MIME_TYPES = setOf(
        "image/gif",
        "image/jpeg",
        "image/jpg",
        "image/png",
        SVG_MIME_TYPE,
        "image/webp",
    )
    private val REDIRECT_STATUS_CODES = setOf(301, 302, 303, 307, 308)
    private const val MAX_REDIRECTS = 3
    private const val MAXIMUM_IMAGE_BYTES = 2_000_000
    private const val MAXIMUM_SOURCE_DIMENSION = 8_192L
    private const val MAXIMUM_SOURCE_PIXELS = 16_777_216L
    private const val MAXIMUM_DECODED_DIMENSION = 256L
}
