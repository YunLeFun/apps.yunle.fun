package `fun`.yunle.apps.home

import org.json.JSONArray
import org.json.JSONObject

internal enum class HomeSyncError(val userMessage: String) {
    INVALID_RESPONSE("云同步返回了无法识别的数据。"),
    UNAUTHORIZED("登录已过期，请重新登录后再同步。"),
    FORBIDDEN("当前账号暂不允许云同步。"),
    UNAVAILABLE("暂时无法连接云同步服务，请稍后再试。"),
    UNSUPPORTED_SCHEMA("云端版本暂不支持当前同步格式。"),
    CONFLICT("云端与本地的云居内容存在冲突，请选择保留的版本。"),
}

internal class HomeSyncException(
    val error: HomeSyncError,
    val remoteConflict: RemoteHomeScreen? = null,
    cause: Throwable? = null,
) : Exception(error.userMessage, cause)

internal data class HomeAppReference(val appId: String) {
    fun toJson(): JSONObject = JSONObject().put("appId", appId)

    companion object {
        fun fromJson(raw: Any?): HomeAppReference? = when (raw) {
            is JSONObject -> raw.optString("appId").trim().takeIf { it.isNotEmpty() && !raw.isNull("appId") }
                ?.let(::HomeAppReference)
            is String -> raw.trim().takeIf { it.isNotEmpty() }?.let(::HomeAppReference)
            else -> null
        }
    }
}

internal data class HomeRecentReference(
    val appId: String,
    val usedAt: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("appId", appId)
        .put("usedAt", usedAt)

    companion object {
        fun fromJson(json: JSONObject): HomeRecentReference {
            val appId = json.optString("appId")
            val usedAt = if (json.has("usedAt") && !json.isNull("usedAt")) json.optLong("usedAt", -1L) else -1L
            if (appId.isEmpty() || usedAt < 0L) {
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }
            return HomeRecentReference(appId = appId, usedAt = usedAt)
        }
    }
}

internal data class HomeApplicationSource(
    val appId: String,
    val ownerLogin: String,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("appId", appId)
        .put("ownerLogin", ownerLogin)

    companion object {
        fun fromJson(json: JSONObject): HomeApplicationSource {
            val appId = json.optString("appId")
            val ownerLogin = json.optString("ownerLogin")
            if (appId.isEmpty() || ownerLogin.isEmpty()) {
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }
            return HomeApplicationSource(appId = appId, ownerLogin = ownerLogin)
        }
    }
}

internal data class HomeFolder(
    val id: String,
    val name: String,
    val appIds: List<String>,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("appIds", JSONArray(appIds))

    companion object {
        const val LIMIT = 200
        const val NAME_LIMIT = 40
        private val ID_REGEX = Regex("^[A-Za-z0-9_-]{1,64}$")

        fun isValidId(id: String): Boolean = ID_REGEX.matches(id)

        fun isValidName(name: String): Boolean =
            name.isNotEmpty() &&
                name == name.trim() &&
                name.length <= NAME_LIMIT &&
                name.none { it.code < 32 || it.code == 127 }

        fun fromJson(json: JSONObject): HomeFolder {
            val id = json.optString("id")
            val name = json.optString("name")
            val idsArray = json.optJSONArray("appIds")
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            val appIds = buildList(idsArray.length()) {
                for (index in 0 until idsArray.length()) {
                    val value = idsArray.opt(index) as? String
                        ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                    add(value)
                }
            }
            return HomeFolder(id = id, name = name, appIds = appIds)
        }
    }
}

