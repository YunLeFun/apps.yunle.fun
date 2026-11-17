package `fun`.yunle.apps.ui.catalog

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.scene.Scene
import androidx.navigation3.scene.SceneStrategy
import androidx.navigation3.scene.SceneStrategyScope
import kotlinx.serialization.Serializable

@Serializable
internal data object CatalogRoute : NavKey

@Serializable
internal data class DetailRoute(val appId: String) : NavKey

internal object CatalogPaneMetadata {
    private const val KEY_LIST_PANE = "fun.yunle.apps.pane.list"
    private const val KEY_DETAIL_PANE = "fun.yunle.apps.pane.detail"

    fun listPane(): Map<String, Any> = mapOf(KEY_LIST_PANE to true)
    fun detailPane(): Map<String, Any> = mapOf(KEY_DETAIL_PANE to true)

    fun isList(entry: NavEntry<NavKey>): Boolean = entry.metadata[KEY_LIST_PANE] == true
    fun isDetail(entry: NavEntry<NavKey>): Boolean = entry.metadata[KEY_DETAIL_PANE] == true
}

internal class ListDetailSceneStrategy(
    private val showTwoPane: Boolean,
) : SceneStrategy<NavKey> {
    override fun SceneStrategyScope<NavKey>.calculateScene(
        entries: List<NavEntry<NavKey>>,
    ): Scene<NavKey>? {
        if (!showTwoPane) return null
        val listEntry = entries.firstOrNull(CatalogPaneMetadata::isList) ?: return null
        val detailEntry = entries.lastOrNull(CatalogPaneMetadata::isDetail)
        val sceneEntries = listOfNotNull(listEntry, detailEntry)
        val previousEntries = if (detailEntry != null && entries.size > 1) {
            entries.dropLast(1)
        } else {
            emptyList()
        }
        return ListDetailScene(
            listEntry = listEntry,
            detailEntry = detailEntry,
            entries = sceneEntries,
            previousEntries = previousEntries,
        )
    }
}

private class ListDetailScene(
    private val listEntry: NavEntry<NavKey>,
    private val detailEntry: NavEntry<NavKey>?,
    override val entries: List<NavEntry<NavKey>>,
    override val previousEntries: List<NavEntry<NavKey>>,
) : Scene<NavKey> {
    override val key: Any = "catalog-list-detail"

    override val content: @Composable () -> Unit = {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Row(modifier = Modifier.fillMaxSize()) {
                Box(
                    modifier = Modifier
                        .weight(0.44f)
                        .fillMaxHeight(),
                ) {
                    listEntry.Content()
                }
                VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Box(
                    modifier = Modifier
                        .weight(0.56f)
                        .fillMaxHeight(),
                    contentAlignment = Alignment.Center,
                ) {
                    if (detailEntry != null) {
                        detailEntry.Content()
                    } else {
                        Text(
                            text = "选择一个应用查看详情",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
