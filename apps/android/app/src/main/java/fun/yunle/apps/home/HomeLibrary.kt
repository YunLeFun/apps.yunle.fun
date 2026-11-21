package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.Base64
import java.util.UUID

internal data class HomeRecentEntry(
    val appId: String,
    val usedAtMillis: Long,
)

internal data class HomeLibrarySnapshot(
    val version: Int = 3,
    val configuration: HomeConfiguration = HomeConfiguration(),
    val cachedApplications: List<CatalogApp> = emptyList(),
    val base: RemoteHomeScreen? = null,
    val mutationId: String = UUID.randomUUID().toString(),
    val hasPendingChanges: Boolean = false,
    val syncEnabled: Boolean = true,
    val autoSyncEnabled: Boolean = true,
    val dockVisible: Boolean = true,
    val lastSyncedAtMillis: Long? = null,
    val lastRestoreId: String? = null,
    val legacyImportId: String? = null,
) {
    val installedIds: List<String> get() = configuration.installedApps.map { it.appId }
    val dockIds: List<String> get() = configuration.dockApps.map { it.appId }
    val recentEntries: List<HomeRecentEntry>
        get() = configuration.recentApps.map { HomeRecentEntry(appId = it.appId, usedAtMillis = it.usedAt) }
    val cachedApps: Map<String, CatalogApp> get() = cachedApplications.associateBy { it.id }

    val applications: List<CatalogApp> get() = configuration.installedApps.map { application(it.appId) }
    val dockApplications: List<CatalogApp> get() = configuration.dockApps.map { application(it.appId) }
    val mainApplications: List<CatalogApp>
        get() = if (dockVisible) {
            applications.filter { !isPinned(it) }
        } else {
            val existing = applications.mapTo(mutableSetOf()) { it.homeKey }
            applications + dockApplications.filter { existing.add(it.homeKey) }
        }
    val recentApplications: List<CatalogApp> get() = configuration.recentApps.map { application(it.appId) }

    fun cachedApplication(reference: String): CatalogApp? {
        val exact = cachedApplications.firstOrNull { it.id == reference }
        if (exact != null) return exact
        val market = cachedApplications.filter { it.key == reference }
        if (market.size == 1) return market.first()
        val legacy = cachedApplications.filter { it.slug == reference }
        return if (legacy.size == 1) legacy.first() else null
    }

    fun application(reference: String): CatalogApp {
        val cached = cachedApplication(reference)
        val source = configuration.applicationSources.firstOrNull { it.appId == reference }
        return when {
            source != null -> {
                if (cached != null &&
                    cached.ownerLogin?.equals(source.ownerLogin, ignoreCase = true) == true
                ) {
                    cached.copy(homeReference = reference)
                } else {
                    CatalogApp(
                        id = cached?.id ?: reference,
                        key = cached?.key ?: reference,
                        name = cached?.name ?: "作者作品",
                        description = "作者：${source.ownerLogin}（暂不支持从云居直接运行）",
                        author = source.ownerLogin,
                        ownerLogin = source.ownerLogin,
                        category = cached?.category ?: "",
                        emoji = cached?.emoji ?: "☁️",
                        launchUrl = null,
                        logo = cached?.logo,
                        themeColor = cached?.themeColor,
                        trustedHosts = emptyList(),
                        immersive = false,
                        slug = cached?.slug,
                        homeReference = reference,
                    )
                }
            }
            reference == YUN_HOME_ID -> CatalogApp(
                id = YUN_HOME_ID,
                key = YUN_HOME_ID,
                name = "Yun Home",
                description = "云端智能家居市场与设备控制台",
                author = "云乐坊",
                ownerLogin = "yunle",
                category = "生活方式",
                emoji = "🏠",
                launchUrl = "https://home.yunle.fun/",
                logo = null,
                themeColor = null,
                trustedHosts = emptyList(),
                immersive = false,
                slug = YUN_HOME_ID,
                homeReference = reference,
            )
            cached != null -> cached.copy(homeReference = reference)
            else -> CatalogApp(
                id = reference,
                key = reference,
                name = "暂不可用",
                description = "已从云端同步，暂无此应用的公开工坊信息。",
                author = "云乐坊",
                ownerLogin = null,
                category = "",
                emoji = "☁️",
                launchUrl = null,
                logo = null,
                themeColor = null,
                trustedHosts = emptyList(),
                immersive = false,
                slug = reference,
                homeReference = reference,
            )
        }
    }

    fun matchesReference(reference: String, app: CatalogApp): Boolean =
        reference == app.homeReference ||
            reference == app.id ||
            reference == app.key ||
            (app.slug != null && reference == app.slug)

    fun isInstalled(app: CatalogApp): Boolean =
        configuration.installedApps.any { matchesReference(it.appId, app) }

    fun isPinned(app: CatalogApp): Boolean =
        configuration.dockApps.any { matchesReference(it.appId, app) }

    fun contains(app: CatalogApp): Boolean = isInstalled(app) || isPinned(app)

    fun containsReference(reference: String): Boolean {
        if (configuration.installedApps.any { it.appId == reference } ||
            configuration.dockApps.any { it.appId == reference }
        ) {
            return true
        }
        val resolved = cachedApplication(reference) ?: return false
        return contains(resolved)
    }

    companion object {
        private const val YUN_HOME_ID = "yun-home"
    }
}

