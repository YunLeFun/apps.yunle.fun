package `fun`.yunle.apps.ui.games

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.cache.NativeGameResourceCacheStore
import `fun`.yunle.apps.games.NativeGame
import `fun`.yunle.apps.games.NativeGameError
import `fun`.yunle.apps.games.NativeGameRoomIntent
import `fun`.yunle.apps.games.NativeRoomCreating
import `fun`.yunle.apps.games.NativeRoomCreationDraft
import `fun`.yunle.apps.games.NativeRoomCreationError
import `fun`.yunle.apps.games.NativeRoomCreationException
import kotlinx.coroutines.launch
import java.util.Locale
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun NativeRoomCreationSheet(
    games: List<NativeGame>,
    accounts: AccountStore,
    service: NativeRoomCreating,
    onRoomCreated: (NativeGameRoomIntent) -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var draft by remember { mutableStateOf(NativeRoomCreationDraft()) }
    var idempotencyKey by remember(draft) { mutableStateOf(UUID.randomUUID()) }
    var needsConsent by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val selectableGames = remember(games) {
        games.filter { it.gameId in NativeRoomCreationDraft.RULESETS && it.isPlayable }
    }

    fun submit(consent: Boolean) {
        val activeUser = accounts.user?.takeIf { it.isUsable }
        if (activeUser == null) {
            onDismiss()
            onNavigateToMe()
            return
        }
        val gen = identityGeneration
        scope.launch {
            isBusy = true
            errorMessage = null
            val res = runCatching {
                val identity = accounts.authorization(forceRefresh = false)
                service.create(
                    draft = draft,
                    idempotencyKey = idempotencyKey,
                    identity = identity,
                    consent = consent,
                    isCurrent = { accounts.identityGeneration.value == gen && accounts.user?.id == activeUser.id },
                )
            }
            isBusy = false
            if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return@launch
            res.fold(
                onSuccess = { intent ->
                    onDismiss()
                    onRoomCreated(intent)
                },
                onFailure = { err ->
                    if (err is NativeRoomCreationException && err.error == NativeRoomCreationError.CONSENT_REQUIRED) {
                        needsConsent = true
                        errorMessage = null
                    } else {
                        errorMessage = NativeGameError.message(err)
                    }
                },
            )
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!isBusy) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = "创建联机房间",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            if (overview.activeUser?.isUsable != true) {
                Text(
                    text = "创建联机房间需要先登录云乐坊账号。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = {
                        onDismiss()
                        onNavigateToMe()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("前往登录")
                }
                return@Column
            }

            Text(
                text = "选择游戏（可稍后在房间内决定）",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = draft.gameId == null,
                    onClick = { draft = draft.copy(gameId = null); needsConsent = false },
                    enabled = !isBusy,
                    label = { Text("一起选游戏") },
                )
                selectableGames.forEach { game ->
                    FilterChip(
                        selected = draft.gameId == game.gameId,
                        onClick = { draft = draft.copy(gameId = game.gameId); needsConsent = false },
                        enabled = !isBusy,
                        label = { Text(game.name) },
                    )
                }
            }

            Surface(
                shape = MaterialTheme.shapes.large,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("公开房间", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text(
                            text = if (draft.isPublic) "显示在寻乐公开房间列表中，任何人可加入" else "仅限持有 6 位房间号或邀请链接的好友加入",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = draft.isPublic,
                        onCheckedChange = { draft = draft.copy(isPublic = it) },
                        enabled = !isBusy,
                    )
                }
            }

            if (needsConsent) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "授权确认",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = "需要允许云乐坊游戏大厅使用当前账号的标识、昵称和头像后再继续创建房间。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Button(
                            onClick = { submit(consent = true) },
                            enabled = !isBusy,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(if (isBusy) "创建中…" else "同意并创建房间")
                        }
                    }
                }
            } else {
                Button(
                    onClick = { submit(consent = false) },
                    enabled = !isBusy,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (isBusy) "正在创建房间…" else "立即创建")
                }
            }

            errorMessage?.let { msg ->
                Text(
                    text = msg,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
internal fun JoinRoomByCodeDialog(
    onJoinRoom: (NativeGameRoomIntent) -> Unit,
    onDismiss: () -> Unit,
) {
    var input by remember { mutableStateOf("") }
    var role by remember { mutableStateOf(NativeGameRoomIntent.Role.PLAYER) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("房间号或链接加入") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = input,
                    onValueChange = {
                        input = it
                        errorMessage = null
                    },
                    label = { Text("6 位房间号或 play.yunle.fun 邀请链接") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NativeGameRoomIntent.Role.entries.forEach { entry ->
                        FilterChip(
                            selected = role == entry,
                            onClick = { role = entry },
                            label = { Text(entry.label) },
                        )
                    }
                }
                errorMessage?.let { msg ->
                    Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
        confirmButton = {
            Button(
                onClick = {
                    val result = runCatching { NativeGameRoomIntent.parseInput(input, role) }
                    result.fold(
                        onSuccess = { intent ->
                            onDismiss()
                            onJoinRoom(intent)
                        },
                        onFailure = { err ->
                            errorMessage = NativeGameError.message(err)
                        },
                    )
                },
                enabled = input.isNotBlank(),
            ) {
                Text("进入房间")
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NativeGameResourcesSheet(
    games: List<NativeGame>,
    profileKey: String,
    cacheStore: NativeGameResourceCacheStore,
    onDismiss: () -> Unit,
) {
    val entries by cacheStore.entries.collectAsStateWithLifecycle()
    val downloadingGameId by cacheStore.downloadingGameId.collectAsStateWithLifecycle()
    val progress by cacheStore.progress.collectAsStateWithLifecycle()
    val isClearing by cacheStore.isClearing.collectAsStateWithLifecycle()
    val error by cacheStore.error.collectAsStateWithLifecycle()
    val wifiOnly by cacheStore.wifiOnly.collectAsStateWithLifecycle()

    val gamesWithManifest = remember(games) {
        games.filter { it.resourceManifestUrl != null }
    }
    val profileEntries = remember(entries, profileKey) {
        entries.filter { it.profileKey == profileKey }
    }
    val totalBytes = remember(entries) { entries.sumOf { it.byteCount.toLong() } }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "游戏离线资源管理",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = "已缓存 ${formatBytesLabel(totalBytes)} / 200 MB（仅缓存公开静态资源并校验 SHA-256 摘要）",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Surface(
                shape = MaterialTheme.shapes.large,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("仅在 Wi-Fi 下准备资源", style = MaterialTheme.typography.titleSmall)
                    Switch(checked = wifiOnly, onCheckedChange = cacheStore::setWifiOnly)
                }
            }

            error?.let { msg ->
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(msg, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(12.dp))
                }
            }

            if (gamesWithManifest.isEmpty()) {
                Text(
                    text = "暂无支持预下载资源包的游戏。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                gamesWithManifest.forEach { game ->
                    val existing = profileEntries.firstOrNull { it.gameId == game.gameId }
                    val isThisDownloading = downloadingGameId == game.gameId
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = game.name,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Text(
                                        text = if (existing != null) {
                                            "已准备 · ${existing.resourceCount} 个文件 · ${formatBytesLabel(existing.byteCount.toLong())}"
                                        } else {
                                            "尚未准备离线资源"
                                        },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (isThisDownloading) {
                                    OutlinedButton(onClick = cacheStore::cancelDownload) {
                                        Text("取消")
                                    }
                                } else {
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        if (existing != null) {
                                            TextButton(
                                                onClick = { cacheStore.clear(game.gameId, profileKey) },
                                                enabled = !isClearing && downloadingGameId == null,
                                            ) {
                                                Text("清理")
                                            }
                                        }
                                        FilledTonalButton(
                                            onClick = {
                                                game.resourceManifestUrl?.let { url ->
                                                    cacheStore.download(url, game.gameId, profileKey)
                                                }
                                            },
                                            enabled = !isClearing && downloadingGameId == null,
                                        ) {
                                            Text(if (existing == null) "准备资源" else "更新")
                                        }
                                    }
                                }
                            }
                            if (isThisDownloading) {
                                LinearProgressIndicator(
                                    progress = { progress.coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                }
            }

            if (entries.isNotEmpty()) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                OutlinedButton(
                    onClick = { cacheStore.clear() },
                    enabled = !isClearing && downloadingGameId == null,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (isClearing) "正在清理…" else "清理全部游戏资源")
                }
            }
        }
    }
}

private fun formatBytesLabel(bytes: Long): String {
    if (bytes < 1024L) return "${bytes} B"
    val kb = bytes / 1024.0
    if (kb < 1024.0) return String.format(Locale.US, "%.1f KB", kb)
    return String.format(Locale.US, "%.2f MB", kb / 1024.0)
}
