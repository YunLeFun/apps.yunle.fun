package `fun`.yunle.apps

import androidx.lifecycle.SavedStateHandle
import `fun`.yunle.apps.ui.catalog.CatalogFeedState
import `fun`.yunle.apps.ui.catalog.CatalogUiState
import `fun`.yunle.apps.ui.catalog.CatalogViewModel
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogViewModelTest {
    private fun sampleApps() = listOf(
        CatalogApp(
            id = "app_cook",
            key = "cook",
            name = "今天来做菜",
            description = "菜谱与食材灵感",
            author = "云乐坊",
            ownerLogin = "yunle",
            category = "生活",
            emoji = "🍳",
            launchUrl = "https://cook.yunle.fun/home",
            logo = null,
            themeColor = "#005DB3",
            trustedHosts = listOf("cook.yunle.fun"),
            immersive = false,
        ),
        CatalogApp(
            id = "app_notes",
            key = "notes",
            name = "随手记",
            description = "会员专享笔记",
            author = "云乐坊",
            ownerLogin = "yunle",
            category = "效率",
            emoji = "📝",
            launchUrl = null,
            logo = null,
            themeColor = null,
            trustedHosts = emptyList(),
            immersive = false,
        ),
    )

    private suspend fun CatalogViewModel.awaitState(
        predicate: (CatalogUiState) -> Boolean,
    ): CatalogUiState = withTimeout(3_000) {
        uiState.first(predicate)
    }

    @Test
    fun loadsCatalogOnceAndFindsAppsByIdOrKey() = runBlocking {
        val calls = AtomicInteger(0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val viewModel = CatalogViewModel(
            savedStateHandle = SavedStateHandle(),
            dataSource = CatalogDataSource {
                calls.incrementAndGet()
                sampleApps()
            },
            ioDispatcher = Dispatchers.Unconfined,
            minimizedAppFlow = MutableStateFlow(null),
            scopeOverride = scope,
        )
        try {
            val loaded = viewModel.awaitState { it.feed is CatalogFeedState.Loaded }
            assertEquals(1, calls.get())
            assertEquals(2, loaded.filteredApps.size)
            assertEquals("cook", loaded.findApp("app_cook")?.key)
            assertEquals("app_cook", loaded.findApp("cook")?.id)
            assertNull(loaded.findApp("missing"))
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun retriesAfterErrorAndTransitionsToLoaded() = runBlocking {
        val calls = AtomicInteger(0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val viewModel = CatalogViewModel(
            savedStateHandle = SavedStateHandle(),
            dataSource = CatalogDataSource {
                if (calls.incrementAndGet() == 1) throw IOException("offline")
                sampleApps()
            },
            ioDispatcher = Dispatchers.Unconfined,
            minimizedAppFlow = MutableStateFlow(null),
            scopeOverride = scope,
        )
        try {
            val failed = viewModel.awaitState { it.feed is CatalogFeedState.Error }
            assertTrue(failed.filteredApps.isEmpty())

            viewModel.retry()
            val recovered = viewModel.awaitState { it.feed is CatalogFeedState.Loaded }
            assertEquals(2, calls.get())
            assertEquals(2, recovered.filteredApps.size)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun savedStateHandlePreservesSearchQueryAndListPositionAcrossRecreation() = runBlocking {
        val handle = SavedStateHandle()
        val firstScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val firstVm = CatalogViewModel(
            savedStateHandle = handle,
            dataSource = CatalogDataSource { sampleApps() },
            ioDispatcher = Dispatchers.Unconfined,
            minimizedAppFlow = MutableStateFlow(null),
            scopeOverride = firstScope,
        )
        try {
            firstVm.awaitState { it.feed is CatalogFeedState.Loaded }
            firstVm.saveListPosition(index = 4, offset = 72)
            assertEquals(4, firstVm.savedListIndex)
            assertEquals(72, firstVm.savedListOffset)

            firstVm.updateQuery("做菜")
            val filtered = firstVm.awaitState { it.query == "做菜" }
            assertEquals(listOf("app_cook"), filtered.filteredApps.map { it.id })
            assertEquals(0, firstVm.savedListIndex)
            assertEquals(0, firstVm.savedListOffset)

            firstVm.saveListPosition(index = 2, offset = 48)
        } finally {
            firstScope.cancel()
        }

        val secondScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recreatedVm = CatalogViewModel(
            savedStateHandle = handle,
            dataSource = CatalogDataSource { sampleApps() },
            ioDispatcher = Dispatchers.Unconfined,
            minimizedAppFlow = MutableStateFlow(null),
            scopeOverride = secondScope,
        )
        try {
            val restored = recreatedVm.awaitState { it.feed is CatalogFeedState.Loaded }
            assertEquals("做菜", restored.query)
            assertEquals(listOf("app_cook"), restored.filteredApps.map { it.id })
            assertEquals(2, recreatedVm.savedListIndex)
            assertEquals(48, recreatedVm.savedListOffset)
        } finally {
            secondScope.cancel()
        }
    }

    @Test
    fun reflectsMinimizedSessionStateChanges() = runBlocking {
        val minimized = MutableStateFlow<String?>("今天来做菜")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val viewModel = CatalogViewModel(
            savedStateHandle = SavedStateHandle(),
            dataSource = CatalogDataSource { sampleApps() },
            ioDispatcher = Dispatchers.Unconfined,
            minimizedAppFlow = minimized,
            scopeOverride = scope,
        )
        try {
            val initial = viewModel.awaitState { it.minimizedAppName == "今天来做菜" }
            assertEquals("今天来做菜", initial.minimizedAppName)

            minimized.value = null
            val cleared = viewModel.awaitState { it.minimizedAppName == null }
            assertNull(cleared.minimizedAppName)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun filtersByCategoryAndOfficialBadge() = runBlocking {
        val mixedApps = listOf(
            sampleApps()[0].copy(isOfficial = true, rating = 4.9),
            sampleApps()[1].copy(isOfficial = false, rating = 4.6),
        )
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val viewModel = CatalogViewModel(
            savedStateHandle = SavedStateHandle(),
            dataSource = CatalogDataSource { mixedApps },
            ioDispatcher = Dispatchers.Unconfined,
            minimizedAppFlow = MutableStateFlow(null),
            scopeOverride = scope,
        )
        try {
            val loaded = viewModel.awaitState { it.feed is CatalogFeedState.Loaded }
            assertEquals(listOf("全部", "官方出品", "效率", "生活"), loaded.availableCategories)

            viewModel.updateCategory("官方出品")
            val official = viewModel.awaitState { it.selectedCategory == "官方出品" }
            assertEquals(listOf("app_cook"), official.filteredApps.map { it.id })

            viewModel.updateCategory("效率")
            val efficiency = viewModel.awaitState { it.selectedCategory == "效率" }
            assertEquals(listOf("app_notes"), efficiency.filteredApps.map { it.id })

            viewModel.updateCategory("全部")
            val all = viewModel.awaitState { it.selectedCategory == "全部" }
            assertEquals(2, all.filteredApps.size)
        } finally {
            scope.cancel()
        }
    }
}
