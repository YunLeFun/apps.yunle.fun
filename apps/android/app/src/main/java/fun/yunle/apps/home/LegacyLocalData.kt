package `fun`.yunle.apps.home

import java.security.MessageDigest
import java.util.Collections
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

internal enum class LegacyImportError(val message: String) {
    INVALID_DATA("旧版记录的格式暂时无法导入，原记录已保留。"),
    UNREADABLE("暂时无法读取旧版记录，请稍后重试。"),
    TIMED_OUT("读取旧版记录用时较长，请重新读取。"),
    STORAGE("未能保存导入记录，请检查设备存储空间后重试。"),
    IDENTITY_CHANGED("当前账号或云居已变化，请重新确认导入位置。"),
    ALREADY_CLAIMED("这份旧版记录已为另一个云居保留，请切换到原来的账号后继续。"),
    RECORD_CHANGED("旧版记录已变化，请重新读取并确认导入内容。"),
}

internal class LegacyImportException(
    val error: LegacyImportError,
    cause: Throwable? = null,
) : Exception(error.message, cause)

@Serializable
internal data class LegacyAccountHint(val uid: String, val nickname: String? = null) {
    val label: String get() = nickname?.takeIf { it.isNotBlank() } ?: "旧版账号"
}

internal class LegacyLocalData(values: Map<String, String>) {
    val values: Map<String, String>
    val accounts: List<LegacyAccountHint>
    val id: String
    val appearance: String?
    val syncEnabled: Boolean?
    val autoSyncEnabled: Boolean?
    val dockVisible: Boolean?
    val hasHome: Boolean
    val hasOtherSettings: Boolean
    val configuration: HomeConfiguration?

