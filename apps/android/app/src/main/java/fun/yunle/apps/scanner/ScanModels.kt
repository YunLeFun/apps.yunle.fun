package `fun`.yunle.apps.scanner

import `fun`.yunle.apps.CrossAppAuthorizationLink
import `fun`.yunle.apps.NativeDeepLinkRouter
import `fun`.yunle.apps.NativeDestination
import `fun`.yunle.apps.WorkshopLink
import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

internal const val MAX_SCAN_PAYLOAD_BYTES = 10_000

internal enum class ScanPurpose { GENERAL, WORKSHOP }

internal sealed interface ScanResult {
    data class Destination(val destination: NativeDestination) : ScanResult
    data class Website(val url: String) : ScanResult
    data class Text(val value: String) : ScanResult
    data object UnsupportedWorkshop : ScanResult
    data object UnsupportedLink : ScanResult
}

internal data class ScanCandidate(val payload: String, val result: ScanResult) {
    val title: String
        get() = when (result) {
            is ScanResult.Destination -> when (result.destination) {
                is NativeDestination.Workshop -> "个人工坊"
                is NativeDestination.Application -> "云应用"
                is NativeDestination.Developer -> "作者主页"
                is NativeDestination.CrossAppAuth -> "跨应用授权"
                NativeDestination.InvalidCrossAppAuth -> "无法打开此链接"
            }
            is ScanResult.Website -> URI(result.url).host ?: "网址"
            is ScanResult.Text -> "文本"
            ScanResult.UnsupportedWorkshop -> "不是工坊二维码"
            ScanResult.UnsupportedLink -> "无法打开此链接"
        }
}

internal enum class ScanImageError(val message: String) {
    INVALID_IMAGE("图片无法读取，请选择另一张图片。"),
    TOO_LARGE("图片过大，请裁剪二维码区域后重试。"),
    NO_CODE("未识别到二维码，请选择更清晰的图片，或裁剪二维码区域后重试。"),
}

internal class ScanImageException(val error: ScanImageError) : Exception(error.message)

internal object ScanParser {
    private val schemePrefix = Regex("^[A-Za-z][A-Za-z0-9+.-]*:")
    private val firstPartyHosts = setOf("apps.yunle.fun", CrossAppAuthorizationLink.HOST)

    fun parse(payload: String, purpose: ScanPurpose): ScanResult {
        val value = payload.trim()
        if (value.isEmpty() || value.toByteArray(Charsets.UTF_8).size > MAX_SCAN_PAYLOAD_BYTES ||
            payload.any { it.code < 32 && it != '\n' && it != '\r' && it != '\t' }
        ) {
            return ScanResult.UnsupportedLink
        }

        if (purpose == ScanPurpose.WORKSHOP) {
            val code = WorkshopLink.parse(value) ?: return ScanResult.UnsupportedWorkshop
            return ScanResult.Destination(NativeDestination.Workshop(code))
        }

        NativeDeepLinkRouter.parse(value)?.let { destination ->
            return if (destination == NativeDestination.InvalidCrossAppAuth) {
                ScanResult.UnsupportedLink
            } else {
                ScanResult.Destination(destination)
            }
        }
        if (!schemePrefix.containsMatchIn(value)) return ScanResult.Text(value)

        val uri = try {
            URI(value)
        } catch (_: URISyntaxException) {
            return ScanResult.UnsupportedLink
        }
        val scheme = uri.scheme?.lowercase(Locale.ROOT)
        val host = uri.host?.lowercase(Locale.ROOT)
        if ((scheme != "http" && scheme != "https") || host.isNullOrEmpty() ||
            uri.rawUserInfo != null || '\n' in value || '\r' in value ||
            host.removeSuffix(".") in firstPartyHosts
        ) {
            return ScanResult.UnsupportedLink
        }
        val normalized = uri.normalize().toASCIIString()
        return ScanResult.Website("$scheme:${normalized.substringAfter(':')}")
    }
}
