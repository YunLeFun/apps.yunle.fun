package `fun`.yunle.apps.ui.workshop

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.WorkshopLink
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import `fun`.yunle.apps.workshop.PersonalWorkshop
import `fun`.yunle.apps.workshop.WorkshopAccess
import `fun`.yunle.apps.workshop.WorkshopDecision
import `fun`.yunle.apps.workshop.WorkshopDraft
import `fun`.yunle.apps.workshop.WorkshopError
import `fun`.yunle.apps.workshop.WorkshopJoinPolicy
import `fun`.yunle.apps.workshop.WorkshopLaunchAuthorization
import `fun`.yunle.apps.workshop.WorkshopManagement
import `fun`.yunle.apps.workshop.WorkshopMembership
import `fun`.yunle.apps.workshop.WorkshopPage
import `fun`.yunle.apps.workshop.WorkshopServing
import `fun`.yunle.apps.workshop.WorkshopStatus
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MyWorkshopsSheet(
    accounts: AccountStore,
    service: WorkshopServing,
    onOpenWorkshop: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var management by remember { mutableStateOf<WorkshopManagement?>(null) }
    var joined by remember { mutableStateOf<List<PersonalWorkshop>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showEditor by remember { mutableStateOf(false) }
    var editingExisting by remember { mutableStateOf<PersonalWorkshop?>(null) }

    suspend fun loadWorkshops() {
        val activeUser = accounts.user?.takeIf { it.isUsable }
        val gen = identityGeneration
        if (activeUser == null) {
            management = null
            joined = emptyList()
            errorMessage = "请先登录云乐坊账号后再管理个人工坊。"
            return
        }
        isLoading = true
        errorMessage = null
        val outcome = runCatching {
            val identity = accounts.authorization(forceRefresh = false)
            val owned = service.mine(identity)
            val joinedList = service.joined(identity)
            owned to joinedList
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return
        outcome.fold(
            onSuccess = { (owned, joinedList) ->
                management = owned
                joined = joinedList
            },
            onFailure = { err ->
                errorMessage = WorkshopError.message(err)
            },
        )
    }

    LaunchedEffect(overview.activeID, identityGeneration) {
        loadWorkshops()
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
                text = "个人工坊",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

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
                        Text(msg, style = MaterialTheme.typography.bodyMedium)
                        if (overview.activeUser?.isUsable == true) {
                            OutlinedButton(
                                onClick = { scope.launch { loadWorkshops() } },
                                enabled = !isBusy,
                            ) {
                                Text("重试")
                            }
                        }
                    }
                }
            }

            if (isLoading) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator()
                    Spacer(modifier = Modifier.width(12.dp))
                    Text("正在读取工坊…")
                }
            } else if (overview.activeUser?.isUsable == true) {
                val ownedMgmt = management
                Text(
                    text = "我创建的工坊",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
                if (ownedMgmt == null) {
                    Surface(
                        shape = MaterialTheme.shapes.medium,
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text = "创建你的个人工坊，分享私有应用并邀请坊客加入。",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Button(
                                onClick = {
                                    editingExisting = null
                                    showEditor = true
                                },
                                enabled = !isBusy,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .defaultMinSize(minHeight = 48.dp),
                            ) {
                                Text("创建个人工坊")
                            }
                        }
                    }
                } else {
                    val ws = ownedMgmt.workshop
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    text = ws.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    text = "#${ws.id}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                            if (!ws.description.isNullOrBlank()) {
                                Text(
                                    text = ws.description,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Text(
                                text = "${ws.status.label} · ${ws.joinPolicy.label}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                FilledTonalButton(
                                    onClick = { onOpenWorkshop(ws.id) },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("打开工坊")
                                }
                                OutlinedButton(
                                    onClick = {
                                        editingExisting = ws
                                        showEditor = true
                                    },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("编辑")
                                }
                                OutlinedButton(
                                    onClick = { copyText(context, ws.shareUrl) },
                                ) {
                                    Text("复制链接")
                                }
                            }
                        }
                    }

                    MemberManagementSection(
                        title = "待审批（${ownedMgmt.pending.size}）",
                        members = ownedMgmt.pending,
                        actions = listOf(
                            WorkshopDecision.APPROVE,
                            WorkshopDecision.REJECT,
                            WorkshopDecision.BLOCK,
                        ),
                        busy = isBusy,
                        onDecide = { member, action ->
                            scope.launch {
                                val expectedGen = accounts.identityGeneration.value
                                val expectedUid = accounts.user?.id ?: return@launch
                                isBusy = true
                                errorMessage = null
                                runCatching {
                                    val identity = accounts.authorization(forceRefresh = false)
                                    service.decide(ws.id, member, action, identity)
                                }.also {
                                    isBusy = false
                                }.fold(
                                    onSuccess = { updated ->
                                        if (accounts.identityGeneration.value == expectedGen &&
                                            accounts.user?.id == expectedUid
                                        ) {
                                            management = ownedMgmt.applying(updated)
                                        }
                                    },
                                    onFailure = { errorMessage = WorkshopError.message(it) },
                                )
                            }
                        },
                    )

                    MemberManagementSection(
                        title = "已加入坊客（${ownedMgmt.guests.size}）",
                        members = ownedMgmt.guests,
                        actions = listOf(WorkshopDecision.REMOVE, WorkshopDecision.BLOCK),
                        busy = isBusy,
                        onDecide = { member, action ->
                            scope.launch {
                                val expectedGen = accounts.identityGeneration.value
                                val expectedUid = accounts.user?.id ?: return@launch
                                isBusy = true
                                errorMessage = null
                                runCatching {
                                    val identity = accounts.authorization(forceRefresh = false)
                                    service.decide(ws.id, member, action, identity)
                                }.also {
                                    isBusy = false
                                }.fold(
                                    onSuccess = { updated ->
                                        if (accounts.identityGeneration.value == expectedGen &&
                                            accounts.user?.id == expectedUid
                                        ) {
                                            management = ownedMgmt.applying(updated)
                                        }
                                    },
                                    onFailure = { errorMessage = WorkshopError.message(it) },
                                )
                            }
                        },
                    )

                    if (ownedMgmt.blocked.isNotEmpty()) {
                        MemberManagementSection(
                            title = "已禁止（${ownedMgmt.blocked.size}）",
                            members = ownedMgmt.blocked,
                            actions = listOf(WorkshopDecision.UNBLOCK),
                            busy = isBusy,
                            onDecide = { member, action ->
                                scope.launch {
                                    val expectedGen = accounts.identityGeneration.value
                                    val expectedUid = accounts.user?.id ?: return@launch
                                    isBusy = true
                                    errorMessage = null
                                    runCatching {
                                        val identity = accounts.authorization(forceRefresh = false)
                                        service.decide(ws.id, member, action, identity)
                                    }.also {
                                        isBusy = false
                                    }.fold(
                                        onSuccess = { updated ->
                                            if (accounts.identityGeneration.value == expectedGen &&
                                                accounts.user?.id == expectedUid
                                            ) {
                                                management = ownedMgmt.applying(updated)
                                            }
                                        },
                                        onFailure = { errorMessage = WorkshopError.message(it) },
                                    )
                                }
                            },
                        )
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Text(
                    text = "已加入的工坊（${joined.size}）",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
                if (joined.isEmpty()) {
                    Text(
                        text = "尚未加入其他人的个人工坊。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    joined.forEach { ws ->
                        Surface(
                            onClick = { onOpenWorkshop(ws.id) },
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .defaultMinSize(minHeight = 56.dp)
                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = ws.name,
                                        style = MaterialTheme.typography.bodyLarge,
                                        fontWeight = FontWeight.Medium,
                                    )
                                    Text(
                                        text = "${ws.ownerName} · #${ws.id}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Text(
                                    text = "打开",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
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

    if (showEditor) {
        WorkshopEditorDialog(
            existing = editingExisting,
            busy = isBusy,
            onSave = { draft ->
                scope.launch {
                    val expectedGen = accounts.identityGeneration.value
                    val expectedUid = accounts.user?.id ?: return@launch
                    isBusy = true
                    errorMessage = null
                    runCatching {
                        val identity = accounts.authorization(forceRefresh = false)
                        val existing = editingExisting
                        if (existing == null) {
                            service.create(draft, identity)
                        } else {
                            service.update(existing.id, draft, identity)
                        }
                    }.also {
                        isBusy = false
                    }.fold(
                        onSuccess = {
                            showEditor = false
                            if (accounts.identityGeneration.value == expectedGen &&
                                accounts.user?.id == expectedUid
                            ) {
                                loadWorkshops()
                            }
                        },
                        onFailure = {
                            errorMessage = WorkshopError.message(it)
                        },
                    )
                }
            },
            onDismiss = { if (!isBusy) showEditor = false },
        )
    }
}

@Composable
private fun MemberManagementSection(
    title: String,
    members: List<WorkshopMembership>,
    actions: List<WorkshopDecision>,
    busy: Boolean,
    onDecide: (WorkshopMembership, WorkshopDecision) -> Unit,
) {
    if (members.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        members.forEach { member ->
            Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = member.displayName,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        actions.forEach { decision ->
                            OutlinedButton(
                                onClick = { onDecide(member, decision) },
                                enabled = !busy && decision.allows(member.status),
                            ) {
                                Text(decision.label)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WorkshopEditorDialog(
    existing: PersonalWorkshop?,
    busy: Boolean,
    onSave: (WorkshopDraft) -> Unit,
    onDismiss: () -> Unit,
) {
    val initial = remember(existing) {
        existing?.let(WorkshopDraft::fromWorkshop) ?: WorkshopDraft()
    }
    var name by remember { mutableStateOf(initial.name) }
    var description by remember { mutableStateOf(initial.description) }
    var joinPolicy by remember { mutableStateOf(initial.joinPolicy) }
    var status by remember { mutableStateOf(initial.status) }
    val draft = WorkshopDraft(name = name, description = description, joinPolicy = joinPolicy, status = status)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "创建个人工坊" else "编辑工坊信息") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { if (it.length <= 40) name = it },
                    label = { Text("工坊名称") },
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { if (it.length <= 200) description = it },
                    label = { Text("工坊简介（可选）") },
                    minLines = 2,
                    maxLines = 4,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (existing != null) {
                    Text("加入方式", style = MaterialTheme.typography.labelLarge)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        WorkshopJoinPolicy.entries.forEach { policy ->
                            FilterChip(
                                selected = joinPolicy == policy,
                                onClick = { joinPolicy = policy },
                                label = { Text(policy.label) },
                            )
                        }
                    }
                    Text("工坊状态", style = MaterialTheme.typography.labelLarge)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        WorkshopStatus.entries.forEach { wsStatus ->
                            FilterChip(
                                selected = status == wsStatus,
                                onClick = { status = wsStatus },
                                label = { Text(wsStatus.label) },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onSave(draft) },
                enabled = !busy && draft.isValid,
            ) {
                Text("保存")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !busy) {
                Text("取消")
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PublicWorkshopSheet(
    workshopId: String,
    accounts: AccountStore,
    service: WorkshopServing,
    onLaunchApp: (CatalogApp) -> Unit,
    onSelectAppDetail: (CatalogApp) -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var page by remember { mutableStateOf<WorkshopPage?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    suspend fun loadPage() {
        val gen = identityGeneration
        val activeUser = accounts.user?.takeIf { it.isUsable }
        isLoading = true
        errorMessage = null
        val loaded = runCatching {
            val identity = activeUser?.let { accounts.authorization(forceRefresh = false) }
            service.page(workshopId, identity)
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser?.id) return
        loaded.fold(
            onSuccess = { page = it },
            onFailure = { errorMessage = WorkshopError.message(it) },
        )
    }

    LaunchedEffect(workshopId, overview.activeID, identityGeneration) {
        loadPage()
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
            when {
                isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 28.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                errorMessage != null && page == null -> {
                    Text(
                        text = "个人工坊 #$workshopId",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = errorMessage!!,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    OutlinedButton(onClick = { scope.launch { loadPage() } }) {
                        Text("重试")
                    }
                }

                else -> {
                    val currentPage = page!!
                    val ws = currentPage.workshop
                    Text(
                        text = ws.name,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = "${ws.ownerName} 的个人工坊 · #$workshopId · ${ws.status.label}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (!ws.description.isNullOrBlank()) {
                        Text(
                            text = ws.description,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }

                    errorMessage?.let { msg ->
                        Text(
                            text = msg,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        when (currentPage.access) {
                            WorkshopAccess.ANONYMOUS -> {
                                Button(
                                    onClick = {
                                        onDismiss()
                                        onNavigateToMe()
                                    },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("登录后加入")
                                }
                            }
                            WorkshopAccess.NONE -> {
                                if (ws.status == WorkshopStatus.ACTIVE && ws.joinPolicy != WorkshopJoinPolicy.CLOSED) {
                                    Button(
                                        enabled = !isBusy,
                                        onClick = {
                                            scope.launch {
                                                isBusy = true
                                                errorMessage = null
                                                runCatching {
                                                    val identity = accounts.authorization(forceRefresh = false)
                                                    service.join(ws.id, identity)
                                                }.also { isBusy = false }.fold(
                                                    onSuccess = { loadPage() },
                                                    onFailure = { errorMessage = WorkshopError.message(it) },
                                                )
                                            }
                                        },
                                        modifier = Modifier.weight(1f),
                                    ) {
                                        Text(
                                            if (ws.joinPolicy == WorkshopJoinPolicy.APPROVAL) "申请加入" else "加入工坊",
                                        )
                                    }
                                }
                            }
                            WorkshopAccess.PENDING -> {
                                FilledTonalButton(
                                    onClick = {},
                                    enabled = false,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("申请审核中")
                                }
                            }
                            WorkshopAccess.ACTIVE -> {
                                OutlinedButton(
                                    enabled = !isBusy,
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        contentColor = MaterialTheme.colorScheme.error,
                                    ),
                                    onClick = {
                                        scope.launch {
                                            isBusy = true
                                            errorMessage = null
                                            runCatching {
                                                val identity = accounts.authorization(forceRefresh = false)
                                                service.leave(ws.id, identity)
                                            }.also { isBusy = false }.fold(
                                                onSuccess = { loadPage() },
                                                onFailure = { errorMessage = WorkshopError.message(it) },
                                            )
                                        }
                                    },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("退出工坊")
                                }
                            }
                            WorkshopAccess.OWNER -> {
                                FilledTonalButton(
                                    onClick = {},
                                    enabled = false,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("我是坊主")
                                }
                            }
                            WorkshopAccess.BLOCKED -> {
                                FilledTonalButton(
                                    onClick = {},
                                    enabled = false,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("已被工坊限制访问")
                                }
                            }
                        }

                        OutlinedButton(onClick = { copyText(context, ws.shareUrl) }) {
                            Text("分享链接")
                        }
                    }

                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                    if (!currentPage.permitsApps) {
                        Text(
                            text = if (ws.status == WorkshopStatus.DISABLED) {
                                "该工坊当前已暂停开放。"
                            } else {
                                "加入该工坊并通过后可查看和使用其中的应用。"
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else if (currentPage.apps.isEmpty()) {
                        Text(
                            text = "该工坊里还没有公开应用。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        Text(
                            text = "工坊应用 · ${currentPage.apps.size}",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.semantics { heading() },
                        )
                        currentPage.apps.forEach { app ->
                            Surface(
                                onClick = { onSelectAppDetail(app) },
                                shape = MaterialTheme.shapes.medium,
                                color = MaterialTheme.colorScheme.surfaceContainerLow,
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 64.dp)
                                        .padding(horizontal = 14.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    AppIconBadge(app = app, size = 48.dp)
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = app.name,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                        Text(
                                            text = app.description.ifBlank { app.author },
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    FilledTonalButton(
                                        enabled = !isBusy,
                                        onClick = {
                                            scope.launch {
                                                isBusy = true
                                                errorMessage = null
                                                runCatching {
                                                    val identity = accounts.user?.takeIf { it.isUsable }?.let {
                                                        accounts.authorization(forceRefresh = false)
                                                    }
                                                    WorkshopLaunchAuthorization.resolve(app, identity, service)
                                                }.also { isBusy = false }.fold(
                                                    onSuccess = { authorizedApp -> onLaunchApp(authorizedApp) },
                                                    onFailure = { errorMessage = WorkshopError.message(it) },
                                                )
                                            }
                                        },
                                    ) {
                                        Text("打开")
                                    }
                                }
                            }
                        }
                    }
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
}

@Composable
internal fun WorkshopLookupDialog(
    onOpenWorkshop: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var input by remember { mutableStateOf("") }
    val normalized = remember(input) { WorkshopLink.parse(input) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("打开个人工坊") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "输入 6 位工坊编号（如 2345AB）或工坊链接。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it },
                    label = { Text("工坊编号或链接") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(
                enabled = normalized != null,
                onClick = { normalized?.let(onOpenWorkshop) },
            ) {
                Text("打开")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeWorkspacePickerSheet(
    accounts: AccountStore,
    service: WorkshopServing,
    activeWorkshopId: String?,
    onSelectPersonal: () -> Unit,
    onSelectWorkshop: (PersonalWorkshop, WorkshopPage) -> Unit,
    onDismiss: () -> Unit,
) {
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var workshops by remember { mutableStateOf<List<PersonalWorkshop>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var isSwitching by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(overview.activeID, identityGeneration) {
        val activeUser = accounts.user?.takeIf { it.isUsable }
        if (activeUser == null) {
            workshops = emptyList()
            return@LaunchedEffect
        }
        isLoading = true
        errorMessage = null
        runCatching {
            val identity = accounts.authorization(forceRefresh = false)
            val owned = service.mine(identity)?.workshop
            val joined = service.joined(identity)
            (listOfNotNull(owned) + joined).distinctBy { it.id }
        }.also { isLoading = false }.fold(
            onSuccess = { workshops = it },
            onFailure = { errorMessage = WorkshopError.message(it) },
        )
    }

    ModalBottomSheet(onDismissRequest = { if (!isSwitching) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "切换云居工作区",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            Surface(
                onClick = { if (!isSwitching) onSelectPersonal() },
                shape = RoundedCornerShape(14.dp),
                color = if (activeWorkshopId == null) {
                    MaterialTheme.colorScheme.primaryContainer
                } else {
                    MaterialTheme.colorScheme.surfaceContainerLow
                },
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
                    Column {
                        Text("我的云居", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text("个人常用桌面与文件夹", style = MaterialTheme.typography.bodySmall)
                    }
                    if (activeWorkshopId == null) {
                        Text("当前", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }

            if (isLoading || isSwitching) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            errorMessage?.let { msg ->
                Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            if (workshops.isNotEmpty()) {
                Text(
                    text = "工坊云居",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                workshops.forEach { ws ->
                    val selected = activeWorkshopId == ws.id
                    Surface(
                        enabled = !isSwitching,
                        onClick = {
                            scope.launch {
                                isSwitching = true
                                errorMessage = null
                                runCatching {
                                    val identity = accounts.authorization(forceRefresh = false)
                                    service.page(ws.id, identity)
                                }.also { isSwitching = false }.fold(
                                    onSuccess = { loadedPage -> onSelectWorkshop(ws, loadedPage) },
                                    onFailure = { errorMessage = WorkshopError.message(it) },
                                )
                            }
                        },
                        shape = RoundedCornerShape(14.dp),
                        color = if (selected) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerLow
                        },
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
                            Column(modifier = Modifier.weight(1f)) {
                                Text(ws.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                Text(
                                    text = "${ws.ownerName} · #${ws.id}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            if (selected) {
                                Text("当前", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }

            TextButton(
                onClick = onDismiss,
                enabled = !isSwitching,
                modifier = Modifier.align(Alignment.End),
            ) {
                Text("关闭")
            }
        }
    }
}

private fun copyText(context: Context, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("云乐坊工坊链接", text))
    Toast.makeText(context, "已复制链接", Toast.LENGTH_SHORT).show()
}
