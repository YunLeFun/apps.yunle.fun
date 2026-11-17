package `fun`.yunle.apps.ui.catalog

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.CatalogDataSource
import `fun`.yunle.apps.CatalogRepository
import `fun`.yunle.apps.HostSession
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal sealed interface CatalogFeedState {
    data object Loading : CatalogFeedState
    data class Loaded(val apps: List<CatalogApp>) : CatalogFeedState
    data object Error : CatalogFeedState
}

internal data class CatalogUiState(
    val feed: CatalogFeedState = CatalogFeedState.Loading,
    val query: String = "",
    val selectedCategory: String = CatalogViewModel.CATEGORY_ALL,
    val minimizedAppName: String? = null,
) {
    val availableCategories: List<String>
        get() {
            val apps = (feed as? CatalogFeedState.Loaded)?.apps ?: return listOf(CatalogViewModel.CATEGORY_ALL)
            return buildList {
                add(CatalogViewModel.CATEGORY_ALL)
                if (apps.any { it.isOfficial }) {
                    add(CatalogViewModel.CATEGORY_OFFICIAL)
                }
                val dynamicCategories = apps.map { it.browseCategory }
                    .distinct()
                    .filter { it.isNotBlank() && it != CatalogViewModel.CATEGORY_ALL && it != CatalogViewModel.CATEGORY_OFFICIAL }
                    .sorted()
                addAll(dynamicCategories)
            }
        }

    val filteredApps: List<CatalogApp>
        get() = when (feed) {
            is CatalogFeedState.Loaded -> {
                feed.apps.filter { app ->
                    val matchesCategory = when (selectedCategory) {
                        CatalogViewModel.CATEGORY_ALL -> true
                        CatalogViewModel.CATEGORY_OFFICIAL -> app.isOfficial
                        else -> app.browseCategory == selectedCategory
                    }
                    matchesCategory && (query.isBlank() || app.matches(query))
                }
            }
            else -> emptyList()
        }

    fun findApp(keyOrId: String?): CatalogApp? {
        if (keyOrId.isNullOrBlank()) return null
        val apps = (feed as? CatalogFeedState.Loaded)?.apps ?: return null
        return apps.firstOrNull { it.id == keyOrId || it.key == keyOrId }
    }
}

internal class CatalogViewModel(
    private val savedStateHandle: SavedStateHandle,
    private val dataSource: CatalogDataSource,
    private val ioDispatcher: CoroutineDispatcher,
    minimizedAppFlow: StateFlow<String?>,
    private val scopeOverride: CoroutineScope? = null,
) : ViewModel() {

    @Suppress("unused")
    constructor(savedStateHandle: SavedStateHandle) : this(
        savedStateHandle = savedStateHandle,
        dataSource = CatalogDataSource { CatalogRepository.loadActive() },
        ioDispatcher = Dispatchers.IO,
        minimizedAppFlow = HostSession.minimizedAppName,
    )

    private val activeScope: CoroutineScope
        get() = scopeOverride ?: viewModelScope

    private val feedState = MutableStateFlow<CatalogFeedState>(CatalogFeedState.Loading)
    private val queryFlow = savedStateHandle.getStateFlow(KEY_QUERY, "")
    private val categoryFlow = savedStateHandle.getStateFlow(KEY_CATEGORY, CATEGORY_ALL)
    private var loadJob: Job? = null

    val uiState: StateFlow<CatalogUiState> = combine(
        feedState,
        queryFlow,
        categoryFlow,
        minimizedAppFlow,
    ) { feed, query, category, minimizedName ->
        CatalogUiState(
            feed = feed,
            query = query,
            selectedCategory = category,
            minimizedAppName = minimizedName,
        )
    }.stateIn(
        scope = activeScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = CatalogUiState(
            feed = feedState.value,
            query = queryFlow.value,
            selectedCategory = categoryFlow.value,
            minimizedAppName = minimizedAppFlow.value,
        ),
    )

    val savedListIndex: Int
        get() = savedStateHandle.get<Int>(KEY_LIST_INDEX) ?: 0

    val savedListOffset: Int
        get() = savedStateHandle.get<Int>(KEY_LIST_OFFSET) ?: 0

    init {
        loadCatalog()
    }

    fun updateQuery(value: String) {
        if (savedStateHandle.get<String>(KEY_QUERY) == value) return
        savedStateHandle[KEY_QUERY] = value
        saveListPosition(0, 0)
    }

    fun updateCategory(value: String) {
        if (savedStateHandle.get<String>(KEY_CATEGORY) == value) return
        savedStateHandle[KEY_CATEGORY] = value
        saveListPosition(0, 0)
    }

    fun saveListPosition(index: Int, offset: Int) {
        savedStateHandle[KEY_LIST_INDEX] = index.coerceAtLeast(0)
        savedStateHandle[KEY_LIST_OFFSET] = offset.coerceAtLeast(0)
    }

    fun retry() {
        loadCatalog()
    }

    private fun loadCatalog() {
        loadJob?.cancel()
        feedState.value = CatalogFeedState.Loading
        loadJob = activeScope.launch {
            val result = runCatching {
                withContext(ioDispatcher) {
                    dataSource.load()
                }
            }
            feedState.value = result.fold(
                onSuccess = { CatalogFeedState.Loaded(it) },
                onFailure = { CatalogFeedState.Error },
            )
        }
    }

    companion object {
        const val CATEGORY_ALL = "全部"
        const val CATEGORY_OFFICIAL = "官方出品"
        private const val KEY_QUERY = "catalog_query"
        private const val KEY_CATEGORY = "catalog_category"
        private const val KEY_LIST_INDEX = "catalog_list_index"
        private const val KEY_LIST_OFFSET = "catalog_list_offset"
    }
}
