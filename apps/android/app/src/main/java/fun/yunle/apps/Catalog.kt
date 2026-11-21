package `fun`.yunle.apps

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URI
import javax.net.ssl.HttpsURLConnection

internal data class CatalogApp(
    val id: String,
    val key: String,
    val name: String,
    val description: String,
    val author: String,
    val ownerLogin: String?,
    val category: String,
    val emoji: String,
    val launchUrl: String?,
    val logo: String?,
    val themeColor: String?,
    val trustedHosts: List<String>,
    val immersive: Boolean,
    val slug: String? = null,
    val homeReference: String? = null,
    val rating: Double? = null,
    val isOfficial: Boolean = false,
    val releaseStage: String? = null,
    val tags: List<String> = emptyList(),
    val accessMode: String? = null,
    val requiresMembership: Boolean = false,
    val coinCost: Int = 0,
    val audience: String? = null,
    val accessWorkshopId: String? = null,
    val personalMarketOwnerLogin: String? = null,
    val rawWebsiteUrl: String? = null,
) {
    val homeKey: String get() = homeReference ?: id
    val browseCategory: String get() = category.trim().ifBlank { "其他" }

    fun withAuthorizedLaunchUrl(): CatalogApp =
        if (launchUrl != null || rawWebsiteUrl == null) this else copy(launchUrl = rawWebsiteUrl)

    fun matches(query: String): Boolean {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return true
        return (listOfNotNull(name, key, slug, category, author, description) + tags)
            .any { it.contains(trimmed, ignoreCase = true) }
    }

    fun launchOptions(): JSONObject? = launchUrl?.let { url ->
        JSONObject()
            .put("url", url)
            .put("title", name)
            .put("displayMode", if (immersive) "immersive" else "titlebar")
            .put("trustedHosts", JSONArray(trustedHosts))
            .put("app", JSONObject()
                .put("id", id)
                .put("slug", key)
                .put("name", name)
                .put("emoji", emoji)
                .put("description", description)
                .put("developer", ownerLogin)
                .put("developerName", author)
                .put("logo", logo)
                .put("themeColor", themeColor))
    }

    companion object {
        fun read(record: JSONObject): CatalogApp? = readScoped(
            record = record,
            allowWorkshopAudience = false,
            workshopId = null,
            personalMarketLogin = null,
            allowAuthorizedLaunch = false,
        )

        fun readScoped(
            record: JSONObject,
            allowWorkshopAudience: Boolean = false,
            workshopId: String? = null,
            personalMarketLogin: String? = null,
            allowAuthorizedLaunch: Boolean = false,
            allowCreatorOwned: Boolean = false,
        ): CatalogApp? {
            val rawAudience = record.readString("audience")
            val audienceValid = rawAudience == "public" ||
                (allowWorkshopAudience && rawAudience == "workshop") ||
                allowCreatorOwned
            if (!audienceValid) return null
            if (!allowCreatorOwned && rawAudience == "public") {
                if (record.opt("isPublic") != true ||
                    record.readString("status") != "approved" ||
                    record.readString("publicationStatus") != "published"
                ) {
                    return null
                }
            }
            val id = record.readString("_id")?.takeIf(::validKey) ?: return null
            val key = record.readString("marketShortName")?.takeIf(::validKey) ?: id
            val slug = record.readString("slug")?.takeIf(::validKey)
            val name = record.readString("name")?.trim()?.takeIf(String::isNotEmpty) ?: return null
            val accessMode = record.readString("accessMode")
            val isUnavailable = record.optBoolean("isUnavailable", false)
            val requiresMembership = !record.isNull("requiresMembership") && record.opt("requiresMembership") == true
            val coinNumber = (record.opt("coinCost") as? Number)?.toDouble()
            val coinCost = coinNumber?.takeIf { it.isFinite() && it >= 0.0 && it <= Int.MAX_VALUE }?.toInt() ?: 0
            val guestAccess = accessMode == "public" &&
                !isUnavailable &&
                !requiresMembership &&
                (coinNumber == null || coinNumber == 0.0)
            val canonicalUrl = (CANONICAL_WEBSITE_URLS[key]
                ?: slug?.let { CANONICAL_WEBSITE_URLS[it] }
                ?: CANONICAL_WEBSITE_URLS[id])
                ?.takeIf(::isHttps)
            val url = canonicalUrl ?: record.readString("websiteUrl")?.takeIf(::isHttps)
            val logo = record.readString("logo")?.takeIf(::isHttps)
            val hosts = record.optJSONArray("trustedHosts")
            val tagsArray = record.optJSONArray("tags")
            val parsedTags = if (tagsArray == null) {
                emptyList()
            } else {
                (0 until minOf(10, tagsArray.length()))
                    .mapNotNull { (tagsArray.opt(it) as? String)?.trim()?.takeIf(String::isNotBlank)?.take(24) }
            }
            val parsedRating = (record.opt("rating") as? Number)?.toDouble()
                ?.takeIf { it.isFinite() && it in 0.0..5.0 }
            val launchTarget = url.takeIf { guestAccess || (allowAuthorizedLaunch && !isUnavailable) }
            return CatalogApp(
                id = id,
                key = key,
                name = name.take(160),
                description = record.optString("description").take(3000),
                author = (record.readString("developerName")?.takeIf(String::isNotBlank)
                    ?: record.readString("ownerLogin") ?: "独立开发者").take(100),
                ownerLogin = record.readString("ownerLogin")?.takeIf(::validKey),
                category = record.optString("category").take(40),
                emoji = record.readString("emoji")?.takeIf(String::isNotBlank)?.take(12) ?: "☁️",
                launchUrl = launchTarget,
                logo = logo,
                themeColor = record.readString("themeColor"),
                trustedHosts = if (personalMarketLogin != null || hosts == null) {
                    emptyList()
                } else {
                    (0 until minOf(50, hosts.length())).mapNotNull { hosts.opt(it) as? String }
                },
                immersive = record.readString("displayMode") == "immersive",
                slug = slug,
                rating = parsedRating,
                isOfficial = record.opt("isOfficial") == true,
                releaseStage = record.readString("releaseStage")?.take(32),
                tags = parsedTags,
                accessMode = accessMode,
                requiresMembership = requiresMembership,
                coinCost = coinCost,
                audience = rawAudience,
                accessWorkshopId = workshopId,
                personalMarketOwnerLogin = personalMarketLogin,
                rawWebsiteUrl = url,
            )
        }

        fun validKey(value: String): Boolean = Regex("[a-zA-Z0-9_.-]{1,128}").matches(value) &&
            value != "." && value != ".."

        private val CANONICAL_WEBSITE_URLS = mapOf(
            "web-resume" to "https://resume.yunle.fun",
            "ai-sfc" to "https://ai-sfc.yunle.fun",
            "give-me-money" to "https://gmm.yunle.fun/",
        )

        private fun isHttps(value: String): Boolean = runCatching {
            val url = URI(value)
            url.scheme.equals("https", ignoreCase = true) && !url.host.isNullOrEmpty() && url.userInfo == null &&
                url.port in listOf(-1, 443)
        }.getOrDefault(false)
    }
}