    init {
        if (!KEYS.containsAll(values.keys) || values.entries.sumOf { (key, value) ->
                key.toByteArray().size.toLong() + value.toByteArray().size
            } > MAXIMUM_BYTES
        ) invalidData()

        accounts = values[SAVED_ACCOUNTS]?.let(::parseAccounts).orEmpty()
        val sanitized = values.toSortedMap()
        if (SAVED_ACCOUNTS in values) {
            sanitized[SAVED_ACCOUNTS] = Json.encodeToString(accounts)
        }
        this.values = Collections.unmodifiableMap(sanitized)

        appearance = values["ylf_theme_mode"]
        if (appearance != null && appearance !in setOf("system", "light", "dark")) invalidData()
        syncEnabled = values.boolean("ylf:cloud-sync-enabled")
        autoSyncEnabled = values.boolean("ylf:cloud-auto-sync")
        dockVisible = values.boolean("ylf:dock-visible")
        hasOtherSettings = CHOICES.keys.any(values::containsKey)
        CHOICES.forEach { (key, options) ->
            if (values[key]?.let { it !in options } == true) invalidData()
        }

        hasHome = HOME_KEYS.any(values::containsKey)
        configuration = if (hasHome) parseConfiguration(values) else null
        id = MessageDigest.getInstance("SHA-256")
            .digest(Json.encodeToString(this.values).toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    companion object {
        const val MAXIMUM_BYTES = 524_288
        const val MAXIMUM_ACCOUNT_HINTS = 10
        const val MAXIMUM_HINT_LENGTH = 256
        const val SAVED_ACCOUNTS = "ylf_saved_accounts"

        private const val INSTALLED = "ylf:homescreen-apps"
        private const val DOCK = "ylf:dock-apps"
        private const val RECENT = "ylf:recent-apps-v2"
        private const val UPDATED_AT = "ylf:homescreen-sync-at"
        private val HOME_KEYS = listOf(INSTALLED, DOCK, RECENT)
        val KEYS = listOf(
            INSTALLED, DOCK, RECENT, UPDATED_AT, "ylf_theme_mode",
            "ylf:cloud-sync-enabled", "ylf:cloud-auto-sync", "ylf:dock-visible",
            "ylf_icon_style", "ylf:preview-window-size", "ylf:in-app-browser-mode",
            "ylf:external-link-mode", "ylf:session-limit-preference", SAVED_ACCOUNTS,
        )
        private val CHOICES = mapOf(
            "ylf_icon_style" to setOf("original", "liquid-glass", "flat-color", "gradient", "minimal"),
            "ylf:preview-window-size" to setOf("mini", "medium", "large", "small"),
            "ylf:in-app-browser-mode" to setOf("titlebar", "system", "immersive"),
            "ylf:external-link-mode" to setOf("safari-view", "default-browser"),
            "ylf:session-limit-preference" to setOf("auto", "2", "3", "4", "5", "6", "7"),
        )

        fun fromJson(json: JsonElement): LegacyLocalData = LegacyLocalData(
            (json as? JsonObject ?: invalidData()).mapValues { (_, value) -> value.requireString() },
        )

        private fun parseAccounts(raw: String): List<LegacyAccountHint> {
            val array = parseJson(raw) as? JsonArray ?: invalidData()
            if (array.size > MAXIMUM_ACCOUNT_HINTS) invalidData()
            val seen = mutableSetOf<String>()
            return array.map { element ->
                val hint = element as? JsonObject ?: invalidData()
                val uid = hint["uid"].requireString()
                val nickname = hint["nickname"]?.takeUnless { it == JsonNull }?.requireString()
                if (!validLegacyText(uid) || !seen.add(uid) ||
                    (nickname != null && !validLegacyText(nickname, allowEmpty = true))
                ) invalidData()
                LegacyAccountHint(uid, nickname)
            }
        }

        private fun parseConfiguration(values: Map<String, String>): HomeConfiguration {
            fun <T> references(key: String, parse: (JsonObject) -> T): List<T> {
                val raw = values[key] ?: return emptyList()
                val array = parseJson(raw) as? JsonArray ?: invalidData()
                return array.map { parse(it as? JsonObject ?: invalidData()) }
            }

            val timestamp = values[UPDATED_AT]?.let { parseJson(it).requireLong() } ?: 0L
            return HomeConfiguration(
                installedApps = references(INSTALLED) { HomeAppReference(it["appId"].requireString()) },
                dockApps = references(DOCK) { HomeAppReference(it["appId"].requireString()) },
                recentApps = references(RECENT) {
                    HomeRecentReference(it["appId"].requireString(), it["usedAt"].requireLong())
                },
                updatedAt = timestamp,
            ).also {
                try {
                    it.validate()
                } catch (e: HomeSyncException) {
                    throw LegacyImportException(LegacyImportError.INVALID_DATA, e)
                }
            }
        }

        private fun Map<String, String>.boolean(key: String): Boolean? = when (get(key)) {
            "true" -> true
            "false" -> false
            null -> null
            else -> invalidData()
        }
    }
}

internal data class LegacyImportArchive(
    val version: Int = 1,
    val record: LegacyLocalData,
    val claim: Claim? = null,
) {
    data class Claim(val accountID: String?, val completed: Boolean = false)

    fun toJson(): String = JsonObject(buildMap {
        put("version", JsonPrimitive(version))
        put("record", JsonObject(record.values.mapValues { JsonPrimitive(it.value) }))
        claim?.let { claim ->
            put("claim", JsonObject(mapOf(
                "accountID" to JsonPrimitive(claim.accountID),
                "completed" to JsonPrimitive(claim.completed),
            )))
        }
    }).toString()

    companion object {
        fun fromJson(raw: String): LegacyImportArchive {
            val archive = parseJson(raw) as? JsonObject ?: invalidData()
            val version = (archive["version"] as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull
            if (version != 1) invalidData()
            val record = LegacyLocalData.fromJson(archive["record"] ?: invalidData())
            val claim = archive["claim"]?.takeUnless { it == JsonNull }?.let {
                val data = it as? JsonObject ?: invalidData()
                val uid = data["accountID"]?.takeUnless { it == JsonNull }?.requireString()
                if (uid != null && !validLegacyText(uid)) invalidData()
                val completed = (data["completed"] as? JsonPrimitive)
                    ?.takeUnless { it.isString }?.booleanOrNull ?: invalidData()
                Claim(uid, completed)
            }
            return LegacyImportArchive(version, record, claim)
        }
    }
}

internal data class LegacyImportConfirmation(
    val id: String = UUID.randomUUID().toString(),
    val recordID: String,
    val accountID: String?,
    val accountGeneration: UUID,
    val libraryGeneration: Int,
)

private fun parseJson(raw: String): JsonElement = try {
    Json.parseToJsonElement(raw)
} catch (_: IllegalArgumentException) {
    // JSON parser messages may contain legacy data.
    throw LegacyImportException(LegacyImportError.INVALID_DATA)
}

private fun JsonElement?.requireString(): String =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: invalidData()

private fun JsonElement?.requireLong(): Long =
    (this as? JsonPrimitive)?.takeUnless { it.isString }?.longOrNull ?: invalidData()

private fun validLegacyText(text: String, allowEmpty: Boolean = false): Boolean =
    (allowEmpty || text.isNotEmpty()) &&
        text.length <= LegacyLocalData.MAXIMUM_HINT_LENGTH &&
        text == text.trim() && text.none { it.code < 32 || it.code == 127 }

private fun invalidData(): Nothing = throw LegacyImportException(LegacyImportError.INVALID_DATA)
