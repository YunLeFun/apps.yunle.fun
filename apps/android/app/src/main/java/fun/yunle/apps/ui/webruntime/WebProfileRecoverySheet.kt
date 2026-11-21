package `fun`.yunle.apps.ui.webruntime

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.webruntime.WebProfileRepository
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WebProfileRecoverySheet(
    app: CatalogApp,
    accounts: AccountStore,
    webProfiles: WebProfileRepository,
    onCloseRuntime: () -> Unit,
    onDismiss: () -> Unit,
) {
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var loadedAccountId by remember { mutableStateOf<String?>(null) }
    var loadedGeneration by remember { mutableStateOf<UUID?>(null) }
    var snapshot by remember { mutableStateOf<WebProfileRepository.Snapshot?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var restoredNotice by remember { mutableStateOf(false) }
    var pendingRestore by remember { mutableStateOf<WebProfileRepository.Selection?>(null) }
    var isBusy by remember { mutableStateOf(false) }

    suspend fun reload() {
        val activeUser = overview.activeUser?.takeIf { it.isUsable }
        val gen = identityGeneration
        pendingRestore = null
        if (activeUser == null) {
            snapshot = null
            loadedAccountId = null
            loadedGeneration = gen
            errorMessage = "请先登录原账号，再查看它保存的应用数据。"
            return
        }
        val result = withContext(Dispatchers.IO) {
            runCatching {
                webProfiles.snapshot(WebProfileRepository.Principal.Account(activeUser.id), app)
            }
        }
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return
        result.fold(
            onSuccess = { loaded ->
                loadedAccountId = activeUser.id
                loadedGeneration = gen
                snapshot = loaded
                errorMessage = null
            },
            onFailure = {
                loadedAccountId = activeUser.id
                loadedGeneration = gen
                snapshot = null
                errorMessage = "暂时无法读取应用数据，原数据仍保留。请稍后重试。"
            },
        )
    }

    LaunchedEffect(app.id, overview.activeID, identityGeneration) {
        restoredNotice = false
        reload()
    }

    ModalBottomSheet(onDismissRequest = { if (!isBusy) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "应用数据",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = "这里保存着当前账号之前使用 ${app.name} 时留下的本机数据。选择一份后，下次打开应用会使用它，当前数据也会保留。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "应用内尚未保存的编辑请先保存。应用可能需要重新登录，云端内容以应用自身的同步规则为准。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            errorMessage?.let { error ->
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
                            text = error,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        OutlinedButton(
                            onClick = { scope.launch { reload() } },
                            enabled = !isBusy,
                        ) {
                            Text("重新读取")
                        }
                    }
                }
            }

            if (restoredNotice) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.6f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = "已切换应用数据，重新打开应用即可查看。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.padding(14.dp),
                    )
                }
            }

            val currentSnapshot = snapshot
            if (currentSnapshot != null && errorMessage == null) {
                val retained = currentSnapshot.retained
                if (retained.isEmpty()) {
                    Surface(
                        shape = MaterialTheme.shapes.medium,
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            text = "当前账号没有其他保留的数据。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(14.dp),
                        )
                    }
                } else {
                    Text(
                        text = "保留的数据",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics { heading() },
                    )
                    retained.indices.reversed().forEach { index ->
                        val profile = retained[index]
                        Surface(
                            onClick = { if (!isBusy) pendingRestore = profile },
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .defaultMinSize(minHeight = 52.dp)
                                    .padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    text = "保留记录 ${index + 1}",
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    text = "切换使用",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                    Text(
                        text = "每条记录都是一份独立保留的数据，可切换后打开应用核对。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))
            TextButton(
                onClick = onDismiss,
                enabled = !isBusy,
                modifier = Modifier.align(Alignment.End),
            ) {
                Text("关闭")
            }
        }
    }

    val confirmSelection = pendingRestore
    if (confirmSelection != null) {
        AlertDialog(
            onDismissRequest = { if (!isBusy) pendingRestore = null },
            title = { Text("使用这份数据？") },
            text = { Text("当前打开的应用会关闭。当前数据会保留，不会与这份数据合并；重新打开后可在应用内查看。") },
            confirmButton = {
                Button(
                    enabled = !isBusy,
                    onClick = {
                        val expectedAccountId = loadedAccountId
                        val expectedGeneration = loadedGeneration
                        val currentSnap = snapshot
                        pendingRestore = null
                        if (expectedAccountId == null ||
                            expectedGeneration == null ||
                            currentSnap == null ||
                            accounts.identityGeneration.value != expectedGeneration ||
                            accounts.user?.id != expectedAccountId
                        ) {
                            errorMessage = "账号或应用数据已变化，未执行本次切换。请重新读取后再试。"
                            return@Button
                        }
                        isBusy = true
                        onCloseRuntime()
                        scope.launch {
                            val activated = withContext(Dispatchers.IO) {
                                runCatching {
                                    webProfiles.activateRetained(
                                        selected = confirmSelection,
                                        accountID = expectedAccountId,
                                        application = app,
                                        replacing = currentSnap.active,
                                    )
                                }
                            }
                            isBusy = false
                            activated.fold(
                                onSuccess = {
                                    restoredNotice = true
                                    reload()
                                },
                                onFailure = {
                                    errorMessage = "账号或应用数据已变化，未执行本次切换。请重新读取后再试。"
                                },
                            )
                        }
                    },
                ) {
                    Text("使用此数据")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !isBusy,
                    onClick = { pendingRestore = null },
                ) {
                    Text("取消")
                }
            },
        )
    }
}