internal data class HomeConfiguration(
    val installedApps: List<HomeAppReference> = emptyList(),
    val dockApps: List<HomeAppReference> = emptyList(),
    val recentApps: List<HomeRecentReference> = emptyList(),
    val updatedAt: Long = 0L,
    val folders: List<HomeFolder> = emptyList(),
    val applicationSources: List<HomeApplicationSource> = emptyList(),
) {
    fun hasSameContent(
        other: HomeConfiguration,
        includingFolders: Boolean = true,
        includingSources: Boolean = true,
    ): Boolean = installedApps == other.installedApps &&
        dockApps == other.dockApps &&
        recentApps == other.recentApps &&
        (!includingFolders || folders == other.folders) &&
        (!includingSources || applicationSources.sortedBy { it.appId } == other.applicationSources.sortedBy { it.appId })

    fun matches(remote: RemoteHomeScreen): Boolean = hasSameContent(
        other = remote.configuration,
        includingFolders = remote.carriesFolders,
        includingSources = remote.carriesSources,
    )

    fun adopting(remote: RemoteHomeScreen): HomeConfiguration {
        val next = remote.configuration.copy(
            folders = if (remote.carriesFolders) remote.configuration.folders else folders,
            applicationSources = if (remote.carriesSources) remote.configuration.applicationSources else applicationSources,
        )
        return next.sanitizingFolders()
    }

    fun sanitizingFolders(): HomeConfiguration {
        val installed = installedApps.mapTo(mutableSetOf()) { it.appId }
        val docked = dockApps.mapTo(mutableSetOf()) { it.appId }
        val seen = mutableSetOf<String>()
        val sanitizedFolders = folders.mapNotNull { folder ->
            val filtered = folder.appIds.filter { id ->
                installed.contains(id) && !docked.contains(id) && seen.add(id)
            }
            if (filtered.isEmpty()) null else folder.copy(appIds = filtered)
        }
        val references = installed + docked + recentApps.map { it.appId }
        val sanitizedSources = applicationSources
            .filter { references.contains(it.appId) }
            .sortedBy { it.appId }
        return copy(folders = sanitizedFolders, applicationSources = sanitizedSources)
    }

    fun validate() {
        val groups = listOf(
            installedApps.map { it.appId },
            dockApps.map { it.appId },
            recentApps.map { it.appId },
        )
        if (installedApps.size > 1000 ||
            dockApps.size > 4 ||
            recentApps.size > 100 ||
            updatedAt < 0L ||
            updatedAt > MAX_SAFE_INTEGER ||
            recentApps.any { it.usedAt < 0L || it.usedAt > MAX_SAFE_INTEGER } ||
            groups.any { ids ->
                ids.toSet().size != ids.size || ids.any { !isValidReference(it) }
            }
        ) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }

        val installed = installedApps.mapTo(mutableSetOf()) { it.appId }
        val folderIds = mutableSetOf<String>()
        val members = mutableSetOf<String>()
        if (folders.size > HomeFolder.LIMIT ||
            folders.any { folder ->
                !HomeFolder.isValidId(folder.id) ||
                    !folderIds.add(folder.id) ||
                    !HomeFolder.isValidName(folder.name) ||
                    folder.appIds.isEmpty() ||
                    folder.appIds.any { !installed.contains(it) || !members.add(it) }
            }
        ) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }

        val references = groups.flatten().toSet()
        val sourceIds = mutableSetOf<String>()
        if (applicationSources.size > 1104 ||
            applicationSources.any { source ->
                !references.contains(source.appId) ||
                    !sourceIds.add(source.appId) ||
                    !isNormalizedOwnerLogin(source.ownerLogin)
            }
        ) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }
    }

    fun toJson(): JSONObject = JSONObject()
        .put("installedApps", JSONArray().apply { installedApps.forEach { put(it.toJson()) } })
        .put("dockApps", JSONArray().apply { dockApps.forEach { put(it.toJson()) } })
        .put("recentApps", JSONArray().apply { recentApps.forEach { put(it.toJson()) } })
        .put("updatedAt", updatedAt)
        .put("folders", JSONArray().apply { folders.forEach { put(it.toJson()) } })
        .put("applicationSources", JSONArray().apply { applicationSources.forEach { put(it.toJson()) } })

    companion object {
        private const val MAX_SAFE_INTEGER = 9_007_199_254_740_991L

        private fun isValidReference(id: String): Boolean =
            id.isNotEmpty() &&
                id.length <= 256 &&
                id == id.trim() &&
                id.none { it.code < 32 || it.code == 127 }

        private fun isNormalizedOwnerLogin(login: String): Boolean =
            login.isNotEmpty() &&
                login.length <= 64 &&
                login == login.trim().lowercase() &&
                login.none { it.isWhitespace() || it.code < 32 || it.code == 127 }

        fun fromJson(json: JSONObject): HomeConfiguration {
            val installedArray = json.optJSONArray("installedApps")
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            val dockArray = json.optJSONArray("dockApps")
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            val recentArray = json.optJSONArray("recentApps")
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            if (!json.has("updatedAt") || json.isNull("updatedAt")) {
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }
            val updatedAt = json.optLong("updatedAt", -1L)
            if (updatedAt < 0L) {
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }

            val installedApps = buildList(installedArray.length()) {
                for (i in 0 until installedArray.length()) {
                    val obj = installedArray.optJSONObject(i)
                        ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                    val appId = obj.optString("appId")
                    if (appId.isEmpty() || obj.isNull("appId")) {
                        throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                    }
                    add(HomeAppReference(appId))
                }
            }
            val dockApps = buildList(dockArray.length()) {
                for (i in 0 until dockArray.length()) {
                    val obj = dockArray.optJSONObject(i)
                        ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                    val appId = obj.optString("appId")
                    if (appId.isEmpty() || obj.isNull("appId")) {
                        throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                    }
                    add(HomeAppReference(appId))
                }
            }
            val recentApps = buildList(recentArray.length()) {
                for (i in 0 until recentArray.length()) {
                    val obj = recentArray.optJSONObject(i)
                        ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                    add(HomeRecentReference.fromJson(obj))
                }
            }
            val foldersArray = json.optJSONArray("folders")
            val folders = if (foldersArray == null) {
                emptyList()
            } else {
                buildList(foldersArray.length()) {
                    for (i in 0 until foldersArray.length()) {
                        val obj = foldersArray.optJSONObject(i)
                            ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                        add(HomeFolder.fromJson(obj))
                    }
                }
            }
            val sourcesArray = json.optJSONArray("applicationSources")
            val applicationSources = if (sourcesArray == null) {
                emptyList()
            } else {
                buildList(sourcesArray.length()) {
                    for (i in 0 until sourcesArray.length()) {
                        val obj = sourcesArray.optJSONObject(i)
                            ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
                        add(HomeApplicationSource.fromJson(obj))
                    }
                }.sortedBy { it.appId }
            }

            return HomeConfiguration(
                installedApps = installedApps,
                dockApps = dockApps,
                recentApps = recentApps,
                updatedAt = updatedAt,
                folders = folders,
                applicationSources = applicationSources,
            )
        }
    }
}

