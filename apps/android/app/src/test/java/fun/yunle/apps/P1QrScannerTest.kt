package `fun`.yunle.apps

import `fun`.yunle.apps.scanner.QrCodeDecoder
import `fun`.yunle.apps.scanner.ScanParser
import `fun`.yunle.apps.scanner.ScanPurpose
import `fun`.yunle.apps.scanner.ScanResult
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import org.junit.Assert.assertEquals
import org.junit.Test

class P1QrScannerTest {
    @Test
    fun generalScanRoutesNativeLinks() {
        val destinations = mapOf(
            " https://apps.yunle.fun/app/reader\n" to NativeDestination.Application("reader"),
            "https://apps.yunle.fun/w/2345ab/" to NativeDestination.Workshop("2345AB"),
            "yunlefun://workshop/a2b3c4" to NativeDestination.Workshop("A2B3C4"),
            "yunlefun://developer/YunYouJun" to NativeDestination.Developer("YunYouJun"),
        )
        for ((url, destination) in destinations) {
            assertEquals(url, ScanResult.Destination(destination), ScanParser.parse(url, ScanPurpose.GENERAL))
        }

        val nonce = "N".repeat(32)
        val challenge = "A".repeat(43)
        val authUrl = "https://www.yunle.fun/auth/app?client_id=partner-app" +
            "&redirect_uri=https%3A%2F%2Fclient.yunle.fun%2Fauth&scope=identity%3Abootstrap" +
            "&nonce=$nonce&code_challenge=$challenge&code_challenge_method=S256"
        val request = CrossAppAuthorizationRequest("partner-app", "https://client.yunle.fun/auth", nonce, challenge)
        assertEquals(ScanResult.Destination(NativeDestination.CrossAppAuth(request)), ScanParser.parse(authUrl, ScanPurpose.GENERAL))
    }

    @Test
    fun generalScanBlocksMalformedFirstPartyLinksAndUnsafeSchemes() {
        val invalid = listOf(
            "https://apps.yunle.fun/app/reader?extra=1",
            "https://apps.yunle.fun/w/111111",
            "https://apps.yunle.fun./app/reader",
            "https://www.yunle.fun/auth/app?client_id=bad",
            "https://www.yunle.fun/auth/app/",
            "javascript:alert(1)",
            "file:///sdcard/photo.jpg",
            "intent://example.org/#Intent;end",
            "https:///missing-host",
            "https://user@example.org/",
            "https://example.org/a\nb",
            "https://example.org/a\rb",
            "https://example.org/bad path",
        )
        for (url in invalid) {
            assertEquals(url, ScanResult.UnsupportedLink, ScanParser.parse(url, ScanPurpose.GENERAL))
        }
    }

    @Test
    fun generalScanRecognizesWebsiteAndPlainText() {
        assertEquals(
            ScanResult.Website("https://example.org/docs?q=qr#overview"),
            ScanParser.parse("  HTTPS://example.org/a/../docs?q=qr#overview  ", ScanPurpose.GENERAL),
        )
        assertEquals(ScanResult.Text("你好\n二维码"), ScanParser.parse(" \t你好\n二维码 \r", ScanPurpose.GENERAL))
        assertEquals(ScanResult.Text("2345ab"), ScanParser.parse("2345ab", ScanPurpose.GENERAL))
    }

    @Test
    fun workshopScanAcceptsCodeAndWorkshopLinkOnly() {
        val expected = ScanResult.Destination(NativeDestination.Workshop("2345AB"))
        assertEquals(expected, ScanParser.parse("\n2345ab ", ScanPurpose.WORKSHOP))
        assertEquals(expected, ScanParser.parse("https://apps.yunle.fun/w/2345ab/", ScanPurpose.WORKSHOP))
        for (payload in listOf("111111", "https://apps.yunle.fun/app/reader", "https://example.org", "plain text")) {
            assertEquals(payload, ScanResult.UnsupportedWorkshop, ScanParser.parse(payload, ScanPurpose.WORKSHOP))
        }
    }

    @Test
    fun scanRejectsEmptyOversizedAndIllegalControlPayloads() {
        for (payload in listOf(" \t\n", "界".repeat(3334), "a\u0000b", "\u000Babc")) {
            for (purpose in ScanPurpose.entries) {
                assertEquals(ScanResult.UnsupportedLink, ScanParser.parse(payload, purpose))
            }
        }
        val limit = "界".repeat(3333) + "a"
        assertEquals(ScanResult.Text(limit), ScanParser.parse(limit, ScanPurpose.GENERAL))
    }

    @Test
    fun decodesSingleQrFromStridedLumaAndArgbPixels() {
        val payload = "你好，二维码"
        val frame = qrFrame(payload)
        assertEquals(listOf(payload), frame.decodeLuma())
        assertEquals(listOf(payload), frame.decodePixels())
    }

    @Test
    fun decodesSideBySideQrsAndDeduplicatesBothInputs() {
        val first = "https://apps.yunle.fun/w/2345AB"
        val second = "https://example.org/docs"
        val frame = qrFrame(first, second, first)
        assertEquals(listOf(first, second).sorted(), frame.decodeLuma().sorted())
        assertEquals(listOf(first, second).sorted(), frame.decodePixels().sorted())
    }

    @Test
    fun decodesInvertedQrFromBothInputs() {
        val frame = qrFrame("inverted QR", inverted = true)
        assertEquals(listOf("inverted QR"), frame.decodeLuma())
        assertEquals(listOf("inverted QR"), frame.decodePixels())
    }

    private fun qrFrame(vararg payloads: String, inverted: Boolean = false): QrFrame {
        val edge = 180
        val width = edge * payloads.size
        val rowStride = width + 11
        // Camera planes can omit the padding after the final row.
        val luma = ByteArray(rowStride * (edge - 1) + width)
        val pixels = IntArray(width * edge)
        val writer = QRCodeWriter()
        for ((index, payload) in payloads.withIndex()) {
            val matrix = writer.encode(payload, BarcodeFormat.QR_CODE, edge, edge, mapOf(EncodeHintType.CHARACTER_SET to "UTF-8"))
            for (y in 0 until edge) {
                for (x in 0 until edge) {
                    val black = matrix[x, y] xor inverted
                    val column = index * edge + x
                    luma[y * rowStride + column] = if (black) 0 else 0xff.toByte()
                    pixels[y * width + column] = if (black) 0xff000000.toInt() else 0xffffffff.toInt()
                }
            }
        }
        return QrFrame(width, edge, rowStride, luma, pixels)
    }

    private data class QrFrame(
        val width: Int,
        val height: Int,
        val rowStride: Int,
        val luma: ByteArray,
        val pixels: IntArray,
    ) {
        fun decodeLuma() = QrCodeDecoder.decodeLumaFrame(luma, width, height, rowStride)
        fun decodePixels() = QrCodeDecoder.decodeLuminancePixels(pixels, width, height)
    }
}
