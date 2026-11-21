package `fun`.yunle.apps.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.AppAppearance
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.home.HomeLibrary
import `fun`.yunle.apps.home.LegacyImportConfirmation
import `fun`.yunle.apps.home.LegacyImportError
import `fun`.yunle.apps.home.LegacyImportStore
import `fun`.yunle.apps.home.LegacyLocalData
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LegacyMigrationSheet(
    store: LegacyImportStore,
    accounts: AccountStore,
    library: HomeLibrary,
    onDismiss: () -> Unit,
) {
    val archive by store.archive.collectAsStateWithLifecycle()
    val isLoading by store.isLoading.collectAsStateWithLifecycle()
    val isLoaded by store.isLoaded.collectAsStateWithLifecycle()
    val error by store.error.collectAsStateWithLifecycle()
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val accountGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val libraryGeneration = library.generation.collectAsStateWithLifecycle().value
    val scope = rememberCoroutineScope()
    var confirmation by remember { mutableStateOf<LegacyImportConfirmation?>(null) }
    var targetChanged by remember { mutableStateOf(false) }
    val user = overview.activeUser
    val currentConfirmation = confirmation?.takeIf {
        it.accountID == user?.id && it.accountID == library.activeAccountId &&
            it.accountGeneration == accountGeneration && it.libraryGeneration == libraryGeneration &&
            (user == null || user.isUsable)
    }
    val targetLabel = store.targetLabel
    val visibleArchive = archive?.takeIf { store.belongsToCurrentTarget }

    LaunchedEffect(store) { store.load() }
    LaunchedEffect(confirmation, currentConfirmation) {
        if (confirmation != null && currentConfirmation == null) {
            confirmation = null
            targetChanged = true
        }
    }

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
                text = "旧版数据导入",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics { heading() },
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
            ) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text("导入位置 · $targetLabel", style = MaterialTheme.typography.titleSmall)
                    Text("访客云居和登录后的账号云居各自独立保存。", style = MaterialTheme.typography.bodyMedium)
                }
            }
            if (targetChanged) {
                LegacyStatus(LegacyImportError.IDENTITY_CHANGED.message)
            }
            error?.let {
                Text(
                    text = it.message,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                )
                OutlinedButton(
                    onClick = {
                        targetChanged = false
                        scope.launch { store.load(retry = true) }
                    },
                    enabled = !isLoading,
                    modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                ) {
                    Text("重新读取")
                }
            }

            when {
                isLoading -> Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator(Modifier.size(20.dp))
                    LegacyStatus("正在读取旧版记录")
                }
                archive != null && visibleArchive == null ->
                    LegacyStatus("此旧版记录已由另一个云居认领，请切换到原账号查看")
                isLoaded && visibleArchive?.claim?.completed == true ->
                    LegacyStatus("已完成旧版数据导入")
                isLoaded && visibleArchive != null -> {
                    LegacyPreview(visibleArchive.record)
                    Button(
                        onClick = {
                            targetChanged = false
                            confirmation = store.prepareConfirmation()
                        },
                        modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp),
                    ) {
                        Text("导入到当前云居")
                    }
                }
                isLoaded -> {
                    LegacyStatus("未检测到旧版应用数据")
                    Text(
                        text = "旧版数据需保留在同一设备上的原应用存储中。卸载重装或安装独立的开发版后，可能无法读取这些数据。",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }

    currentConfirmation?.let { pending ->
        AlertDialog(
            onDismissRequest = { confirmation = null },
            title = { Text("导入旧版数据？") },
            text = {
                Text("将导入到$targetLabel。当前云居会先保存一份本机备份，再应用旧版布局和对应设置。旧版原记录会继续保留。")
            },
            confirmButton = {
                Button(onClick = {
                    confirmation = null
                    store.apply(pending)
                }) {
                    Text("确认导入")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmation = null }) { Text("取消") }
            },
        )
    }
}

@Composable
private fun LegacyStatus(message: String) {
    Text(
        text = message,
        style = MaterialTheme.typography.bodyLarge,
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
    )
}

@Composable
private fun LegacyPreview(record: LegacyLocalData) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "导入预览",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { heading() },
            )
            record.configuration?.let {
                LegacyPreviewRow("应用", it.installedApps.size.toString())
                LegacyPreviewRow("常用栏应用", it.dockApps.size.toString())
                LegacyPreviewRow("最近使用", it.recentApps.size.toString())
            }
            record.appearance?.let { LegacyPreviewRow("显示模式", AppAppearance.fromKey(it).label) }
            record.syncEnabled?.let { LegacyPreviewRow("云同步", if (it) "开启" else "关闭") }
            record.autoSyncEnabled?.let { LegacyPreviewRow("自动同步", if (it) "开启" else "关闭") }
            record.dockVisible?.let { LegacyPreviewRow("常用栏", if (it) "显示" else "隐藏") }
            if (record.hasOtherSettings) {
                Text("浏览器、图标等其他旧版设置仍会保留在此设备。", style = MaterialTheme.typography.bodyMedium)
            }
            if (record.accounts.isNotEmpty()) {
                Text("旧版账号记录", style = MaterialTheme.typography.titleSmall)
                record.accounts.forEach { Text(it.label, style = MaterialTheme.typography.bodyMedium) }
                Text("这些账号名称仅供辨认，旧版账号需要重新登录。", style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun LegacyPreviewRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