internal data class RemoteHomeScreen(
    val schemaVersion: Int = HomeScreenWrite.SCHEMA_VERSION,
    val revision: String?,
    val configuration: HomeConfiguration,
) {
    val carriesFolders: Boolean get() = schemaVersion >= 2
    val carriesSources: Boolean get() = schemaVersion >= 3

    fun validate() {
        if (schemaVersion !in 1..3 ||
            (!carriesFolders && configuration.folders.isNotEmpty()) ||
            (!carriesSources && configuration.applicationSources.isNotEmpty())
        ) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }
        if (revision != null && !REVISION_REGEX.matches(revision)) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }
        configuration.validate()
        if (revision == null && configuration != HomeConfiguration()) {
            throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
        }
    }

    fun toJson(): JSONObject = JSONObject()
        .put("schemaVersion", schemaVersion)
        .put("revision", revision ?: JSONObject.NULL)
        .put("configuration", configuration.toJson())

    companion object {
        private val REVISION_REGEX = Regex("^[0-9a-f]{64}$")

        fun fromJson(json: JSONObject): RemoteHomeScreen {
            if (!json.has("revision")) {
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }
            val schemaVersion = json.optInt("schemaVersion", -1)
            val revision = if (json.isNull("revision")) null else json.optString("revision")
            val configJson = json.optJSONObject("configuration")
                ?: throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            val configuration = HomeConfiguration.fromJson(configJson)
            if (schemaVersion >= 3 && (!configJson.has("applicationSources") || !configJson.has("folders"))) {
                throw HomeSyncException(HomeSyncError.INVALID_RESPONSE)
            }
            return RemoteHomeScreen(
                schemaVersion = schemaVersion,
                revision = revision,
                configuration = configuration,
            ).also { it.validate() }
        }
    }
}

internal data class HomeScreenWrite(
    val baseRevision: String?,
    val mutationId: String,
    val configuration: HomeConfiguration,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("schemaVersion", SCHEMA_VERSION)
        .put("baseRevision", baseRevision ?: JSONObject.NULL)
        .put("mutationId", mutationId)
        .put("configuration", configuration.toJson())

    companion object {
        const val SCHEMA_VERSION = 3
    }
}
