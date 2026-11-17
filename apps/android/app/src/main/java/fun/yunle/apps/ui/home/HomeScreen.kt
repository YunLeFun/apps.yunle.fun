package `fun`.yunle.apps.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.home.HomeFolder
import `fun`.yunle.apps.home.HomeGridItem
import `fun`.yunle.apps.home.HomeLibrarySnapshot
import `fun`.yunle.apps.home.HomeSyncPhase
import `fun`.yunle.apps.home.HomeSyncResolution
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import `fun`.yunle.apps.ui.catalog.ResumeSessionBanner

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeScreen(
    snapshot: HomeLibrarySnapshot,
    storageError: String?,
    syncPhase: HomeSyncPhase = HomeSyncPhase.Idle,
    showRecent: Boolean,
    minimizedAppName: String?,
    activeUser: AccountUser?,
    onBrowseWorkshop: () -> Unit,
    onResumeSession: () -> Unit,
    onLaunchOrDetail: (CatalogApp) -> Unit,
    onOpenDetail: (CatalogApp) -> Unit = onLaunchOrDetail,
    onAddApp: (CatalogApp) -> Unit = {},
    onTogglePin: (CatalogApp, Boolean) -> Unit,
    onSetPinnedBatch: (List<CatalogApp>, Boolean) -> Boolean = { apps, pinned ->
        apps.forEach { onTogglePin(it, pinned) }
        true
    },
    onRemoveApp: (CatalogApp) -> Unit,
    onReorderDock: (List<String>) -> Unit = {},
    onReorderItems: (List<String>) -> Unit = {},
    onCreateFolder: (name: String, keys: List<String>, anchor: String) -> Unit = { _, _, _ -> },
    onAddToFolder: (folderId: String, keys: List<String>) -> Unit = { _, _ -> },
    onRemoveFromFolder: (String) -> Unit = {},
    onRenameFolder: (folderId: String, name: String) -> Unit = { _, _ -> },
    onReorderFolder: (folderId: String, appIds: List<String>) -> Unit = { _, _ -> },
    onDissolveFolder: (String) -> Unit = {},
    onRetryStorage: () -> Unit,
    onSyncNow: () -> Unit = {},
    onResolveSyncConflict: (HomeSyncResolution) -> Unit = {},
    onOpenSyncSettings: () -> Unit = {},
) {
    val haptic = LocalHapticFeedback.current
    var editing by rememberSaveable { mutableStateOf(false) }
    var openFolderId by rememberSaveable { mutableStateOf<String?>(null) }
    var menuTargetKey by remember { mutableStateOf<String?>(null) }
    var folderPickerApp by remember { mutableStateOf<CatalogApp?>(null) }
    var confirmDissolveFolder by remember { mutableStateOf<HomeFolder?>(null) }

    val dockApps = snapshot.dockApplications
    val mainApps = snapshot.mainApplications
    val mainItems = remember(mainApps, snapshot.configuration.folders) {
        HomeGridItem.items(mainApps, snapshot.configuration.folders)
    }
    val hasDesktopApps = dockApps.isNotEmpty() || mainItems.isNotEmpty()

    LaunchedEffect(hasDesktopApps) {
        if (editing && !hasDesktopApps) {
            editing = false
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = "我的云居",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.semantics { heading() },
                        )
                        Text(
                            text = activeUser?.let { "当前账号：${it.displayName}" } ?: "访客云居 · 登录后可多账号独立保存",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                },
                actions = {
                    if (editing) {
                        TextButton(onClick = { editing = false }) {
                            Text("完成")
                        }
                    } else {
                        if (hasDesktopApps) {
                            TextButton(onClick = { editing = true }) {
                                Text("编辑")
                            }
                        }
                        if (activeUser != null) {
                            TextButton(
                                onClick = onSyncNow,
                                enabled = syncPhase !is HomeSyncPhase.Syncing,
                            ) {
                                Text(if (syncPhase is HomeSyncPhase.Syncing) "同步中" else "同步")
                            }
                        }
                        TextButton(onClick = onBrowseWorkshop) {
                            Text("去工坊")
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
                .padding(innerPadding),
        ) {
            minimizedAppName?.let { name ->
                ResumeSessionBanner(
                    appName = name,
                    onResume = onResumeSession,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                )
            }

            if (activeUser != null) {
                HomeSyncBanner(
                    syncPhase = syncPhase,
                    localInstalledCount = snapshot.installedIds.size,
                    localDockCount = snapshot.dockIds.size,
                    onSyncNow = onSyncNow,
                    onResolveConflict = onResolveSyncConflict,
                    onOpenSyncSettings = onOpenSyncSettings,
                )
            }

            if (storageError != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = storageError,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Button(onClick = onRetryStorage) {
                            Text("重试")
                        }
                    }
                }
                return@Column
            }

            if (editing) {
                val reorderable = remember(snapshot.installedIds, snapshot.configuration.folders) {
                    (snapshot.installedIds + snapshot.configuration.folders.map { HomeGridItem.folderKey(it.id) }).toSet()
                }
                HomeEditCanvas(
                    dock = if (snapshot.dockVisible) dockApps else null,
                    items = mainItems,
                    reorderable = reorderable,
                    onReorderDock = onReorderDock,
                    onReorderItems = onReorderItems,
                    onSetPinned = onSetPinnedBatch,
                    onRemoveApp = onRemoveApp,
                    onCreateFolder = onCreateFolder,
                    onAddToFolder = onAddToFolder,
                    onDissolveFolder = { folder -> onDissolveFolder(folder.id) },
                    onOpenFolder = { folder -> openFolderId = folder.id },
                    onExitEditMode = { editing = false },
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                )
                return@Column
            }

            val recentApps = if (showRecent) {
                snapshot.recentApplications.take(if (hasDesktopApps) 4 else 8)
            } else {
                emptyList()
            }

            if (!hasDesktopApps && recentApps.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyHomePlaceholder(
                        canSync = activeUser != null && snapshot.syncEnabled,
                        syncing = syncPhase is HomeSyncPhase.Syncing,
                        onBrowseWorkshop = onBrowseWorkshop,
                        onSyncNow = onSyncNow,
                    )
                }
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .pointerInput(hasDesktopApps) {
                            detectTapGestures(
                                onLongPress = {
                                    if (hasDesktopApps) {
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        editing = true
                                    }
                                },
                            )
                        }
                        .padding(horizontal = HomeGridMetrics.MARGIN, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    if (!hasDesktopApps) {
                        Surface(
                            shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            EmptyHomePlaceholder(
                                canSync = activeUser != null && snapshot.syncEnabled,
                                syncing = syncPhase is HomeSyncPhase.Syncing,
                                onBrowseWorkshop = onBrowseWorkshop,
                                onSyncNow = onSyncNow,
                                modifier = Modifier.padding(20.dp),
                            )
                        }
                    }

                    if (snapshot.dockVisible && dockApps.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                text = "常用应用",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.semantics { heading() },
                            )
                            HomeDockPlatter {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceEvenly,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    dockApps.forEach { app ->
                                        val keyId = "dock:${app.homeKey}"
                                        key(keyId) {
                                            Box {
                                                HomeAppGlyph(
                                                    name = app.name,
                                                    showsName = false,
                                                    labelWidth = HomeGridMetrics.ICON_SIZE,
                                                    isUnavailable = app.launchUrl == null,
                                                    onClick = { onLaunchOrDetail(app) },
                                                    onLongClick = {
                                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                        menuTargetKey = keyId
                                                    },
                                                    modifier = Modifier.semantics {
                                                        contentDescription = "打开 ${app.name}"
                                                    },
                                                ) {
                                                    AppIconBadge(app = app, size = HomeGridMetrics.ICON_SIZE)
                                                }
                                                AppContextMenu(
                                                    expanded = menuTargetKey == keyId,
                                                    app = app,
                                                    isPinned = true,
                                                    canPinMore = true,
                                                    canManageFolders = false,
                                                    inFolder = null,
                                                    onDismiss = { menuTargetKey = null },
                                                    onEnterEdit = { editing = true },
                                                    onOpenDetail = { onOpenDetail(app) },
                                                    onTogglePin = { onTogglePin(app, false) },
                                                    onMoveToFolder = {},
                                                    onRemoveFromFolder = {},
                                                    onRemove = { onRemoveApp(app) },
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (recentApps.isNotEmpty() && (!hasDesktopApps || snapshot.applications.size > 4)) {
                        RecentDesktopGridSection(
                            recentApps = recentApps,
                            snapshot = snapshot,
                            menuTargetKey = menuTargetKey,
                            onSetMenuTarget = { menuTargetKey = it },
                            onLaunchOrDetail = onLaunchOrDetail,
                            onOpenDetail = onOpenDetail,
                            onAddApp = onAddApp,
                        )
                    }

                    if (mainItems.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "我的应用 · ${mainItems.size}",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.semantics { heading() },
                                )
                                Text(
                                    text = "长按管理 · 点「编辑」拖拽",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                                val metrics = HomeGridMetrics.calculate(maxWidth)
                                val rows = mainItems.chunked(metrics.columns)
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalArrangement = Arrangement.spacedBy(HomeGridMetrics.ROW_SPACING),
                                ) {
                                    rows.forEach { rowItems ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.spacedBy(HomeGridMetrics.COLUMN_SPACING),
                                        ) {
                                            for (column in 0 until metrics.columns) {
                                                val item = rowItems.getOrNull(column)
                                                if (item != null) {
                                                    val keyId = "main:${item.id}"
                                                    key(keyId) {
                                                        Box(
                                                            modifier = Modifier.weight(1f),
                                                            contentAlignment = Alignment.TopCenter,
                                                        ) {
                                                            when (item) {
                                                                is HomeGridItem.App -> {
                                                                    val app = item.app
                                                                    val pinned = snapshot.isPinned(app)
                                                                    val canPin = pinned || snapshot.dockIds.size < 4
                                                                    HomeAppGlyph(
                                                                        name = app.name,
                                                                        labelWidth = Dp.Unspecified,
                                                                        isUnavailable = app.launchUrl == null,
                                                                        onClick = { onLaunchOrDetail(app) },
                                                                        onLongClick = {
                                                                            haptic.performHapticFeedback(
                                                                                HapticFeedbackType.LongPress,
                                                                            )
                                                                            menuTargetKey = keyId
                                                                        },
                                                                    ) {
                                                                        AppIconBadge(
                                                                            app = app,
                                                                            size = HomeGridMetrics.ICON_SIZE,
                                                                        )
                                                                    }
                                                                    AppContextMenu(
                                                                        expanded = menuTargetKey == keyId,
                                                                        app = app,
                                                                        isPinned = pinned,
                                                                        canPinMore = canPin,
                                                                        canManageFolders = snapshot.contains(app) && !pinned,
                                                                        inFolder = null,
                                                                        onDismiss = { menuTargetKey = null },
                                                                        onEnterEdit = { editing = true },
                                                                        onOpenDetail = { onOpenDetail(app) },
                                                                        onTogglePin = { onTogglePin(app, !pinned) },
                                                                        onMoveToFolder = { folderPickerApp = app },
                                                                        onRemoveFromFolder = {},
                                                                        onRemove = { onRemoveApp(app) },
                                                                    )
                                                                }
                                                                is HomeGridItem.Folder -> {
                                                                    HomeAppGlyph(
                                                                        name = item.folder.name,
                                                                        labelWidth = Dp.Unspecified,
                                                                        onClick = { openFolderId = item.folder.id },
                                                                        onLongClick = {
                                                                            haptic.performHapticFeedback(
                                                                                HapticFeedbackType.LongPress,
                                                                            )
                                                                            menuTargetKey = keyId
                                                                        },
                                                                    ) {
                                                                        HomeFolderIcon(
                                                                            apps = item.apps,
                                                                            size = HomeGridMetrics.ICON_SIZE,
                                                                        )
                                                                    }
                                                                    DropdownMenu(
                                                                        expanded = menuTargetKey == keyId,
                                                                        onDismissRequest = { menuTargetKey = null },
                                                                    ) {
                                                                        DropdownMenuItem(
                                                                            text = { Text("打开文件夹") },
                                                                            onClick = {
                                                                                menuTargetKey = null
                                                                                openFolderId = item.folder.id
                                                                            },
                                                                        )
                                                                        DropdownMenuItem(
                                                                            text = { Text("编辑云居") },
                                                                            onClick = {
                                                                                menuTargetKey = null
                                                                                editing = true
                                                                            },
                                                                        )
                                                                        DropdownMenuItem(
                                                                            text = {
                                                                                Text(
                                                                                    "解散文件夹",
                                                                                    color = MaterialTheme.colorScheme.error,
                                                                                )
                                                                            },
                                                                            onClick = {
                                                                                menuTargetKey = null
                                                                                confirmDissolveFolder = item.folder
                                                                            },
                                                                        )
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    Spacer(modifier = Modifier.weight(1f))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (recentApps.isNotEmpty() && hasDesktopApps && snapshot.applications.size <= 4) {
                        RecentDesktopGridSection(
                            recentApps = recentApps,
                            snapshot = snapshot,
                            menuTargetKey = menuTargetKey,
                            onSetMenuTarget = { menuTargetKey = it },
                            onLaunchOrDetail = onLaunchOrDetail,
                            onOpenDetail = onOpenDetail,
                            onAddApp = onAddApp,
                        )
                    }

                    Spacer(modifier = Modifier.height(24.dp))
                }
            }
        }
    }

    val activeFolder = openFolderId?.let { id ->
        snapshot.configuration.folders.firstOrNull { it.id == id }
    }
    if (activeFolder != null) {
        val folderApps = activeFolder.appIds.map { snapshot.application(it) }
        HomeFolderSheet(
            folder = activeFolder,
            apps = folderApps,
            onLaunchApp = onLaunchOrDetail,
            onRenameFolder = { newName -> onRenameFolder(activeFolder.id, newName) },
            onReorderFolder = { ids -> onReorderFolder(activeFolder.id, ids) },
            onRemoveFromFolder = onRemoveFromFolder,
            onDissolveFolder = { onDissolveFolder(activeFolder.id) },
            onDismiss = { openFolderId = null },
        )
    }

    folderPickerApp?.let { targetApp ->
        val suggested = HomeGridItem.suggestedFolderName(listOf(targetApp))
        AlertDialog(
            onDismissRequest = { folderPickerApp = null },
            title = { Text("将“${targetApp.name}”移入文件夹") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (snapshot.configuration.folders.isEmpty()) {
                        Text(
                            text = "新建文件夹“$suggested”并放入此应用？",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    } else {
                        snapshot.configuration.folders.forEach { folder ->
                            OutlinedButton(
                                onClick = {
                                    onAddToFolder(folder.id, listOf(targetApp.homeKey))
                                    folderPickerApp = null
                                },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text("${folder.name}（${folder.appIds.size}）")
                            }
                        }
                        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                        Button(
                            onClick = {
                                onCreateFolder(suggested, listOf(targetApp.homeKey), targetApp.homeKey)
                                folderPickerApp = null
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("新建文件夹“$suggested”")
                        }
                    }
                }
            },
            confirmButton = {
                if (snapshot.configuration.folders.isEmpty()) {
                    Button(
                        onClick = {
                            onCreateFolder(suggested, listOf(targetApp.homeKey), targetApp.homeKey)
                            folderPickerApp = null
                        },
                    ) {
                        Text("新建文件夹")
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = { folderPickerApp = null }) {
                    Text("取消")
                }
            },
        )
    }

    confirmDissolveFolder?.let { folder ->
        AlertDialog(
            onDismissRequest = { confirmDissolveFolder = null },
            title = { Text("解散“${folder.name}”？") },
            text = { Text("其中的应用会留在云居原来的位置。") },
            confirmButton = {
                Button(
                    onClick = {
                        confirmDissolveFolder = null
                        onDissolveFolder(folder.id)
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("解散文件夹")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDissolveFolder = null }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun RecentDesktopGridSection(
    recentApps: List<CatalogApp>,
    snapshot: HomeLibrarySnapshot,
    menuTargetKey: String?,
    onSetMenuTarget: (String?) -> Unit,
    onLaunchOrDetail: (CatalogApp) -> Unit,
    onOpenDetail: (CatalogApp) -> Unit,
    onAddApp: (CatalogApp) -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            text = "最近使用",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.semantics { heading() },
        )
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val metrics = HomeGridMetrics.calculate(maxWidth)
            val rows = recentApps.chunked(metrics.columns)
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(HomeGridMetrics.ROW_SPACING),
            ) {
                rows.forEach { rowApps ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(HomeGridMetrics.COLUMN_SPACING),
                    ) {
                        for (column in 0 until metrics.columns) {
                            val app = rowApps.getOrNull(column)
                            if (app != null) {
                                val keyId = "recent:${app.homeKey}"
                                key(keyId) {
                                    Box(
                                        modifier = Modifier.weight(1f),
                                        contentAlignment = Alignment.TopCenter,
                                    ) {
                                        HomeAppGlyph(
                                            name = app.name,
                                            labelWidth = Dp.Unspecified,
                                            isUnavailable = app.launchUrl == null,
                                            onClick = { onLaunchOrDetail(app) },
                                            onLongClick = {
                                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                onSetMenuTarget(keyId)
                                            },
                                        ) {
                                            AppIconBadge(app = app, size = HomeGridMetrics.ICON_SIZE)
                                        }
                                        DropdownMenu(
                                            expanded = menuTargetKey == keyId,
                                            onDismissRequest = { onSetMenuTarget(null) },
                                        ) {
                                            DropdownMenuItem(
                                                text = { Text("应用详情") },
                                                onClick = {
                                                    onSetMenuTarget(null)
                                                    onOpenDetail(app)
                                                },
                                            )
                                            if (!snapshot.contains(app)) {
                                                DropdownMenuItem(
                                                    text = { Text("加入云居") },
                                                    onClick = {
                                                        onSetMenuTarget(null)
                                                        onAddApp(app)
                                                    },
                                                )
                                            }
                                        }
                                    }
                                }
                            } else {
                                Spacer(modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AppContextMenu(
    expanded: Boolean,
    app: CatalogApp,
    isPinned: Boolean,
    canPinMore: Boolean,
    canManageFolders: Boolean,
    inFolder: HomeFolder?,
    onDismiss: () -> Unit,
    onEnterEdit: () -> Unit,
    onOpenDetail: () -> Unit,
    onTogglePin: () -> Unit,
    onMoveToFolder: () -> Unit,
    onRemoveFromFolder: () -> Unit,
    onRemove: () -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
    ) {
        DropdownMenuItem(
            text = { Text("编辑云居") },
            onClick = {
                onDismiss()
                onEnterEdit()
            },
        )
        DropdownMenuItem(
            text = { Text("应用详情") },
            onClick = {
                onDismiss()
                onOpenDetail()
            },
        )
        DropdownMenuItem(
            text = {
                Text(
                    when {
                        isPinned -> "取消常用"
                        canPinMore -> "设为常用"
                        else -> "常用栏已满（最多 4 个）"
                    },
                )
            },
            enabled = isPinned || canPinMore,
            onClick = {
                onDismiss()
                onTogglePin()
            },
        )
        if (inFolder != null) {
            DropdownMenuItem(
                text = { Text("移出“${inFolder.name}”") },
                onClick = {
                    onDismiss()
                    onRemoveFromFolder()
                },
            )
        } else if (canManageFolders) {
            DropdownMenuItem(
                text = { Text("移入文件夹") },
                onClick = {
                    onDismiss()
                    onMoveToFolder()
                },
            )
        }
        DropdownMenuItem(
            text = { Text("移出", color = MaterialTheme.colorScheme.error) },
            onClick = {
                onDismiss()
                onRemove()
            },
        )
    }
}

@Composable
private fun EmptyHomePlaceholder(
    canSync: Boolean,
    syncing: Boolean,
    onBrowseWorkshop: () -> Unit,
    onSyncNow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "你的云居还没有应用",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = "在「工坊」中发现喜欢的云应用，在详情页点按「加入云居」即可把它们带回这里。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Button(
            onClick = onBrowseWorkshop,
            modifier = Modifier.defaultMinSize(minHeight = 48.dp),
        ) {
            Text("前往工坊浏览")
        }
        if (canSync) {
            OutlinedButton(
                onClick = onSyncNow,
                enabled = !syncing,
                modifier = Modifier.defaultMinSize(minHeight = 48.dp),
            ) {
                Text(if (syncing) "正在同步云居…" else "立即从云端同步")
            }
        }
    }
}

@Composable
private fun HomeSyncBanner(
    syncPhase: HomeSyncPhase,
    localInstalledCount: Int,
    localDockCount: Int,
    onSyncNow: () -> Unit,
    onResolveConflict: (HomeSyncResolution) -> Unit,
    onOpenSyncSettings: () -> Unit,
) {
    when (syncPhase) {
        HomeSyncPhase.Idle -> Unit
        HomeSyncPhase.Syncing -> {
            Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .width(16.dp)
                            .height(16.dp),
                        strokeWidth = 2.dp,
                    )
                    Text(
                        text = "正在同步云居…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        is HomeSyncPhase.Failed -> {
            Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.errorContainer,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = syncPhase.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onSyncNow) {
                        Text("重试")
                    }
                    TextButton(onClick = onOpenSyncSettings) {
                        Text("设置")
                    }
                }
            }
        }
        is HomeSyncPhase.Conflict -> {
            val remoteConfig = syncPhase.remote.configuration
            Surface(
                shape = MaterialTheme.shapes.large,
                color = MaterialTheme.colorScheme.secondaryContainer,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = "云端与本地的云居版本存在冲突",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Text(
                        text = "云端：${remoteConfig.installedApps.size} 个应用 / ${remoteConfig.dockApps.size} 个常用；" +
                            "此设备：$localInstalledCount 个应用 / $localDockCount 个常用。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        OutlinedButton(onClick = { onResolveConflict(HomeSyncResolution.DEVICE) }) {
                            Text("保留此设备版本")
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(onClick = { onResolveConflict(HomeSyncResolution.CLOUD) }) {
                            Text("使用云端版本")
                        }
                    }
                }
            }
        }
    }
}
