package `fun`.yunle.apps.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.home.HomeBackupError
import `fun`.yunle.apps.home.HomeBackupException
import `fun`.yunle.apps.home.HomeBackupItem
import `fun`.yunle.apps.home.HomeBackupPreview
import `fun`.yunle.apps.home.HomeBackupRepository
import `fun`.yunle.apps.home.HomeLibrary
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class HomeBackupBoundary(
    val accountId: String?,
    val identityGeneration: UUID,
    val libraryGeneration: Int,
    val ownerFileName: String,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeBackupsSheet(
    accounts: AccountStore,
    homeLibrary: HomeLibrary,
    onDismiss: () -> Unit,
) {
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val libraryGeneration by homeLibrary.generation.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val repository = remember(homeLibrary) { HomeBackupRepository(homeLibrary.storageDirectory) }

    var items by remember { mutableStateOf<List<HomeBackupItem>>(emptyList()) }
    var listBoundary by remember { mutableStateOf<HomeBackupBoundary?>(null) }
    var isLoadingList by remember { mutableStateOf(false) }

    var selectedPreview by remember { mutableStateOf<HomeBackupPreview?>(null) }
    var previewBoundary by remember { mutableStateOf<HomeBackupBoundary?>(null) }
    var isLoadingPreview by remember { mutableStateOf(false) }

    var restoreSettings by remember { mutableStateOf(true) }
    var confirmRestore by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var restoredBanner by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val activeUser = overview.activeUser
    val targetLabel = activeUser?.let { "当前账号：${it.displayName}" } ?: "本机访客云居"
    val dateFormat = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()) }

    fun captureBoundary(): HomeBackupBoundary? {
        val currentUser = accounts.user
        val activeId = currentUser?.id
        if (activeId != homeLibrary.activeAccountId) return null
        if (currentUser != null && !currentUser.isUsable) return null
        return HomeBackupBoundary(
            accountId = homeLibrary.activeAccountId,
            identityGeneration = accounts.identityGeneration.value,
            libraryGeneration = homeLibrary.generation.value,
            ownerFileName = homeLibrary.currentFileName,
        )
    }

    fun isSameBoundary(boundary: HomeBackupBoundary): Boolean =
        accounts.user?.id == boundary.accountId &&
            accounts.identityGeneration.value == boundary.identityGeneration &&
            homeLibrary.activeAccountId == boundary.accountId &&
            homeLibrary.generation.value == boundary.libraryGeneration &&
            homeLibrary.currentFileName == boundary.ownerFileName

    suspend fun loadList() {
        val boundary = captureBoundary()
        if (boundary == null) {
            items = emptyList()
            listBoundary = null
            errorMessage = HomeBackupError.IDENTITY_CHANGED.message
            return
        }
        isLoadingList = true
        errorMessage = null
        val loaded = withContext(Dispatchers.IO) {
            runCatching { repository.list(boundary.ownerFileName) }
        }
        isLoadingList = false
        if (!isSameBoundary(boundary)) {
            errorMessage = HomeBackupError.IDENTITY_CHANGED.message
            return
        }
        loaded.fold(
            onSuccess = {
                listBoundary = boundary
                items = it
            },
            onFailure = {
                errorMessage = HomeBackupError.UNREADABLE.message
            },
        )
    }

    suspend fun openPreview(id: String) {
        val boundary = captureBoundary()
        if (boundary == null) {
            errorMessage = HomeBackupError.IDENTITY_CHANGED.message
            return
        }
        isLoadingPreview = true
        restoredBanner = false
        errorMessage = null
        val loaded = withContext(Dispatchers.IO) {
            runCatching { repository.preview(id, boundary.ownerFileName) }
        }
        isLoadingPreview = false
        if (!isSameBoundary(boundary)) {
            errorMessage = HomeBackupError.IDENTITY_CHANGED.message
            return
        }
        loaded.fold(
            onSuccess = { preview ->
                previewBoundary = boundary
                selectedPreview = preview
            },
            onFailure = { err ->
                errorMessage = (err as? HomeBackupException)?.error?.message
                    ?: HomeBackupError.UNREADABLE.message
            },
        )
    }

    LaunchedEffect(overview.activeID, identityGeneration, libraryGeneration) {
        selectedPreview = null
        previewBoundary = null
        confirmRestore = false
        loadList()
    }

    ModalBottomSheet(onDismissRequest = { if (!isRestoring) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = if (selectedPreview != null) "备份详情" else "云居备份",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = "当前云居：$targetLabel",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                )
            }

            if (homeLibrary.needsRecovery) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.55f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = "当前云居暂时无法读取。恢复前会保留原文件。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(14.dp),
                    )
                }
            }

            if (restoredBanner) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.65f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = "已恢复云居",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.padding(14.dp),
                    )
                }
            }

            errorMessage?.let { msg ->
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = msg,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        OutlinedButton(
                            onClick = { scope.launch { loadList() } },
                            enabled = !isRestoring,
                        ) {
                            Text("重试")
                        }
                    }
                }
            }

            val preview = selectedPreview
            if (isLoadingList || isLoadingPreview) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator()
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = if (isLoadingPreview) "正在打开备份…" else "正在读取备份…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else if (preview != null) {
                val config = preview.snapshot.configuration
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        BackupDetailRow("备份来源", preview.item.kind.label)
                        if (preview.item.savedAtMillis > 0L) {
                            BackupDetailRow("保存时间", dateFormat.format(Date(preview.item.savedAtMillis)))
                        }
                        BackupDetailRow("恢复位置", targetLabel)
                        BackupDetailRow("应用", "${config.installedApps.size}")
                        BackupDetailRow("常用应用", "${config.dockApps.size}")
                        BackupDetailRow("文件夹", "${config.folders.size}")
                        BackupDetailRow("最近使用", "${config.recentApps.size}")
                        val appNames = (preview.snapshot.applications + preview.snapshot.dockApplications)
                            .distinctBy { it.homeKey }
                            .take(8)
                            .map { it.name }
                        if (appNames.isNotEmpty()) {
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                            Text(
                                text = "包含应用：${appNames.joinToString("、")}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }

                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = "同时恢复云居设置",
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                            )
                            Switch(
                                checked = restoreSettings,
                                onCheckedChange = { if (!isRestoring) restoreSettings = it },
                                enabled = !isRestoring,
                            )
                        }
                        if (restoreSettings) {
                            BackupDetailRow("云同步", if (preview.snapshot.syncEnabled) "开启" else "关闭")
                            BackupDetailRow("自动同步", if (preview.snapshot.autoSyncEnabled) "开启" else "关闭")
                            BackupDetailRow("常用应用显示", if (preview.snapshot.dockVisible) "显示" else "隐藏")
                        }
                    }
                }

                Text(
                    text = "替换前会保留当前版本，之后也能从备份页找回。登录账号和购买权益以当前账号记录为准。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Button(
                    onClick = { confirmRestore = true },
                    enabled = !isRestoring,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier
                        .fillMaxWidth()
                        .defaultMinSize(minHeight = 48.dp),
                ) {
                    Text(if (isRestoring) "正在恢复云居…" else "恢复此备份")
                }

                OutlinedButton(
                    onClick = {
                        selectedPreview = null
                        previewBoundary = null
                        errorMessage = null
                    },
                    enabled = !isRestoring,
                    modifier = Modifier
                        .fillMaxWidth()
                        .defaultMinSize(minHeight = 48.dp),
                ) {
                    Text("返回备份列表")
                }
            } else {
                val validItems = if (listBoundary?.let(::isSameBoundary) == true) items else emptyList()
                if (validItems.isEmpty() && errorMessage == null) {
                    Surface(
                        shape = MaterialTheme.shapes.medium,
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(
                                text = "还没有云居备份",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = "选择云端版本或恢复备份前，会在此设备保留当前版本。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                } else {
                    validItems.forEach { item ->
                        Surface(
                            onClick = { scope.launch { openPreview(item.id) } },
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .defaultMinSize(minHeight = 56.dp)
                                    .padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(
                                        text = item.kind.label,
                                        style = MaterialTheme.typography.bodyLarge,
                                        fontWeight = FontWeight.Medium,
                                    )
                                    Text(
                                        text = if (item.savedAtMillis > 0L) {
                                            dateFormat.format(Date(item.savedAtMillis))
                                        } else {
                                            "日期未知"
                                        },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Text(
                                    text = "查看",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                    Text(
                        text = "只显示当前账号或访客云居在此设备的备份。恢复前可以查看内容，再决定是否替换。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))
            TextButton(
                onClick = onDismiss,
                enabled = !isRestoring,
                modifier = Modifier.align(Alignment.End),
            ) {
                Text("关闭")
            }
        }
    }

    if (confirmRestore && selectedPreview != null) {
        val currentPreview = selectedPreview!!
        AlertDialog(
            onDismissRequest = { if (!isRestoring) confirmRestore = false },
            title = { Text("恢复此备份？") },
            text = {
                Text("将替换${targetLabel}的云居。恢复前会保留当前版本；如果原文件已损坏，会保留其原始文件。")
            },
            confirmButton = {
                Button(
                    enabled = !isRestoring,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                    onClick = {
                        val boundary = previewBoundary
                        confirmRestore = false
                        if (boundary == null || !isSameBoundary(boundary)) {
                            errorMessage = HomeBackupError.IDENTITY_CHANGED.message
                            return@Button
                        }
                        isRestoring = true
                        val restoreId = UUID.randomUUID().toString()
                        scope.launch {
                            val verified = withContext(Dispatchers.IO) {
                                runCatching {
                                    val fresh = repository.preview(currentPreview.item.id, boundary.ownerFileName)
                                    if (fresh.sha256Digest != currentPreview.sha256Digest) {
                                        throw HomeBackupException(HomeBackupError.BACKUP_CHANGED)
                                    }
                                    fresh
                                }
                            }
                            verified.fold(
                                onSuccess = { fresh ->
                                    if (!isSameBoundary(boundary)) {
                                        isRestoring = false
                                        errorMessage = HomeBackupError.IDENTITY_CHANGED.message
                                        return@fold
                                    }
                                    val ok = homeLibrary.restoreBackup(
                                        restored = fresh.snapshot,
                                        restoreSettings = restoreSettings,
                                        restoreId = restoreId,
                                        expectedAccountId = boundary.accountId,
                                        expectedGeneration = boundary.libraryGeneration,
                                    )
                                    isRestoring = false
                                    if (ok) {
                                        restoredBanner = true
                                        selectedPreview = null
                                        previewBoundary = null
                                        errorMessage = null
                                        loadList()
                                    } else {
                                        errorMessage = HomeBackupError.IDENTITY_CHANGED.message
                                    }
                                },
                                onFailure = { err ->
                                    isRestoring = false
                                    errorMessage = (err as? HomeBackupException)?.error?.message
                                        ?: HomeBackupError.UNREADABLE.message
                                },
                            )
                        }
                    },
                ) {
                    Text("确认恢复")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !isRestoring,
                    onClick = { confirmRestore = false },
                ) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun BackupDetailRow(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