internal class HomeLibrary(
    private val directory: File,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()
    private var currentFile: File = fileForAccount(null)
    private var canWrite = true
    private var _activeAccountId: String? = null

    private val _snapshot = MutableStateFlow(HomeLibrarySnapshot())
    val snapshot: StateFlow<HomeLibrarySnapshot> = _snapshot.asStateFlow()

    private val _storageError = MutableStateFlow<String?>(null)
    val storageError: StateFlow<String?> = _storageError.asStateFlow()

    private val _generation = MutableStateFlow(0)
    val generation: StateFlow<Int> = _generation.asStateFlow()

    var onUserChange: (() -> Unit)? = null

    val activeAccountId: String?
        get() = synchronized(lock) { _activeAccountId }

    val storageDirectory: File
        get() = directory

    val currentFileName: String
        get() = synchronized(lock) { currentFile.name }

    val needsRecovery: Boolean
        get() = synchronized(lock) { !canWrite }

    init {
        synchronized(lock) {
            loadCurrentFileLocked()
        }
    }

    fun activateAccount(accountId: String?) {
        synchronized(lock) {
            val normalized = accountId?.trim()?.takeIf { it.isNotEmpty() }
            if (normalized == _activeAccountId && currentFile == fileForAccount(normalized)) {
                return
            }
            _activeAccountId = normalized
            currentFile = fileForAccount(normalized)
            _generation.value += 1
            loadCurrentFileLocked()
        }
    }

    fun retryLoad() {
        synchronized(lock) {
            loadCurrentFileLocked()
        }
    }

    private fun loadCurrentFileLocked() {
        if (!currentFile.exists()) {
            canWrite = true
            _storageError.value = null
            _snapshot.value = HomeLibrarySnapshot()
            return
        }
        try {
            val raw = currentFile.readText(Charsets.UTF_8)
            val parsed = parseSnapshot(JSONObject(raw))
            canWrite = true
            _storageError.value = null
            _snapshot.value = parsed
        } catch (_: Throwable) {
            canWrite = false
            _storageError.value = "无法读取本地云居数据，请重试。"
            _snapshot.value = HomeLibrarySnapshot()
        }
    }

    fun contains(appId: String): Boolean = _snapshot.value.containsReference(appId)

    fun contains(app: CatalogApp): Boolean = _snapshot.value.contains(app)

    fun add(app: CatalogApp) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val cached = upsertCachedLocked(current.cachedApplications, app)
            if (current.contains(app)) {
                if (cached != current.cachedApplications) {
                    saveLocked(current.copy(cachedApplications = cached), markUserEdit = false)
                }
                return@synchronized
            }
            val refId = app.homeReference ?: app.id
            val nextInstalled = current.configuration.installedApps + HomeAppReference(refId)
            val nextSources = updateApplicationSource(
                sources = current.configuration.applicationSources,
                refId = refId,
                app = app,
            )
            val nextConfig = current.configuration.copy(
                installedApps = nextInstalled,
                updatedAt = nowMillis(),
                applicationSources = nextSources,
            ).sanitizingFolders()
            changed = saveLocked(
                current.copy(
                    configuration = nextConfig,
                    cachedApplications = cached,
                ),
                markUserEdit = true,
            )
        }
        if (changed) onUserChange?.invoke()
    }

    fun remove(appId: String) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val targetApp = current.cachedApplication(appId)
            fun matches(ref: String): Boolean =
                ref == appId || (targetApp != null && current.matchesReference(ref, targetApp))
            val nextInstalled = current.configuration.installedApps.filterNot { matches(it.appId) }
            val nextDock = current.configuration.dockApps.filterNot { matches(it.appId) }
            if (nextInstalled.size == current.configuration.installedApps.size &&
                nextDock.size == current.configuration.dockApps.size
            ) {
                return@synchronized
            }
            val nextConfig = current.configuration.copy(
                installedApps = nextInstalled,
                dockApps = nextDock,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun remove(app: CatalogApp) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val nextInstalled = current.configuration.installedApps.filterNot {
                current.matchesReference(it.appId, app)
            }
            val nextDock = current.configuration.dockApps.filterNot {
                current.matchesReference(it.appId, app)
            }
            if (nextInstalled.size == current.configuration.installedApps.size &&
                nextDock.size == current.configuration.dockApps.size
            ) {
                return@synchronized
            }
            val nextConfig = current.configuration.copy(
                installedApps = nextInstalled,
                dockApps = nextDock,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun recordUse(app: CatalogApp) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val refId = current.configuration.installedApps
                .firstOrNull { current.matchesReference(it.appId, app) }?.appId
                ?: current.configuration.dockApps
                    .firstOrNull { current.matchesReference(it.appId, app) }?.appId
                ?: app.homeKey
            val filtered = current.configuration.recentApps.filterNot {
                current.matchesReference(it.appId, app) || it.appId == refId
            }
            val nextRecent = (listOf(HomeRecentReference(appId = refId, usedAt = nowMillis())) + filtered).take(100)
            val cached = upsertCachedLocked(current.cachedApplications, app)
            val nextSources = updateApplicationSource(
                sources = current.configuration.applicationSources,
                refId = refId,
                app = app,
            )
            val nextConfig = current.configuration.copy(
                recentApps = nextRecent,
                updatedAt = nowMillis(),
                applicationSources = nextSources,
            ).sanitizingFolders()
            changed = saveLocked(
                current.copy(
                    configuration = nextConfig,
                    cachedApplications = cached,
                ),
                markUserEdit = true,
            )
        }
        if (changed) onUserChange?.invoke()
    }

    fun clearRecent() {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            if (current.configuration.recentApps.isEmpty()) return@synchronized
            val nextConfig = current.configuration.copy(
                recentApps = emptyList(),
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun setPinned(app: CatalogApp, pinned: Boolean) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val existingRef = current.configuration.dockApps
                .firstOrNull { current.matchesReference(it.appId, app) }?.appId
                ?: current.configuration.installedApps
                    .firstOrNull { current.matchesReference(it.appId, app) }?.appId
                ?: app.homeKey
            val nextDock = if (pinned) {
                if (current.configuration.dockApps.any { current.matchesReference(it.appId, app) }) {
                    current.configuration.dockApps
                } else {
                    (current.configuration.dockApps + HomeAppReference(existingRef)).take(4)
                }
            } else {
                current.configuration.dockApps.filterNot { current.matchesReference(it.appId, app) }
            }
            val nextInstalled = if (!pinned && !current.isInstalled(app)) {
                current.configuration.installedApps + HomeAppReference(existingRef)
            } else {
                current.configuration.installedApps
            }
            val cached = upsertCachedLocked(current.cachedApplications, app)
            val nextSources = updateApplicationSource(
                sources = current.configuration.applicationSources,
                refId = existingRef,
                app = app,
            )
            val nextConfig = current.configuration.copy(
                installedApps = nextInstalled,
                dockApps = nextDock,
                updatedAt = nowMillis(),
                applicationSources = nextSources,
            ).sanitizingFolders()
            changed = saveLocked(
                current.copy(
                    configuration = nextConfig,
                    cachedApplications = cached,
                ),
                markUserEdit = true,
            )
        }
        if (changed) onUserChange?.invoke()
    }

    fun setPinned(apps: List<CatalogApp>, pinned: Boolean): Boolean {
        if (apps.isEmpty()) return true
        var result = false
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val existingDock = current.configuration.dockApps.toMutableList()
            val resolvedKeys = apps.map { app ->
                current.configuration.dockApps
                    .firstOrNull { current.matchesReference(it.appId, app) }?.appId
                    ?: current.configuration.installedApps
                        .firstOrNull { current.matchesReference(it.appId, app) }?.appId
                    ?: app.homeKey
            }.distinct()

            if (pinned) {
                val present = existingDock.mapTo(mutableSetOf()) { it.appId }
                val toAdd = resolvedKeys.filter { !present.contains(it) }
                if (existingDock.size + toAdd.size > 4) {
                    return@synchronized
                }
                existingDock.addAll(toAdd.map(::HomeAppReference))
            } else {
                val removeSet = resolvedKeys.toSet()
                existingDock.removeAll { ref ->
                    removeSet.contains(ref.appId) || apps.any { current.matchesReference(ref.appId, it) }
                }
            }

            val nextInstalled = if (!pinned) {
                val installedSet = current.configuration.installedApps.mapTo(mutableSetOf()) { it.appId }
                val appended = resolvedKeys.filter { !installedSet.contains(it) }.map(::HomeAppReference)
                current.configuration.installedApps + appended
            } else {
                current.configuration.installedApps
            }

            var cached = current.cachedApplications
            var nextSources = current.configuration.applicationSources
            for (index in apps.indices) {
                val app = apps[index]
                cached = upsertCachedLocked(cached, app)
                val ref = resolvedKeys.getOrElse(index) { app.homeKey }
                nextSources = updateApplicationSource(nextSources, refId = ref, app = app)
            }
            val nextConfig = current.configuration.copy(
                installedApps = nextInstalled,
                dockApps = existingDock,
                updatedAt = nowMillis(),
                applicationSources = nextSources,
            ).sanitizingFolders()
            result = true
            if (nextConfig != current.configuration || cached != current.cachedApplications) {
                changed = saveLocked(
                    current.copy(
                        configuration = nextConfig,
                        cachedApplications = cached,
                    ),
                    markUserEdit = true,
                )
            }
        }
        if (changed) onUserChange?.invoke()
        return result
    }

    fun reorder(keys: List<String>, inDock: Boolean) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val refs = (if (inDock) current.configuration.dockApps else current.configuration.installedApps).toMutableList()
            val present = refs.mapTo(mutableSetOf()) { it.appId }
            val seen = mutableSetOf<String>()
            val ordered = keys.filter { present.contains(it) && seen.add(it) }
            val slots = refs.indices.filter { seen.contains(refs[it].appId) }
            if (slots.size != ordered.size || ordered.isEmpty()) return@synchronized
            val byKey = slots.associate { slot -> refs[slot].appId to refs[slot] }
            for (i in slots.indices) {
                val item = byKey[ordered[i]] ?: continue
                refs[slots[i]] = item
            }
            val nextConfig = if (inDock) {
                current.configuration.copy(dockApps = refs, updatedAt = nowMillis())
            } else {
                current.configuration.copy(installedApps = refs, updatedAt = nowMillis())
            }.sanitizingFolders()
            if (nextConfig == current.configuration) return@synchronized
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun reorderItems(itemKeys: List<String>) {
        val expanded = synchronized(lock) {
            val folders = _snapshot.value.configuration.folders.associate {
                HomeGridItem.folderKey(it.id) to it.appIds
            }
            itemKeys.flatMap { folders[it] ?: listOf(it) }
        }
        reorder(expanded, inDock = false)
    }

    fun createFolder(name: String, keys: List<String>, anchor: String): String? {
        var createdId: String? = null
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val installed = current.configuration.installedApps.mapTo(mutableSetOf()) { it.appId }
            val members = keys.filter { installed.contains(it) }.distinct()
            if (members.isEmpty() || current.configuration.folders.size >= HomeFolder.LIMIT) return@synchronized
            val id = UUID.randomUUID().toString().lowercase()
            val cleanName = folderName(name)
            val memberSet = members.toSet()
            val updatedFolders = current.configuration.folders.map { folder ->
                folder.copy(appIds = folder.appIds.filterNot { memberSet.contains(it) })
            } + HomeFolder(id = id, name = cleanName, appIds = members)
            val nextDock = current.configuration.dockApps.filterNot { memberSet.contains(it.appId) }
            val gatheredInstalled = gathering(members, anchor = anchor, apps = current.configuration.installedApps)
            val nextConfig = current.configuration.copy(
                installedApps = gatheredInstalled,
                dockApps = nextDock,
                folders = updatedFolders,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            if (saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)) {
                changed = true
                createdId = id
            }
        }
        if (changed) onUserChange?.invoke()
        return createdId
    }

    fun addToFolder(folderId: String, keys: List<String>) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val folder = current.configuration.folders.firstOrNull { it.id == folderId } ?: return@synchronized
            val installed = current.configuration.installedApps.mapTo(mutableSetOf()) { it.appId }
            val adding = keys.filter { installed.contains(it) && !folder.appIds.contains(it) }.distinct()
            val anchor = folder.appIds.lastOrNull() ?: return@synchronized
            if (adding.isEmpty()) return@synchronized
            val addingSet = adding.toSet()
            val updatedFolders = current.configuration.folders.map { existing ->
                when (existing.id) {
                    folderId -> existing.copy(appIds = existing.appIds + adding)
                    else -> existing.copy(appIds = existing.appIds.filterNot { addingSet.contains(it) })
                }
            }
            val nextDock = current.configuration.dockApps.filterNot { addingSet.contains(it.appId) }
            val gathered = gathering(folder.appIds + adding, anchor = anchor, apps = current.configuration.installedApps)
            val nextConfig = current.configuration.copy(
                installedApps = gathered,
                dockApps = nextDock,
                folders = updatedFolders,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun removeFromFolder(key: String) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val folder = current.configuration.folders.firstOrNull { it.appIds.contains(key) } ?: return@synchronized
            val rest = folder.appIds.filterNot { it == key }
            val updatedFolders = current.configuration.folders.map { existing ->
                if (existing.id == folder.id) existing.copy(appIds = rest) else existing
            }
            val apps = current.configuration.installedApps.toMutableList()
            val from = apps.indexOfFirst { it.appId == key }
            if (from >= 0) {
                val moving = apps.removeAt(from)
                val restSet = rest.toSet()
                val after = apps.indexOfLast { restSet.contains(it.appId) }.let { if (it >= 0) it + 1 else from }
                apps.add(after.coerceAtMost(apps.size), moving)
            }
            val nextConfig = current.configuration.copy(
                installedApps = apps,
                folders = updatedFolders,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun renameFolder(folderId: String, name: String) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val cleanName = folderName(name)
            val updatedFolders = current.configuration.folders.map { folder ->
                if (folder.id == folderId) folder.copy(name = cleanName) else folder
            }
            val nextConfig = current.configuration.copy(
                folders = updatedFolders,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            if (nextConfig == current.configuration) return@synchronized
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun dissolveFolder(folderId: String) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val updatedFolders = current.configuration.folders.filterNot { it.id == folderId }
            if (updatedFolders.size == current.configuration.folders.size) return@synchronized
            val nextConfig = current.configuration.copy(
                folders = updatedFolders,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun reorderFolder(folderId: String, appIds: List<String>) {
        var changed = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val folder = current.configuration.folders.firstOrNull { it.id == folderId } ?: return@synchronized
            if (appIds.size != folder.appIds.size || appIds.toSet() != folder.appIds.toSet()) return@synchronized
            val firstAnchor = folder.appIds.firstOrNull() ?: return@synchronized
            val updatedFolders = current.configuration.folders.map { existing ->
                if (existing.id == folderId) existing.copy(appIds = appIds) else existing
            }
            val gathered = gathering(appIds, anchor = firstAnchor, apps = current.configuration.installedApps)
            val nextConfig = current.configuration.copy(
                installedApps = gathered,
                folders = updatedFolders,
                updatedAt = nowMillis(),
            ).sanitizingFolders()
            if (nextConfig == current.configuration) return@synchronized
            changed = saveLocked(current.copy(configuration = nextConfig), markUserEdit = true)
        }
        if (changed) onUserChange?.invoke()
    }

    fun setDockVisible(visible: Boolean) {
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            if (current.dockVisible == visible) return@synchronized
            saveLocked(current.copy(dockVisible = visible), markUserEdit = false)
        }
    }

    fun updateCatalog(applications: List<CatalogApp>) = cache(applications)

    fun cache(applications: List<CatalogApp>) {
        if (applications.isEmpty()) return
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            val byId = current.cachedApplications.associateByTo(linkedMapOf()) { it.id }
            val byKey = applications.filter { it.key.isNotEmpty() }.groupBy { it.key }
            val bySlug = applications.filter { !it.slug.isNullOrEmpty() }.groupBy { it.slug!! }
            val incomingById = applications.associateBy { it.id }
            val referenced = (
                current.installedIds +
                    current.dockIds +
                    current.configuration.recentApps.map { it.appId }
                ).toSet()
            var anyChanged = false
            for (ref in referenced) {
                val resolved = incomingById[ref]
                    ?: byKey[ref]?.singleOrNull()
                    ?: bySlug[ref]?.singleOrNull()
                    ?: continue
                val existing = byId[resolved.id]
                if (existing != resolved) {
                    byId[resolved.id] = resolved
                    anyChanged = true
                }
            }
            for ((existingId, existingApp) in current.cachedApplications.associateBy { it.id }) {
                val updated = incomingById[existingId]
                if (updated != null && updated != existingApp) {
                    byId[existingId] = updated
                    anyChanged = true
                }
            }
            if (!anyChanged) return@synchronized
            saveLocked(current.copy(cachedApplications = byId.values.toList()), markUserEdit = false)
        }
    }

    fun pendingWrite(): Pair<HomeScreenWrite, Int>? = synchronized(lock) {
        if (!canWrite) return@synchronized null
        val current = _snapshot.value
        if (!current.syncEnabled) return@synchronized null
        val needsPush = current.hasPendingChanges ||
            (current.base == null && current.configuration != HomeConfiguration())
        if (!needsPush) return@synchronized null
        HomeScreenWrite(
            baseRevision = current.base?.revision,
            mutationId = current.mutationId,
            configuration = current.configuration,
        ) to _generation.value
    }

    fun adopt(remote: RemoteHomeScreen, expectedAccountId: String?, catalog: List<CatalogApp> = emptyList()) {
        synchronized(lock) {
            if (!canWrite || _activeAccountId != expectedAccountId) return@synchronized
            val current = _snapshot.value
            if (current.hasPendingChanges) return@synchronized
            val adopted = current.configuration.adopting(remote)
            val mergedCache = mergeCatalogIntoCache(current.cachedApplications, adopted, catalog)
            saveLocked(
                current.copy(
                    configuration = adopted,
                    cachedApplications = mergedCache,
                    base = remote,
                    mutationId = UUID.randomUUID().toString(),
                    hasPendingChanges = false,
                    lastSyncedAtMillis = nowMillis(),
                ),
                markUserEdit = false,
            )
        }
    }

    fun acknowledge(remote: RemoteHomeScreen, writeGeneration: Int, expectedAccountId: String?) {
        synchronized(lock) {
            if (!canWrite || _activeAccountId != expectedAccountId) return@synchronized
            val current = _snapshot.value
            val matchingGeneration = _generation.value == writeGeneration
            saveLocked(
                current.copy(
                    base = remote,
                    hasPendingChanges = if (matchingGeneration) false else current.hasPendingChanges,
                    mutationId = if (matchingGeneration) UUID.randomUUID().toString() else current.mutationId,
                    lastSyncedAtMillis = nowMillis(),
                ),
                markUserEdit = false,
            )
        }
    }

    fun keepDevice(remote: RemoteHomeScreen, expectedAccountId: String?) {
        synchronized(lock) {
            if (!canWrite || _activeAccountId != expectedAccountId) return@synchronized
            val current = _snapshot.value
            saveLocked(
                current.copy(
                    base = remote,
                    hasPendingChanges = true,
                ),
                markUserEdit = true,
            )
        }
    }

    fun keepCloud(remote: RemoteHomeScreen, expectedAccountId: String?, catalog: List<CatalogApp> = emptyList()) {
        synchronized(lock) {
            if (!canWrite || _activeAccountId != expectedAccountId) return@synchronized
            writeBackupLocked(HomeBackupKind.CONFLICT)
            _generation.value += 1
            val current = _snapshot.value
            val adopted = current.configuration.adopting(remote)
            val mergedCache = mergeCatalogIntoCache(current.cachedApplications, adopted, catalog)
            saveLocked(
                current.copy(
                    configuration = adopted,
                    cachedApplications = mergedCache,
                    base = remote,
                    hasPendingChanges = false,
                    lastSyncedAtMillis = nowMillis(),
                ),
                markUserEdit = false,
            )
        }
    }

    fun restoreBackup(
        restored: HomeLibrarySnapshot,
        restoreSettings: Boolean,
        restoreId: String,
        expectedAccountId: String?,
        expectedGeneration: Int,
    ): Boolean {
        var restoredOk = false
        synchronized(lock) {
            if (_activeAccountId != expectedAccountId || _generation.value != expectedGeneration) {
                return@synchronized
            }
            val current = _snapshot.value
            if (current.lastRestoreId == restoreId) {
                restoredOk = true
                return@synchronized
            }
            writeBackupLocked(HomeBackupKind.RESTORE)
            val mergedCache = (restored.cachedApplications + current.cachedApplications)
                .associateBy { it.id }
                .values
                .toList()
            val nextConfig = restored.configuration
                .copy(updatedAt = nowMillis())
                .sanitizingFolders()
            val next = current.copy(
                configuration = nextConfig,
                cachedApplications = mergedCache,
                lastRestoreId = restoreId,
                syncEnabled = if (restoreSettings) restored.syncEnabled else current.syncEnabled,
                autoSyncEnabled = if (restoreSettings) restored.autoSyncEnabled else current.autoSyncEnabled,
                dockVisible = if (restoreSettings) restored.dockVisible else current.dockVisible,
            )
            val previousCanWrite = canWrite
            canWrite = true
            restoredOk = saveLocked(next, markUserEdit = true)
            if (!restoredOk) {
                canWrite = previousCanWrite
            }
        }
        if (restoredOk) onUserChange?.invoke()
        return restoredOk
    }

    fun importLegacy(record: LegacyLocalData, expectedAccountId: String?, expectedGeneration: Int): Boolean {
        synchronized(lock) {
            if (activeAccountId != expectedAccountId || _generation.value != expectedGeneration) {
                throw LegacyImportException(LegacyImportError.IDENTITY_CHANGED)
            }
            val current = _snapshot.value
            if (!canWrite) throw LegacyImportException(LegacyImportError.STORAGE)
            if (current.legacyImportId == record.id) return true

            val configuration = record.configuration ?: current.configuration
            configuration.validate()
            if (!writeBackupLocked(HomeBackupKind.LEGACY, record.id)) {
                throw LegacyImportException(LegacyImportError.STORAGE)
            }
            val next = current.copy(
                configuration = configuration,
                syncEnabled = record.syncEnabled ?: current.syncEnabled,
                autoSyncEnabled = record.autoSyncEnabled ?: current.autoSyncEnabled,
                dockVisible = record.dockVisible ?: current.dockVisible,
                legacyImportId = record.id,
            )
            if (!saveLocked(next, markUserEdit = true, durable = true)) {
                throw LegacyImportException(LegacyImportError.STORAGE)
            }
        }
        onUserChange?.invoke()
        return true
    }

    fun setSyncEnabled(enabled: Boolean) {
        var shouldTrigger = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            if (current.syncEnabled == enabled) return@synchronized
            saveLocked(current.copy(syncEnabled = enabled), markUserEdit = false)
            shouldTrigger = enabled && current.autoSyncEnabled
        }
        if (shouldTrigger) onUserChange?.invoke()
    }

    fun setAutoSyncEnabled(enabled: Boolean) {
        var shouldTrigger = false
        synchronized(lock) {
            if (!canWrite) return@synchronized
            val current = _snapshot.value
            if (current.autoSyncEnabled == enabled) return@synchronized
            saveLocked(current.copy(autoSyncEnabled = enabled), markUserEdit = false)
            shouldTrigger = enabled && current.syncEnabled
        }
        if (shouldTrigger) onUserChange?.invoke()
    }

    private fun mergeCatalogIntoCache(
        existing: List<CatalogApp>,
        configuration: HomeConfiguration,
        catalog: List<CatalogApp>,
    ): List<CatalogApp> {
        if (catalog.isEmpty()) return existing
        val map = existing.associateByTo(linkedMapOf()) { it.id }
        val byId = catalog.associateBy { it.id }
        val byKey = catalog.groupBy { it.key }
        val bySlug = catalog.filter { !it.slug.isNullOrEmpty() }.groupBy { it.slug!! }
        val references = configuration.installedApps.map { it.appId } +
            configuration.dockApps.map { it.appId } +
            configuration.recentApps.map { it.appId }
        for (ref in references) {
            val found = byId[ref]
                ?: byKey[ref]?.singleOrNull()
                ?: bySlug[ref]?.singleOrNull()
                ?: continue
            map[found.id] = found
        }
        return map.values.toList()
    }

    private fun upsertCachedLocked(existing: List<CatalogApp>, app: CatalogApp): List<CatalogApp> {
        val cleanApp = if (app.homeReference != null) app.copy(homeReference = null) else app
        val map = existing.associateByTo(linkedMapOf()) { it.id }
        map[cleanApp.id] = cleanApp
        return map.values.toList()
    }

    private fun updateApplicationSource(
        sources: List<HomeApplicationSource>,
        refId: String,
        app: CatalogApp,
    ): List<HomeApplicationSource> {
        if (app.launchUrl != null) return sources
        val owner = app.ownerLogin?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: return sources
        val filtered = sources.filterNot { it.appId == refId }
        return (filtered + HomeApplicationSource(appId = refId, ownerLogin = owner)).sortedBy { it.appId }
    }

    private fun writeBackupLocked(kind: HomeBackupKind, tokenSuffix: String? = null): Boolean {
        val token = when (kind) {
            HomeBackupKind.CONFLICT -> "conflict"
            HomeBackupKind.RESTORE -> "before-restore"
            HomeBackupKind.LEGACY -> "before-legacy"
            HomeBackupKind.NATIVE_MIGRATION -> return false
        }
        val ownerBase = currentFile.name.removeSuffix(".json")
        if (kind == HomeBackupKind.LEGACY) {
            val digestHex = tokenSuffix ?: return false
            val name = "$ownerBase.$token-$digestHex.json"
            // Validate the deterministic backup name with the same rules used to list it.
            if (HomeBackupRepository.kind(name, currentFile.name) != kind) return false
            val backup = File(directory, name)
            return try {
                if (Files.exists(backup.toPath(), LinkOption.NOFOLLOW_LINKS)) {
                    HomeBackupRepository(directory).preview(name, currentFile.name)
                } else {
                    // A first import can target a Home with no file yet.
                    val bytes = serializeSnapshot(_snapshot.value).toString().toByteArray()
                    if (bytes.size > HomeBackupRepository.MAXIMUM_BYTES) return false
                    writeLegacyMigrationFile(backup, bytes)
                }
                true
            } catch (_: Exception) {
                false
            }
        }
        if (!currentFile.exists()) return false
        return try {
            val path = currentFile.toPath()
            if (Files.isSymbolicLink(path) || !currentFile.isFile) return false
            if (currentFile.length() > HomeBackupRepository.MAXIMUM_BYTES) return false
            val bytes = currentFile.readBytes()
            if (bytes.size > HomeBackupRepository.MAXIMUM_BYTES) return false
            if (!directory.exists()) directory.mkdirs()
            val backupFile = File(directory, "$ownerBase.$token-${UUID.randomUUID().toString().lowercase()}.json")
            val temp = File(directory, "${backupFile.name}.tmp")
            temp.writeBytes(bytes)
            if (!temp.renameTo(backupFile)) {
                backupFile.writeBytes(bytes)
                temp.delete()
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun saveLocked(next: HomeLibrarySnapshot, markUserEdit: Boolean, durable: Boolean = false): Boolean {
        val finalNext = if (markUserEdit) {
            _generation.value += 1
            next.copy(
                version = 3,
                mutationId = UUID.randomUUID().toString(),
                hasPendingChanges = true,
            )
        } else {
            next.copy(version = 3)
        }
        return try {
            if (!directory.exists()) directory.mkdirs()
            val serialized = serializeSnapshot(finalNext).toString()
            if (durable) {
                writeLegacyMigrationFile(currentFile, serialized.toByteArray())
            } else {
                val temp = File(directory, "${currentFile.name}.tmp")
                temp.writeText(serialized, Charsets.UTF_8)
                if (!temp.renameTo(currentFile)) {
                    currentFile.writeText(serialized, Charsets.UTF_8)
                    temp.delete()
                }
            }
            _snapshot.value = finalNext
            _storageError.value = null
            true
        } catch (_: Throwable) {
            _storageError.value = "无法保存云居变更，请检查存储空间后重试。"
            false
        }
    }

    private fun fileForAccount(id: String?): File {
        val name = if (id.isNullOrEmpty()) {
            "guest"
        } else {
            Base64.getUrlEncoder().withoutPadding().encodeToString(id.toByteArray(Charsets.UTF_8))
        }
        return File(directory, "$name.json")
    }

    private fun serializeSnapshot(snapshot: HomeLibrarySnapshot): JSONObject =
        serializeSnapshotJson(snapshot)

    private fun parseSnapshot(json: JSONObject): HomeLibrarySnapshot =
        parseSnapshotJson(json)

    companion object {
        fun folderName(raw: String): String {
            val cleaned = raw.trim()
                .filterNot { it.code < 32 || it.code == 127 }
                .trim()
            return if (cleaned.isEmpty()) "文件夹" else cleaned.take(HomeFolder.NAME_LIMIT)
        }

        internal fun serializeSnapshotJson(snapshot: HomeLibrarySnapshot): JSONObject = JSONObject().apply {
            put("version", snapshot.version)
            put("configuration", snapshot.configuration.toJson())
            put("base", snapshot.base?.toJson() ?: JSONObject.NULL)
            put("mutationId", snapshot.mutationId)
            put("hasPendingChanges", snapshot.hasPendingChanges)
            put("syncEnabled", snapshot.syncEnabled)
            put("autoSyncEnabled", snapshot.autoSyncEnabled)
            put("dockVisible", snapshot.dockVisible)
            put("lastSyncedAtMillis", snapshot.lastSyncedAtMillis ?: JSONObject.NULL)
            put("lastRestoreId", snapshot.lastRestoreId ?: JSONObject.NULL)
            snapshot.legacyImportId?.let { put("legacyImportId", it) }
            put(
                "cachedApps",
                JSONArray().apply {
                    snapshot.cachedApplications.forEach { app ->
                        put(serializeCachedAppJson(app))
                    }
                },
            )
        }

        private fun serializeCachedAppJson(app: CatalogApp): JSONObject = JSONObject().apply {
            put("id", app.id)
            put("key", app.key)
            app.slug?.let { put("slug", it) }
            put("name", app.name)
            put("description", app.description)
            put("author", app.author)
            app.ownerLogin?.let { put("ownerLogin", it) }
            put("category", app.category)
            put("emoji", app.emoji)
            app.launchUrl?.let { put("launchUrl", it) }
            app.logo?.let { put("logo", it) }
            app.themeColor?.let { put("themeColor", it) }
            put("trustedHosts", JSONArray(app.trustedHosts))
            put("immersive", app.immersive)
        }

        internal fun parseSnapshotJson(json: JSONObject): HomeLibrarySnapshot {
            val cachedApplications = parseCachedAppsJson(json.optJSONArray("cachedApps"))
            val configJson = json.optJSONObject("configuration")
            return if (configJson != null) {
                val configuration = HomeConfiguration.fromJson(configJson)
                val baseJson = json.optJSONObject("base")
                val base = baseJson?.let { runCatching { RemoteHomeScreen.fromJson(it) }.getOrNull() }
                val lastSyncedAt = if (json.has("lastSyncedAtMillis") && !json.isNull("lastSyncedAtMillis")) {
                    json.optLong("lastSyncedAtMillis").takeIf { it > 0L }
                } else {
                    null
                }
                val lastRestoreId = json.optString("lastRestoreId")
                    .takeIf { it.isNotBlank() && !json.isNull("lastRestoreId") }
                HomeLibrarySnapshot(
                    version = 3,
                    configuration = configuration,
                    cachedApplications = cachedApplications,
                    base = base,
                    mutationId = json.optString("mutationId").ifEmpty { UUID.randomUUID().toString() },
                    hasPendingChanges = json.optBoolean("hasPendingChanges", false),
                    syncEnabled = json.optBoolean("syncEnabled", true),
                    autoSyncEnabled = json.optBoolean("autoSyncEnabled", true),
                    dockVisible = json.optBoolean("dockVisible", true),
                    lastSyncedAtMillis = lastSyncedAt,
                    lastRestoreId = lastRestoreId,
                    legacyImportId = json.opt("legacyImportId") as? String,
                )
            } else {
                // Backward compatibility with legacy M1 flat snapshot JSON
                val installed = parseRefArrayJson(json.optJSONArray("installedApps"))
                val dock = parseRefArrayJson(json.optJSONArray("dockApps")).take(4)
                val recentArray = json.optJSONArray("recentApps") ?: JSONArray()
                val recent = buildList {
                    for (i in 0 until recentArray.length()) {
                        val item = recentArray.optJSONObject(i) ?: continue
                        val appId = item.optString("appId").trim().takeIf { it.isNotEmpty() } ?: continue
                        val usedAt = item.optLong("usedAt", 0L).coerceAtLeast(0L)
                        add(HomeRecentReference(appId = appId, usedAt = usedAt))
                    }
                }
                val configuration = HomeConfiguration(
                    installedApps = installed,
                    dockApps = dock,
                    recentApps = recent,
                    updatedAt = json.optLong("updatedAt", 0L).coerceAtLeast(0L),
                )
                val hasLocalItems = installed.isNotEmpty() || dock.isNotEmpty() || recent.isNotEmpty()
                HomeLibrarySnapshot(
                    version = 3,
                    configuration = configuration,
                    cachedApplications = cachedApplications,
                    base = null,
                    mutationId = UUID.randomUUID().toString(),
                    hasPendingChanges = hasLocalItems,
                    syncEnabled = true,
                    autoSyncEnabled = true,
                    dockVisible = json.optBoolean("dockVisible", true),
                    lastSyncedAtMillis = null,
                )
            }
        }

        private fun parseRefArrayJson(array: JSONArray?): List<HomeAppReference> {
            if (array == null) return emptyList()
            val seen = mutableSetOf<String>()
            return buildList {
                for (i in 0 until array.length()) {
                    val ref = HomeAppReference.fromJson(array.opt(i)) ?: continue
                    if (seen.add(ref.appId)) add(ref)
                }
            }
        }

        private fun parseCachedAppsJson(cachedArray: JSONArray?): List<CatalogApp> {
            if (cachedArray == null) return emptyList()
            return buildList {
                for (i in 0 until cachedArray.length()) {
                    val item = cachedArray.optJSONObject(i) ?: continue
                    val id = item.optString("id").takeIf { it.isNotBlank() } ?: continue
                    val hostsArr = item.optJSONArray("trustedHosts")
                    val hosts = buildList {
                        if (hostsArr != null) {
                            for (t in 0 until hostsArr.length()) {
                                hostsArr.optString(t).takeIf { it.isNotBlank() }?.let { add(it) }
                            }
                        }
                    }
                    add(
                        CatalogApp(
                            id = id,
                            key = item.optString("key", id),
                            name = item.optString("name", id),
                            description = item.optString("description"),
                            author = item.optString("author", "独立开发者"),
                            ownerLogin = item.optString("ownerLogin").takeIf { it.isNotBlank() && !item.isNull("ownerLogin") },
                            category = item.optString("category", "生活"),
                            emoji = item.optString("emoji", "☁️"),
                            launchUrl = item.optString("launchUrl").takeIf { it.isNotBlank() && !item.isNull("launchUrl") },
                            logo = item.optString("logo").takeIf { it.isNotBlank() && !item.isNull("logo") },
                            themeColor = item.optString("themeColor").takeIf { it.isNotBlank() && !item.isNull("themeColor") },
                            trustedHosts = hosts,
                            immersive = item.optBoolean("immersive", false),
                            slug = item.optString("slug").takeIf { it.isNotBlank() && !item.isNull("slug") },
                        ),
                    )
                }
            }
        }

        private fun gathering(
            members: List<String>,
            anchor: String,
            apps: List<HomeAppReference>,
        ): List<HomeAppReference> {
            val anchorIndex = apps.indexOfFirst { it.appId == anchor }
            if (anchorIndex < 0) return apps
            val memberSet = members.toSet()
            val before = apps.subList(0, anchorIndex).count { !memberSet.contains(it.appId) }
            val rest = apps.filterNot { memberSet.contains(it.appId) }.toMutableList()
            val byId = apps.associateBy { it.appId }
            val moving = members.mapNotNull { byId[it] }
            rest.addAll(before.coerceAtMost(rest.size), moving)
            return rest
        }
    }
}