internal fun interface CatalogDataSource {
    fun load(): List<CatalogApp>
}

internal object CatalogRepository : CatalogDataSource {
    private const val ENDPOINT = "https://apps.yunle.fun/api/apps/public"
    private const val MAXIMUM_BYTES = 2 * 1024 * 1024

    @Volatile
    internal var overrideForTesting: CatalogDataSource? = null

    fun loadActive(): List<CatalogApp> = (overrideForTesting ?: this).load()

    override fun load(): List<CatalogApp> {
        val connection = URI(ENDPOINT).toURL().openConnection() as HttpsURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.setRequestProperty("Accept", "application/json")
            check(connection.responseCode == 200 && connection.contentType?.startsWith("application/json") == true)
            return connection.inputStream.use { stream ->
                val buffer = ByteArray(8192)
                val output = ByteArrayOutputStream()
                while (true) {
                    val count = stream.read(buffer)
                    if (count == -1) break
                    check(output.size() + count <= MAXIMUM_BYTES)
                    output.write(buffer, 0, count)
                }
                decode(output.toString(Charsets.UTF_8.name()))
            }
        } finally {
            connection.disconnect()
        }
    }

    internal fun decode(payload: String): List<CatalogApp> {
        val items = JSONObject(payload).getJSONArray("items")
        check(items.length() <= 1000)
        return (0 until items.length()).mapNotNull { index ->
            items.optJSONObject(index)?.let(CatalogApp::read)
        }.distinctBy(CatalogApp::id)
    }
}
