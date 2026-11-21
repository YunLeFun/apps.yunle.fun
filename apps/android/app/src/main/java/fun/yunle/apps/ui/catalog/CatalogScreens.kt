package `fun`.yunle.apps.ui.catalog

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import `fun`.yunle.apps.BoundedHttpsImageLoader
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.R
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.ui.account.AccountAvatar
import java.util.Locale
import kotlinx.coroutines.flow.distinctUntilChanged

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CatalogScreen(
    uiState: CatalogUiState,
    selectedAppId: String?,
    initialListIndex: Int,
    initialListOffset: Int,
    homeInstalledIds: Set<String> = emptySet(),
    activeUser: AccountUser? = null,
    onQueryChange: (String) -> Unit,
    onCategoryChange: (String) -> Unit = {},
    onSaveScrollPosition: (Int, Int) -> Unit,
    onRetry: () -> Unit,
    onOpenAccount: () -> Unit,
    onResumeSession: () -> Unit,
    onSelectApp: (CatalogApp) -> Unit,
    onLaunchApp: (CatalogApp) -> Unit = {},
    onToggleHome: ((CatalogApp) -> Unit)? = null,
    onOpenMyWorkshops: (() -> Unit)? = null,
    onOpenWorkshopLookup: (() -> Unit)? = null,
    onOpenScanOrLink: (() -> Unit)? = null,
) {
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = initialListIndex,
        initialFirstVisibleItemScrollOffset = initialListOffset,
    )
    var previousQuery by rememberSaveable { mutableStateOf(uiState.query) }
    var previousCategory by rememberSaveable { mutableStateOf(uiState.selectedCategory) }

    LaunchedEffect(uiState.query, uiState.selectedCategory) {
        if (previousQuery != uiState.query || previousCategory != uiState.selectedCategory) {
            previousQuery = uiState.query
            previousCategory = uiState.selectedCategory
            listState.scrollToItem(0)
        }
    }

    LaunchedEffect(listState) {
        snapshotFlow {
            listState.firstVisibleItemIndex to listState.firstVisibleItemScrollOffset
        }
            .distinctUntilChanged()
            .collect { (index, offset) ->
                onSaveScrollPosition(index, offset)
            }
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "云乐坊",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
                },
                actions = {
                    IconButton(
                        onClick = onOpenAccount,
                        modifier = Modifier.semantics { contentDescription = "账号" },
                    ) {
                        if (activeUser != null) {
                            Box(modifier = Modifier.clearAndSetSemantics {}) {
                                AccountAvatar(user = activeUser, size = 32.dp)
                            }
                        } else {
                            Icon(
                                painter = painterResource(R.drawable.ic_catalog_account),
                                contentDescription = null,
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .imePadding(),
        ) {
            uiState.minimizedAppName?.let { minimizedName ->
                ResumeSessionBanner(
                    appName = minimizedName,
                    onResume = onResumeSession,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                )
            }

            WorkshopSearchHeader(
                query = uiState.query,
                categories = uiState.availableCategories,
                selectedCategory = uiState.selectedCategory,
                showCategories = uiState.feed is CatalogFeedState.Loaded && uiState.availableCategories.size > 1,
                onQueryChange = onQueryChange,
                onCategoryChange = { category ->
                    keyboardController?.hide()
                    focusManager.clearFocus()
                    onCategoryChange(category)
                },
                onSearchSubmit = {
                    keyboardController?.hide()
                    focusManager.clearFocus()
                },
            )

            when (uiState.feed) {
                CatalogFeedState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.semantics {
                                contentDescription = "正在加载应用"
                            },
                        )
                    }
                }

                CatalogFeedState.Error -> {
                    CatalogStatusMessage(
                        message = "暂时无法加载应用，请检查网络。",
                        actionLabel = "重试",
                        onAction = onRetry,
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                    )
                }

                is CatalogFeedState.Loaded -> {
                    val matches = uiState.filteredApps
                    if (matches.isEmpty()) {
                        val hasQuery = uiState.query.isNotBlank()
                        val hasCategory = uiState.selectedCategory != CatalogViewModel.CATEGORY_ALL
                        CatalogStatusMessage(
                            message = if (hasQuery || hasCategory) "没有找到符合条件的应用。" else "暂无可用应用。",
                            actionLabel = when {
                                hasQuery -> "清除搜索"
                                hasCategory -> "显示全部"
                                else -> "刷新"
                            },
                            onAction = {
                                keyboardController?.hide()
                                focusManager.clearFocus()
                                when {
                                    hasQuery -> onQueryChange("")
                                    hasCategory -> onCategoryChange(CatalogViewModel.CATEGORY_ALL)
                                    else -> onRetry()
                                }
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f),
                        )
                    } else {
                        val isBrowsingAll = uiState.query.isBlank() &&
                            uiState.selectedCategory == CatalogViewModel.CATEGORY_ALL
                        val spotlightApps = remember(matches) {
                            pickSpotlightApps(matches)
                        }

                        LazyColumn(
                            state = listState,
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f),
                            contentPadding = PaddingValues(top = 4.dp, bottom = 24.dp),
                        ) {
                            if (isBrowsingAll && spotlightApps.isNotEmpty()) {
                                item(key = "workshop_spotlight") {
                                    FeaturedSpotlightSection(
                                        apps = spotlightApps,
                                        homeInstalledIds = homeInstalledIds,
                                        onSelectApp = { app ->
                                            keyboardController?.hide()
                                            focusManager.clearFocus()
                                            onSelectApp(app)
                                        },
                                    )
                                }
                            }

                            item(key = "workshop_list_header") {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(start = 16.dp, end = 12.dp, top = 8.dp, bottom = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Text(
                                        text = when {
                                            uiState.query.isNotBlank() -> "搜索结果 · ${matches.size}"
                                            uiState.selectedCategory != CatalogViewModel.CATEGORY_ALL ->
                                                "${uiState.selectedCategory} · ${matches.size}"
                                            else -> "热门榜单 · ${matches.size}"
                                        },
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.semantics { heading() },
                                    )
                                    if (uiState.selectedCategory != CatalogViewModel.CATEGORY_ALL) {
                                        TextButton(
                                            onClick = { onCategoryChange(CatalogViewModel.CATEGORY_ALL) },
                                        ) {
                                            Text(text = "显示全部")
                                        }
                                    }
                                }
                            }

                            itemsIndexed(
                                items = matches,
                                key = { _, app -> app.id },
                            ) { index, app ->
                                val isSelected = selectedAppId != null &&
                                    (selectedAppId == app.id || selectedAppId == app.key)
                                val isInHome = homeInstalledIds.contains(app.id) ||
                                    homeInstalledIds.contains(app.key) ||
                                    homeInstalledIds.contains(app.homeKey)
                                PlayStoreAppRow(
                                    app = app,
                                    rank = if (isBrowsingAll) index + 1 else null,
                                    selected = isSelected,
                                    isInHome = isInHome,
                                    onClick = {
                                        keyboardController?.hide()
                                        focusManager.clearFocus()
                                        onSelectApp(app)
                                    },
                                    onLaunch = {
                                        keyboardController?.hide()
                                        focusManager.clearFocus()
                                        onLaunchApp(app)
                                    },
                                    onToggleHome = onToggleHome?.let { toggle ->
                                        {
                                            keyboardController?.hide()
                                            focusManager.clearFocus()
                                            toggle(app)
                                        }
                                    },
                                )
                                if (index < matches.lastIndex) {
                                    HorizontalDivider(
                                        modifier = Modifier.padding(
                                            start = if (isBrowsingAll) 104.dp else 84.dp,
                                            end = 16.dp,
                                        ),
                                        thickness = 0.5.dp,
                                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                                    )
                                }
                            }

                            if (onOpenMyWorkshops != null || onOpenWorkshopLookup != null || onOpenScanOrLink != null) {
                                item(key = "workshop_footer_shortcuts") {
                                    Surface(
                                        shape = MaterialTheme.shapes.large,
                                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                                        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp, vertical = 14.dp),
                                    ) {
                                        Column(
                                            modifier = Modifier.padding(14.dp),
                                            verticalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            Text(
                                                text = "工坊入口",
                                                style = MaterialTheme.typography.titleSmall,
                                                fontWeight = FontWeight.SemiBold,
                                            )
                                            FlowRow(
                                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                                verticalArrangement = Arrangement.spacedBy(8.dp),
                                            ) {
                                                onOpenMyWorkshops?.let { openMine ->
                                                    OutlinedButton(onClick = openMine) {
                                                        Text("个人工坊")
                                                    }
                                                }
                                                onOpenWorkshopLookup?.let { openLookup ->
                                                    OutlinedButton(onClick = openLookup) {
                                                        Text("按编号打开")
                                                    }
                                                }
                                                onOpenScanOrLink?.let { openScan ->
                                                    OutlinedButton(onClick = openScan) {
                                                        Text("识别链接")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WorkshopSearchHeader(
    query: String,
    categories: List<String>,
    selectedCategory: String,
    showCategories: Boolean,
    onQueryChange: (String) -> Unit,
    onCategoryChange: (String) -> Unit,
    onSearchSubmit: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 2.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
        ) {
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "探索应用",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    text = "发现创作工具与小游戏",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))

            Surface(
                shape = RoundedCornerShape(28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier.fillMaxWidth(),
            ) {
                SearchBarDefaults.InputField(
                    query = query,
                    onQueryChange = onQueryChange,
                    onSearch = { onSearchSubmit() },
                    expanded = false,
                    onExpandedChange = {},
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = {
                        Text(
                            text = "搜索应用、作者或分类",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    leadingIcon = {
                        Icon(
                            painter = painterResource(R.drawable.ic_catalog_search),
                            contentDescription = null,
                        )
                    },
                    trailingIcon = if (query.isNotEmpty()) {
                        {
                            IconButton(
                                onClick = {
                                    onSearchSubmit()
                                    onQueryChange("")
                                },
                            ) {
                                Icon(
                                    painter = painterResource(R.drawable.ic_catalog_close),
                                    contentDescription = "清除搜索",
                                )
                            }
                        }
                    } else {
                        null
                    },
                )
            }
        }

        if (showCategories) {
            LazyRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(
                    items = categories,
                    key = { it },
                ) { category ->
                    val isSelected = selectedCategory == category
                    FilterChip(
                        selected = isSelected,
                        onClick = { onCategoryChange(category) },
                        label = {
                            Text(
                                text = category,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        shape = RoundedCornerShape(20.dp),
                    )
                }
            }
        }
    }
}

private fun pickSpotlightApps(apps: List<CatalogApp>): List<CatalogApp> {
    if (apps.size < 2) return emptyList()
    return apps
        .sortedWith(
            compareByDescending<CatalogApp> { it.isOfficial }
                .thenByDescending { it.rating ?: 0.0 }
                .thenByDescending { it.launchUrl != null },
        )
        .take(5)
}

@Composable
private fun FeaturedSpotlightSection(
    apps: List<CatalogApp>,
    homeInstalledIds: Set<String>,
    onSelectApp: (CatalogApp) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp, bottom = 4.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "编辑精选",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = "为你推荐",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(
                items = apps,
                key = { "spotlight_${it.id}" },
            ) { app ->
                val isInHome = homeInstalledIds.contains(app.id) ||
                    homeInstalledIds.contains(app.key) ||
                    homeInstalledIds.contains(app.homeKey)
                FeaturedSpotlightCard(
                    app = app,
                    isInHome = isInHome,
                    onClick = { onSelectApp(app) },
                )
            }
        }
    }
}

@Composable
private fun FeaturedSpotlightCard(
    app: CatalogApp,
    isInHome: Boolean,
    onClick: () -> Unit,
) {
    val accent = parseThemeColor(app.themeColor) ?: MaterialTheme.colorScheme.primary
    val baseColor = MaterialTheme.colorScheme.surfaceContainerHigh
    val gradient = Brush.linearGradient(
        colors = listOf(
            accent.copy(alpha = 0.18f),
            baseColor,
        ),
    )
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(20.dp),
        color = Color.Transparent,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
        modifier = Modifier.width(276.dp),
    ) {
        Column(
            modifier = Modifier
                .background(gradient)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                PlayStoreIconFrame(app = app, size = 48.dp)
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = app.name,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = if (app.isOfficial) {
                                MaterialTheme.colorScheme.primaryContainer
                            } else {
                                MaterialTheme.colorScheme.secondaryContainer
                            },
                        ) {
                            Text(
                                text = if (app.isOfficial) "官方" else app.browseCategory,
                                style = MaterialTheme.typography.labelSmall,
                                color = if (app.isOfficial) {
                                    MaterialTheme.colorScheme.onPrimaryContainer
                                } else {
                                    MaterialTheme.colorScheme.onSecondaryContainer
                                },
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                            )
                        }
                    }
                    Text(
                        text = app.description.ifBlank { "${app.author} · ${app.browseCategory}" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = listOfNotNull(
                        app.rating?.let(::formatRating),
                        app.author.takeIf(String::isNotBlank),
                        when {
                            isInHome -> "已在云居"
                            app.launchUrl != null -> "即点即用"
                            else -> "需登录"
                        },
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "查看",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun PlayStoreAppRow(
    app: CatalogApp,
    rank: Int?,
    selected: Boolean,
    isInHome: Boolean,
    onClick: () -> Unit,
    onLaunch: () -> Unit,
    onToggleHome: (() -> Unit)?,
) {
    val containerColor = if (selected) {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
    } else {
        Color.Transparent
    }
    Surface(
        selected = selected,
        onClick = onClick,
        shape = if (selected) RoundedCornerShape(16.dp) else RoundedCornerShape(0.dp),
        color = containerColor,
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                if (selected) stateDescription = "已选中"
            },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 76.dp)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (rank != null) {
                Text(
                    text = rank.toString(),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.width(20.dp),
                )
            }

            PlayStoreIconFrame(app = app, size = 56.dp)

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = app.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (app.isOfficial) {
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = MaterialTheme.colorScheme.primaryContainer,
                        ) {
                            Text(
                                text = "官方",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                            )
                        }
                    }
                }

                Text(
                    text = app.description.ifBlank { "${app.browseCategory} · ${app.author}" },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )

                val statsText = buildList {
                    app.rating?.let { add(formatRating(it)) }
                    add(app.browseCategory)
                    if (isInHome) {
                        add("已在云居")
                    } else if (app.launchUrl == null) {
                        add("需登录")
                    } else if (app.author.isNotBlank()) {
                        add(app.author)
                    }
                }.joinToString(" · ")

                Text(
                    text = statsText,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isInHome) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            when {
                isInHome && app.launchUrl != null -> {
                    FilledTonalButton(
                        onClick = onLaunch,
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                        modifier = Modifier.defaultMinSize(minHeight = 36.dp),
                    ) {
                        Text(
                            text = "打开",
                            style = MaterialTheme.typography.labelLarge,
                            maxLines = 1,
                        )
                    }
                }

                !isInHome && onToggleHome != null -> {
                    OutlinedButton(
                        onClick = onToggleHome,
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                        modifier = Modifier.defaultMinSize(minHeight = 36.dp),
                    ) {
                        Text(
                            text = "+ 云居",
                            style = MaterialTheme.typography.labelLarge,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayStoreIconFrame(
    app: CatalogApp,
    size: Dp,
) {
    val cornerRadius = (size.value * 0.22f).coerceIn(4f, 16f).dp
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(cornerRadius))
            .border(
                width = 0.5.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f),
                shape = RoundedCornerShape(cornerRadius),
            ),
    ) {
        AppIconBadge(app = app, size = size)
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun DetailScreen(
    appId: String,
    uiState: CatalogUiState,
    showBackNavigation: Boolean,
    isInHome: Boolean = false,
    fallbackApp: CatalogApp? = null,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onResumeSession: () -> Unit,
    onLaunchApp: (CatalogApp) -> Unit,
    onToggleHome: ((CatalogApp) -> Unit)? = null,
    onOpenWebDetails: (CatalogApp) -> Unit,
    onOpenAppData: ((CatalogApp) -> Unit)? = null,
    onOpenReviews: ((CatalogApp) -> Unit)? = null,
    onOpenDeveloper: ((String) -> Unit)? = null,
    onAcquireApp: ((CatalogApp) -> Unit)? = null,
    onShareApp: ((CatalogApp) -> Unit)? = null,
) {
    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "应用详情",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
                },
                navigationIcon = if (showBackNavigation) {
                    {
                        IconButton(onClick = onBack) {
                            Icon(
                                painter = painterResource(R.drawable.ic_host_arrow_back),
                                contentDescription = "返回",
                            )
                        }
                    }
                } else {
                    {}
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            if (showBackNavigation) {
                uiState.minimizedAppName?.let { minimizedName ->
                    ResumeSessionBanner(
                        appName = minimizedName,
                        onResume = onResumeSession,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                    )
                }
            }

            when (uiState.feed) {
                CatalogFeedState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.semantics {
                                contentDescription = "正在加载应用"
                            },
                        )
                    }
                }

                CatalogFeedState.Error -> {
                    CatalogStatusMessage(
                        message = "暂时无法加载应用，请检查网络。",
                        actionLabel = "重试",
                        onAction = onRetry,
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                    )
                }

                is CatalogFeedState.Loaded -> {
                    val app = uiState.findApp(appId) ?: fallbackApp
                    if (app == null) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f)
                                .padding(24.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "这个应用暂不可用。",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f)
                                .verticalScroll(rememberScrollState())
                                .padding(horizontal = 20.dp, vertical = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(18.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(16.dp),
                            ) {
                                PlayStoreIconFrame(app = app, size = 72.dp)
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Text(
                                        text = app.name,
                                        style = MaterialTheme.typography.headlineSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.semantics { heading() },
                                    )
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        if (app.author.isNotBlank()) {
                                            val authorClickable = onOpenDeveloper != null && !app.ownerLogin.isNullOrBlank()
                                            Text(
                                                text = if (authorClickable) "${app.author} ›" else app.author,
                                                style = MaterialTheme.typography.labelLarge,
                                                color = MaterialTheme.colorScheme.primary,
                                                modifier = Modifier.clickable(enabled = authorClickable) {
                                                    app.ownerLogin?.let { login -> onOpenDeveloper?.invoke(login) }
                                                },
                                            )
                                        }
                                        if (app.isOfficial) {
                                            Surface(
                                                shape = RoundedCornerShape(6.dp),
                                                color = MaterialTheme.colorScheme.primaryContainer,
                                            ) {
                                                Text(
                                                    text = "官方出品",
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                                                    modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                            DetailStatsStrip(app = app)

                            if (app.launchUrl != null) {
                                Button(
                                    onClick = { onLaunchApp(app) },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 48.dp),
                                ) {
                                    Text(text = "试用")
                                }
                            } else {
                                Surface(
                                    shape = MaterialTheme.shapes.small,
                                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(
                                        text = "该应用需登录或满足访问条件，请在网页详情中查看。",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(14.dp),
                                    )
                                }
                            }

                            if (onToggleHome != null) {
                                FilledTonalButton(
                                    onClick = { onToggleHome(app) },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 48.dp),
                                ) {
                                    Text(text = if (isInHome) "已在云居 · 点击移出" else "加入云居")
                                }
                            }

                            OutlinedButton(
                                onClick = { onOpenWebDetails(app) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .defaultMinSize(minHeight = 48.dp),
                            ) {
                                Text(text = "网页详情")
                            }

                            if (onOpenAppData != null && app.launchUrl != null) {
                                OutlinedButton(
                                    onClick = { onOpenAppData(app) },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 48.dp),
                                ) {
                                    Text(text = "应用数据")
                                }
                            }

                            if (app.launchUrl == null && onAcquireApp != null) {
                                OutlinedButton(
                                    onClick = { onAcquireApp(app) },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 48.dp),
                                ) {
                                    Text(text = "获取与权益")
                                }
                            }

                            if (onOpenReviews != null || onShareApp != null) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    if (onOpenReviews != null) {
                                        OutlinedButton(
                                            onClick = { onOpenReviews(app) },
                                            modifier = Modifier
                                                .weight(1f)
                                                .defaultMinSize(minHeight = 48.dp),
                                        ) {
                                            Text(text = "评分与评价")
                                        }
                                    }
                                    if (onShareApp != null) {
                                        OutlinedButton(
                                            onClick = { onShareApp(app) },
                                            modifier = Modifier
                                                .weight(1f)
                                                .defaultMinSize(minHeight = 48.dp),
                                        ) {
                                            Text(text = "分享")
                                        }
                                    }
                                }
                            }

                            HorizontalDivider(
                                thickness = 0.5.dp,
                                color = MaterialTheme.colorScheme.outlineVariant,
                            )

                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    text = "关于此应用",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.semantics { heading() },
                                )
                                Text(
                                    text = app.description.ifBlank { "在云乐坊发现并使用这个应用。" },
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                val detailBadges = buildList {
                                    if (app.browseCategory.isNotBlank()) add(app.browseCategory)
                                    app.releaseStage?.takeIf(String::isNotBlank)?.let { stage ->
                                        add(if (stage == "stable") "正式版" else stage)
                                    }
                                    addAll(app.tags)
                                }.distinct()
                                if (detailBadges.isNotEmpty()) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    FlowRow(
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        detailBadges.forEach { badge ->
                                            Surface(
                                                shape = RoundedCornerShape(16.dp),
                                                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                                                border = BorderStroke(
                                                    width = 0.5.dp,
                                                    color = MaterialTheme.colorScheme.outlineVariant,
                                                ),
                                            ) {
                                                Text(
                                                    text = badge,
                                                    style = MaterialTheme.typography.labelMedium,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailStatsStrip(app: CatalogApp) {
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            DetailStatCell(
                value = app.rating?.let(::formatRating) ?: "—",
                label = "评分",
                modifier = Modifier.weight(1f),
            )
            VerticalDivider(
                modifier = Modifier.height(28.dp),
                thickness = 0.5.dp,
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            DetailStatCell(
                value = app.browseCategory,
                label = "分类",
                modifier = Modifier.weight(1f),
            )
            VerticalDivider(
                modifier = Modifier.height(28.dp),
                thickness = 0.5.dp,
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            DetailStatCell(
                value = if (app.launchUrl != null) "即点即用" else "需登录",
                label = "访问方式",
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun DetailStatCell(
    value: String,
    label: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
        )
    }
}

@Composable
internal fun ResumeSessionBanner(
    appName: String,
    onResume: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FilledTonalButton(
        onClick = onResume,
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp),
        shape = MaterialTheme.shapes.medium,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_catalog_play),
            contentDescription = null,
            modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "继续使用：$appName",
            style = MaterialTheme.typography.labelLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
internal fun AppIconBadge(
    app: CatalogApp,
    size: Dp,
) {
    val bitmap by produceState<Bitmap?>(initialValue = null, key1 = app.logo) {
        value = BoundedHttpsImageLoader.loadBitmap(app.logo)
    }
    val cornerRadius = (size.value * 0.22f).coerceIn(4f, 16f).dp
    val shape = RoundedCornerShape(cornerRadius)
    val parsedColor = parseThemeColor(app.themeColor)
    val backgroundColor = parsedColor ?: MaterialTheme.colorScheme.secondaryContainer

    Box(
        modifier = Modifier
            .size(size)
            .clip(shape)
            .background(backgroundColor)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        val loaded = bitmap
        if (loaded != null) {
            Image(
                bitmap = loaded.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Text(
                text = app.emoji,
                style = when {
                    size <= 22.dp -> MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp)
                    size >= 60.dp -> MaterialTheme.typography.headlineMedium
                    else -> MaterialTheme.typography.titleLarge
                },
            )
        }
    }
}

@Composable
private fun CatalogStatusMessage(
    message: String,
    actionLabel: String,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(
                onClick = onAction,
                modifier = Modifier.defaultMinSize(minHeight = 48.dp),
            ) {
                Text(text = actionLabel)
            }
        }
    }
}

private fun parseThemeColor(raw: String?): Color? = raw
    ?.takeIf { it.startsWith('#') }
    ?.let { value -> runCatching { Color(AndroidColor.parseColor(value)) }.getOrNull() }

private fun formatRating(rating: Double): String =
    String.format(Locale.US, "%.1f ★", rating)
