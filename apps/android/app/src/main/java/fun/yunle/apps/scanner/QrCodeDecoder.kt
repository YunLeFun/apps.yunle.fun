package `fun`.yunle.apps.scanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.LuminanceSource
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.GlobalHistogramBinarizer
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader
import com.google.zxing.qrcode.QRCodeReader

internal object QrCodeDecoder {
    const val MAX_IMAGE_BYTES = 20 * 1024 * 1024
    private const val MAX_IMAGE_PIXELS = 60_000_000L
    private const val MAX_IMAGE_EDGE = 2048
    private const val MAX_RESULTS = 20

    private val hints = mapOf(
        DecodeHintType.TRY_HARDER to true,
        DecodeHintType.ALSO_INVERTED to true,
        DecodeHintType.CHARACTER_SET to "UTF-8",
    )

    fun decodeLumaFrame(yBytes: ByteArray, width: Int, height: Int, rowStride: Int): List<String> {
        if (width <= 0 || height <= 0 || rowStride < width ||
            (height - 1L) * rowStride + width > yBytes.size
        ) {
            return emptyList()
        }
        val source = PlanarYUVLuminanceSource(yBytes, rowStride, height, 0, 0, width, height, false)
        return decode(source, useGlobalHistogram = false)
    }

    fun decodeLuminancePixels(pixels: IntArray, width: Int, height: Int): List<String> {
        if (width <= 0 || height <= 0 || width.toLong() * height > pixels.size) return emptyList()
        return decode(RGBLuminanceSource(width, height, pixels), useGlobalHistogram = true)
    }

    fun decodeImageBytes(rawBytes: ByteArray): List<String> {
        if (rawBytes.size > MAX_IMAGE_BYTES) throw ScanImageException(ScanImageError.TOO_LARGE)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw ScanImageException(ScanImageError.INVALID_IMAGE)
        }
        if (bounds.outWidth.toLong() * bounds.outHeight > MAX_IMAGE_PIXELS) {
            throw ScanImageException(ScanImageError.TOO_LARGE)
        }

        val longestEdge = maxOf(bounds.outWidth, bounds.outHeight)
        var sampleSize = 1
        while (longestEdge > MAX_IMAGE_EDGE * sampleSize) sampleSize *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, options)
            ?: throw ScanImageException(ScanImageError.INVALID_IMAGE)
        try {
            val width = bitmap.width
            val height = bitmap.height
            if (maxOf(width, height) > MAX_IMAGE_EDGE) throw ScanImageException(ScanImageError.TOO_LARGE)
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            return decodeLuminancePixels(pixels, width, height)
                .ifEmpty { throw ScanImageException(ScanImageError.NO_CODE) }
        } finally {
            bitmap.recycle()
        }
    }

    private fun decode(source: LuminanceSource, useGlobalHistogram: Boolean): List<String> {
        val payloads = linkedSetOf<String>()
        fun collect(bitmap: BinaryBitmap) {
            val multiple = try {
                QRCodeMultiReader().decodeMultiple(bitmap, hints).map { it.text }
            } catch (_: ReaderException) {
                emptyList()
            }
            val texts = multiple.ifEmpty {
                try {
                    listOf(QRCodeReader().decode(bitmap, hints).text)
                } catch (_: ReaderException) {
                    emptyList()
                }
            }
            for (text in texts) {
                if (payloads.size >= MAX_RESULTS) break
                if (text.isNotBlank() && text.toByteArray(Charsets.UTF_8).size <= MAX_SCAN_PAYLOAD_BYTES) {
                    payloads.add(text)
                }
            }
        }

        for (luminance in listOf(source, source.invert())) {
            collect(BinaryBitmap(HybridBinarizer(luminance)))
            if (useGlobalHistogram && payloads.size < MAX_RESULTS) {
                collect(BinaryBitmap(GlobalHistogramBinarizer(luminance)))
            }
            if (payloads.size >= MAX_RESULTS) break
        }
        return payloads.toList()
    }
}
