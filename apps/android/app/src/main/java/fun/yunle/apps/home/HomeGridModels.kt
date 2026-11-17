package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp

internal object HomeEditOrder {
    /** Moves [key] so it ends at [index] in the result (clamped). */
    fun moving(key: String, inOrder: List<String>, toIndex: Int): List<String> {
        val from = inOrder.indexOf(key)
        if (from < 0) return inOrder
        val next = inOrder.toMutableList()
        next.removeAt(from)
        next.add(toIndex.coerceIn(0, next.size), key)
        return next
    }

    /** Final order after a drop: stacked apps land right after [afterPrimary] in pickup order. */
    fun landing(stack: List<String>, afterPrimary: String, inOrder: List<String>): List<String> {
        val stackSet = stack.toSet()
        val next = inOrder.filterNot { stackSet.contains(it) }.toMutableList()
        val index = next.indexOf(afterPrimary)
        if (index < 0) return inOrder
        next.addAll(index + 1, stack)
        return next
    }
}

internal sealed interface HomeGridItem {
    val id: String
    val name: String
    val appOrNull: CatalogApp?

    data class App(val app: CatalogApp) : HomeGridItem {
        override val id: String get() = app.homeKey
        override val name: String get() = app.name
        override val appOrNull: CatalogApp get() = app
    }

    data class Folder(
        val folder: HomeFolder,
        val apps: List<CatalogApp>,
    ) : HomeGridItem {
        override val id: String get() = folderKey(folder.id)
        override val name: String get() = folder.name
        override val appOrNull: CatalogApp? get() = null
    }

    companion object {
        fun folderKey(id: String): String = "folder:$id"

        fun items(apps: List<CatalogApp>, folders: List<HomeFolder>): List<HomeGridItem> {
            val lookup = LinkedHashMap<String, CatalogApp>(apps.size)
            for (app in apps) {
                lookup.putIfAbsent(app.homeKey, app)
            }
            val folderOf = HashMap<String, HomeFolder>()
            for (folder in folders) {
                for (key in folder.appIds) {
                    folderOf.putIfAbsent(key, folder)
                }
            }
            val emitted = HashSet<String>()
            val result = ArrayList<HomeGridItem>(apps.size)
            for (app in apps) {
                val folder = folderOf[app.homeKey]
                if (folder != null) {
                    if (!emitted.add(folder.id)) continue
                    val members = folder.appIds.mapNotNull { lookup[it] }
                    if (members.isNotEmpty()) {
                        result.add(Folder(folder = folder, apps = members))
                    }
                } else {
                    result.add(App(app))
                }
            }
            return result
        }

        fun suggestedFolderName(apps: List<CatalogApp>): String {
            val categories = apps.map { it.category.trim() }.filter { it.isNotEmpty() && it != "全部" }.toSet()
            return if (categories.size == 1) categories.first() else "文件夹"
        }
    }
}
