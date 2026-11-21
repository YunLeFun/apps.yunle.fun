package `fun`.yunle.apps.ui.games

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.games.NativeGame
import `fun`.yunle.apps.games.NativeGameHistoryEntry
import `fun`.yunle.apps.games.NativeGameMode
import `fun`.yunle.apps.games.NativeGameRoomIntent
import `fun`.yunle.apps.games.NativePublicRoom
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import `fun`.yunle.apps.ui.catalog.CatalogFeedState
import `fun`.yunle.apps.ui.catalog.CatalogUiState
import `fun`.yunle.apps.ui.catalog.ResumeSessionBanner

private val DEFAULT_PLAY_HALL_APP = CatalogApp(
    id = "play",
    key = "play",
    name = "云乐坊游戏大厅",
    description = "与好友随时开局联机桌游、休闲对战与聚会小游戏。",
    author = "云乐坊",
    ownerLogin = "yunle",
    category = "游戏",
    emoji = "🎮",
    launchUrl = "https://play.yunle.fun",
    logo = null,
    themeColor = "#1F2937",
    trustedHosts = listOf("play.yunle.fun"),
    immersive = false,
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun GamesScreen(
    uiState: CatalogUiState,
    onResumeSession: () -> Unit,
    onLaunchGame: (CatalogApp) -> Unit,
    onSelectAppDetail: (CatalogApp) -> Unit,
    onRetry: () -> Unit,
    nativeGames: List<NativeGame> = emptyList(),
    recentHistory: List<NativeGameHistoryEntry> = emptyList(),
    publicRooms: List<NativePublicRoom> = emptyList(),
    isLoadingRooms: Boolean = false,
    roomsError: String? = null,
    onLaunchNativeGame: (NativeGame, NativeGameMode) -> Unit = { _, _ -> },
    onJoinPublicRoom: (NativeGameRoomIntent) -> Unit = {},
    onRefreshRooms: () -> Unit = {},
    onCreateRoom: () -> Unit = {},
    onJoinByCode: () -> Unit = {},
    onManageGameResources: () -> Unit = {},
) {
    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "寻乐",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
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
            uiState.minimizedAppName?.let { minimized ->
                ResumeSessionBanner(
                    appName = minimized,
                    onResume = onResumeSession,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                )
            }

            val loadedFeed = uiState.feed as? CatalogFeedState.Loaded
            val loadedApps = loadedFeed?.apps.orEmpty()
            val playApp = loadedApps.firstOrNull { it.key == "play" || it.id == "play" }
                ?: DEFAULT_PLAY_HALL_APP
            val gameApps = loadedApps.filter { app ->
                app.id != playApp.id && (
                    app.category.contains("游戏") ||
                        app.category.contains("娱乐") ||
                        app.name.contains("棋") ||
                        app.name.contains("游") ||
                        app.name.contains("杀") ||
                        app.name.contains("牌")
                    )
            }

            if (uiState.feed is CatalogFeedState.Loading && nativeGames.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    item(key = "play_hall_hero") {
                        Surface(
                            shape = MaterialTheme.shapes.extraLarge,
                            color = MaterialTheme.colorScheme.primaryContainer,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(20.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                                ) {
                                    AppIconBadge(app = playApp, size = 56.dp)
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = playApp.name,
                                            style = MaterialTheme.typography.titleLarge,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                                            modifier = Modifier.semantics { heading() },
                                        )
                                        Text(
                                            text = "公开房间 · 联机创建房间 · 单机快速开局",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                                        )
                                    }
                                }
                                Text(
                                    text = playApp.description.ifBlank { DEFAULT_PLAY_HALL_APP.description },
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                                )
                                Button(
                                    onClick = { onLaunchGame(playApp) },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 48.dp),
                                ) {
                                    Text("进入游戏大厅")
                                }
                            }
                        }
                    }

                    item(key = "room_actions_bar") {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            FilledTonalButton(onClick = onCreateRoom) {
                                Text("创建房间")
                            }
                            OutlinedButton(onClick = onJoinByCode) {
                                Text("房间号加入")
                            }
                            OutlinedButton(onClick = onManageGameResources) {
                                Text("资源包")
                            }
                        }
                    }

                    val recentPairs = recentHistory.mapNotNull { entry ->
                        val g = nativeGames.firstOrNull { it.gameId == entry.gameId } ?: return@mapNotNull null
                        val m = g.mode(entry.modeId)?.takeIf { g.isPlayable && it.available } ?: return@mapNotNull null
                        g to m
                    }
                    if (recentPairs.isNotEmpty()) {
                        item(key = "recent_games_section") {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    text = "最近游玩",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.semantics { heading() },
                                )
                                FlowRow(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    recentPairs.forEach { (g, m) ->
                                        FilledTonalButton(onClick = { onLaunchNativeGame(g, m) }) {
                                            Text("${g.name} · ${m.title}")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (nativeGames.isNotEmpty()) {
                        item(key = "native_games_header") {
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = "原生直玩游戏 · ${nativeGames.size}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.semantics { heading() },
                            )
                        }
                        items(items = nativeGames, key = { "native:${it.gameId}" }) { game ->
                            Surface(
                                shape = MaterialTheme.shapes.large,
                                color = MaterialTheme.colorScheme.surfaceContainerLow,
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(
                                    modifier = Modifier.padding(14.dp),
                                    verticalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Text(
                                            text = game.name,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        game.players?.let { players ->
                                            Text(
                                                text = players.label,
                                                style = MaterialTheme.typography.labelMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                    if (game.description.isNotBlank()) {
                                        Text(
                                            text = game.description,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    FlowRow(
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        game.availableModes.forEach { mode ->
                                            FilledTonalButton(
                                                onClick = { onLaunchNativeGame(game, mode) },
                                            ) {
                                                Text(mode.title)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    item(key = "public_rooms_header") {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = "公开房间 (${publicRooms.size})",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.semantics { heading() },
                            )
                            TextButton(
                                onClick = onRefreshRooms,
                                enabled = !isLoadingRooms,
                            ) {
                                Text(if (isLoadingRooms) "刷新中…" else "刷新")
                            }
                        }
                    }

                    if (roomsError != null) {
                        item(key = "public_rooms_error") {
                            Surface(
                                shape = MaterialTheme.shapes.medium,
                                color = MaterialTheme.colorScheme.surfaceContainerLow,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = roomsError,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.weight(1f),
                                    )
                                    TextButton(onClick = onRefreshRooms) {
                                        Text("重试")
                                    }
                                }
                            }
                        }
                    } else if (publicRooms.isEmpty() && !isLoadingRooms) {
                        item(key = "public_rooms_empty") {
                            Text(
                                text = "当前暂无等待中的公开房间，你可以自己创建一个房间或凭房间号加入。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        items(items = publicRooms, key = { "room:${it.inviteCode}" }) { room ->
                            Surface(
                                shape = MaterialTheme.shapes.large,
                                color = MaterialTheme.colorScheme.surfaceContainerLow,
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = "${room.gameName(nativeGames)} · #${room.inviteCode}",
                                            style = MaterialTheme.typography.titleSmall,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        Text(
                                            text = "${room.status.label} · ${room.memberCount}/${room.capacity} 人",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    FilledTonalButton(
                                        onClick = { onJoinPublicRoom(room.intent()) },
                                    ) {
                                        Text(room.actionTitle)
                                    }
                                }
                            }
                        }
                    }

                    if (uiState.feed is CatalogFeedState.Error) {
                        item(key = "catalog_games_retry") {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "工坊游戏目录离线",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                TextButton(onClick = onRetry) { Text("重试目录") }
                            }
                        }
                    } else if (gameApps.isNotEmpty()) {
                        item(key = "games_section_header") {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = "精选休闲与桌游 · ${gameApps.size}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.semantics { heading() },
                            )
                        }
                        items(items = gameApps, key = CatalogApp::id) { app ->
                            Surface(
                                onClick = { onSelectAppDetail(app) },
                                shape = MaterialTheme.shapes.large,
                                color = MaterialTheme.colorScheme.surfaceContainerLow,
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    AppIconBadge(app = app, size = 48.dp)
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = app.name,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MaterialTheme.colorScheme.onSurface,
                                        )
                                        Text(
                                            text = app.description.ifBlank { "${app.author} · ${app.category}" },
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    if (app.launchUrl != null) {
                                        FilledTonalButton(
                                            onClick = { onLaunchGame(app) },
                                            modifier = Modifier.defaultMinSize(minHeight = 40.dp),
                                        ) {
                                            Text("开玩")
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
