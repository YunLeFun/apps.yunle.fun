package `fun`.yunle.apps

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/** A validated first-party route that can be hosted by [LocalPageActivity]. */
internal data class LocalPageRequest(
    val routePath: String,
    val kind: String,
    val target: String?,
) {
    fun contextJson(): String = buildString {
        append("{\"version\":1,\"kind\":\"")
        append(kind)
        append('"')
        target?.let {
            append(",\"target\":\"")
            append(it)
            append('"')
        }
        append('}')
    }
}

/** Strict allowlist for routes accepted by the non-exported local page container. */
internal object LocalPageRoutePolicy {
    const val KIND_APP_DETAIL = "app-detail-sheet"
    const val KIND_DEVELOPER = "developer-sheet"
    const val TARGET_REVIEWS = "reviews"

    fun resolve(kind: String?, value: String?, target: String?): LocalPageRequest? {
        val segment = value?.takeIf(::isSafeSegment) ?: return null
        val encodedSegment = URLEncoder.encode(segment, StandardCharsets.UTF_8)
            .replace("+", "%20")

        return when (kind) {
            KIND_APP_DETAIL -> {
                if (target != null && target != TARGET_REVIEWS) return null
                LocalPageRequest("/app/$encodedSegment", kind, target)
            }
            KIND_DEVELOPER -> {
                if (target != null) return null
                LocalPageRequest("/developer/$encodedSegment", kind, null)
            }
            else -> null
        }
    }

    private fun isSafeSegment(value: String): Boolean =
        value.isNotBlank() &&
            value.length <= MAXIMUM_SEGMENT_LENGTH &&
            value == value.trim() &&
            value != "." &&
            value != ".." &&
            value.none { it.isISOControl() || it in FORBIDDEN_SEGMENT_CHARACTERS }

    private const val MAXIMUM_SEGMENT_LENGTH = 128
    private const val FORBIDDEN_SEGMENT_CHARACTERS = "/\\?#%"
}
