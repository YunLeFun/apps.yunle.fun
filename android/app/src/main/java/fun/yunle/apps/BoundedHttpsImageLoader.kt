package `fun`.yunle.apps

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.ImageView
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * Loads small, trusted-surface images without allowing redirects, unbounded
 * downloads, or an oversized compressed image to expand at decode time.
 */
internal object BoundedHttpsImageLoader {
    fun load(
        activity: Activity,
        source: String?,
        imageView: ImageView,
        fallback: View,
    ) {
        val safeSource = source ?: return
        val uri = Uri.parse(safeSource)
        if (uri.scheme?.lowercase() != "https" || uri.host.isNullOrBlank()) return

        Thread {
            val bitmap = fetch(safeSource) ?: return@Thread
            activity.runOnUiThread {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    imageView.setImageBitmap(bitmap)
                    imageView.visibility = View.VISIBLE
                    fallback.visibility = View.GONE
                }
            }
        }.start()
    }

    private fun fetch(source: String): Bitmap? = runCatching {
        val connection = URL(source).openConnection() as HttpsURLConnection
        try {
            connection.connectTimeout = 4_000
            connection.readTimeout = 4_000
            connection.instanceFollowRedirects = false
            connection.connect()
            if (connection.responseCode !in 200..299) return@runCatching null
            val mimeType = connection.contentType.orEmpty().substringBefore(';').lowercase()
            if (mimeType !in ALLOWED_IMAGE_MIME_TYPES) return@runCatching null
            if (connection.contentLengthLong > MAXIMUM_IMAGE_BYTES) return@runCatching null
            val bytes = connection.inputStream.use {
                readBounded(it, MAXIMUM_IMAGE_BYTES)
            } ?: return@runCatching null
            decodeBoundedImage(bytes)
        } finally {
            connection.disconnect()
        }
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

    private val ALLOWED_IMAGE_MIME_TYPES = setOf(
        "image/gif",
        "image/jpeg",
        "image/png",
        "image/webp",
    )
    private const val MAXIMUM_IMAGE_BYTES = 2_000_000
    private const val MAXIMUM_SOURCE_DIMENSION = 8_192L
    private const val MAXIMUM_SOURCE_PIXELS = 16_777_216L
    private const val MAXIMUM_DECODED_DIMENSION = 256L
}
