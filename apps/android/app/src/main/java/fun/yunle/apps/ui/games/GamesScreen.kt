package `fun`.yunle.apps.ui.games

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun GamesScreen(
    uiState: CatalogUiState,
    onResumeSession: () -> Unit,
    onLaunchGame: (CatalogApp) -> Unit,
    onSelectAppDetail: (CatalogApp) -> Unit,
    onRetry: () -> Unit,
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

            when (val feed = uiState.feed) {
                CatalogFeedState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                CatalogFeedState.Error -> {
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
                                text = "暂时无法载入游戏列表，你仍可直接打开云乐坊游戏大厅。",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                FilledTonalButton(onClick = onRetry) {
                                    Text("重试")
                                }
                                Button(onClick = { onLaunchGame(DEFAULT_PLAY_HALL_APP) }) {
                                    Text("打开游戏大厅")
                                }
                            }
                        }
                    }
                }

                is CatalogFeedState.Loaded -> {
                    val playApp = feed.apps.firstOrNull { it.key == "play" || it.id == "play" }
                        ?: DEFAULT_PLAY_HALL_APP
                    val gameApps = feed.apps.filter { app ->
                        app.id != playApp.id && (
                            app.category.contains("游戏") ||
                                app.category.contains("娱乐") ||
                                app.name.contains("棋") ||
                                app.name.contains("游") ||
                                app.name.contains("杀") ||
                                app.name.contains("牌")
                            )
                    }
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

                        if (gameApps.isNotEmpty()) {
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
}
