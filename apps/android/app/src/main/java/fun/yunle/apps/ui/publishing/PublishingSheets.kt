package `fun`.yunle.apps.ui.publishing

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.publishing.ApplicationAccessMode
import `fun`.yunle.apps.publishing.ApplicationAudience
import `fun`.yunle.apps.publishing.ApplicationDraft
import `fun`.yunle.apps.publishing.ApplicationDraftVault
import `fun`.yunle.apps.publishing.ApplicationIconNormalizer
import `fun`.yunle.apps.publishing.ApplicationIconRole
import `fun`.yunle.apps.publishing.ApplicationReleaseStage
import `fun`.yunle.apps.publishing.ManagedApplication
import `fun`.yunle.apps.publishing.PublicationAction
import `fun`.yunle.apps.publishing.PublishingAccess
import `fun`.yunle.apps.publishing.PublishingError
import `fun`.yunle.apps.publishing.PublishingServing
import `fun`.yunle.apps.publishing.SavedApplicationDraft
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun MyApplicationsSheet(
    accounts: AccountStore,
    service: PublishingServing,
    draftVault: ApplicationDraftVault,
    onLaunchPreview: (CatalogApp) -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var access by remember { mutableStateOf<PublishingAccess?>(null) }
    var apps by remember { mutableStateOf<List<ManagedApplication>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var editorTarget by remember { mutableStateOf<Pair<Boolean, ManagedApplication?>?>(null) }
    var submitTarget by remember { mutableStateOf<ManagedApplication?>(null) }
    var confirmDelist by remember { mutableStateOf<ManagedApplication?>(null) }

    suspend fun loadApplications() {
        val activeUser = accounts.user?.takeIf { it.isUsable } ?: run {
            access = null
            apps = emptyList()
            return
        }
        val gen = identityGeneration
        isLoading = true
        errorMessage = null
        val res = runCatching {
            val identity = accounts.authorization(forceRefresh = false)
            val acc = service.access(identity)
            val list = service.applications(identity)
            acc to list
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return
        res.fold(
            onSuccess = { (acc, list) ->
                access = acc
                apps = list
            },
            onFailure = { errorMessage = PublishingError.message(it) },
        )
    }

    LaunchedEffect(overview.activeID, identityGeneration) {
        loadApplications()
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
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "我的应用发布",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                if (overview.activeUser?.isUsable == true && access?.canSubmitFirstParty == true) {
                    Button(
                        onClick = { editorTarget = true to null },
                        enabled = !isBusy,
                    ) {
                        Text("新建应用")
                    }
                }
            }

            if (overview.activeUser?.isUsable != true) {
                Text(
                    text = "请先登录云乐坊账号后再管理并发布个人作品。",
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

            access?.takeIf { !it.canSubmitFirstParty }?.let { denied ->
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = denied.thirdPartyMessage.ifBlank { "当前账号暂未开通第一方作品投稿权限，请确认已绑定手机号且状态正常。" },
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(12.dp),
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
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(msg, style = MaterialTheme.typography.bodySmall)
                        OutlinedButton(onClick = { scope.launch { loadApplications() } }, enabled = !isBusy) {
                            Text("重试")
                        }
                    }
                }
            }

            if (isLoading && apps.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else if (apps.isEmpty() && errorMessage == null) {
                Text(
                    text = "你还没有创建或发布过应用。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                apps.forEach { managed ->
                    val state = managed.marketState
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
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                AppIconBadge(app = managed.application, size = 48.dp)
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = managed.application.name,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        text = state.label,
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                            }
                            Text(
                                text = state.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                if (managed.application.launchUrl != null) {
                                    FilledTonalButton(
                                        onClick = {
                                            onDismiss()
                                            onLaunchPreview(managed.application)
                                        },
                                        enabled = !isBusy,
                                    ) {
                                        Text("预览")
                                    }
                                }
                                OutlinedButton(
                                    onClick = { editorTarget = true to managed },
                                    enabled = !isBusy,
                                ) {
                                    Text("编辑")
                                }
                                if (state.action == PublicationAction.SUBMIT || state.action == PublicationAction.MAKE_PUBLIC) {
                                    FilledTonalButton(
                                        onClick = { submitTarget = managed },
                                        enabled = !isBusy && managed.writeVersion != null,
                                    ) {
                                        Text(if (state.action == PublicationAction.MAKE_PUBLIC) "投稿云乐坊" else "提交审核")
                                    }
                                }
                                if (managed.writeVersion != null) {
                                    TextButton(
                                        onClick = { confirmDelist = managed },
                                        enabled = !isBusy,
                                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                                    ) {
                                        Text("下架")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    editorTarget?.let { (_, existing) ->
        ApplicationEditorSheet(
            existing = existing,
            accounts = accounts,
            service = service,
            draftVault = draftVault,
            onSaved = {
                editorTarget = null
                scope.launch { loadApplications() }
            },
            onDismiss = { editorTarget = null },
        )
    }

    submitTarget?.let { managed ->
        var shortName by remember(managed.id) { mutableStateOf(managed.draft.slug) }
        var makePublic by remember(managed.id) {
            mutableStateOf(managed.draft.audience == ApplicationAudience.PUBLIC)
        }
        var submitErr by remember { mutableStateOf<String?>(null) }
        AlertDialog(
            onDismissRequest = { if (!isBusy) submitTarget = null },
            title = { Text("投稿「${managed.application.name}」") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("同时设为公开作品", style = MaterialTheme.typography.bodyMedium)
                        Switch(checked = makePublic, onCheckedChange = { makePublic = it }, enabled = !isBusy)
                    }
                    OutlinedTextField(
                        value = shortName,
                        onValueChange = { shortName = it },
                        label = { Text("市场短名（选填，2–50 小写字母/连字符）") },
                        singleLine = true,
                        enabled = !isBusy,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    submitErr?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = { submitTarget = null }, enabled = !isBusy) { Text("取消") }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val version = managed.writeVersion ?: return@Button
                        val gen = identityGeneration
                        scope.launch {
                            isBusy = true
                            submitErr = null
                            val res = runCatching {
                                val identity = accounts.authorization(forceRefresh = false)
                                service.submit(managed.id, makePublic, shortName.trim(), version, identity)
                            }
                            isBusy = false
                            if (accounts.identityGeneration.value != gen) return@launch
                            res.fold(
                                onSuccess = {
                                    Toast.makeText(context, "已提交审核", Toast.LENGTH_SHORT).show()
                                    submitTarget = null
                                    loadApplications()
                                },
                                onFailure = { submitErr = PublishingError.message(it) },
                            )
                        }
                    },
                    enabled = !isBusy,
                ) {
                    Text(if (isBusy) "提交中…" else "提交审核")
                }
            },
        )
    }

    confirmDelist?.let { managed ->
        AlertDialog(
            onDismissRequest = { if (!isBusy) confirmDelist = null },
            title = { Text("下架「${managed.application.name}」？") },
            text = { Text("下架后公开工坊将不再展示此应用，你仍可在创作列表查看或重新投稿。") },
            dismissButton = {
                TextButton(onClick = { confirmDelist = null }, enabled = !isBusy) { Text("取消") }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val version = managed.writeVersion ?: return@Button
                        val gen = identityGeneration
                        scope.launch {
                            isBusy = true
                            errorMessage = null
                            val res = runCatching {
                                val identity = accounts.authorization(forceRefresh = false)
                                service.delist(managed.id, version, identity)
                            }
                            isBusy = false
                            if (accounts.identityGeneration.value != gen) return@launch
                            confirmDelist = null
                            res.fold(
                                onSuccess = { loadApplications() },
                                onFailure = { errorMessage = PublishingError.message(it) },
                            )
                        }
                    },
                    enabled = !isBusy,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("确认下架")
                }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun ApplicationEditorSheet(
    existing: ManagedApplication?,
    accounts: AccountStore,
    service: PublishingServing,
    draftVault: ApplicationDraftVault,
    onSaved: (ManagedApplication) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val ownerUid = accounts.user?.id
    val scope = rememberCoroutineScope()

    var draft by remember(existing?.id) {
        mutableStateOf(existing?.draft ?: ApplicationDraft())
    }
    var activeWriteVersion by remember(existing?.id) {
        mutableStateOf(existing?.writeVersion)
    }
    var rebaseConflict by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var isUploadingIcon by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(ownerUid, existing?.id) {
        val uid = ownerUid ?: return@LaunchedEffect
        val saved = runCatching { draftVault.load(uid, existing?.id) }.getOrNull() ?: return@LaunchedEffect
        val hasServerVersionConflict = saved.baseWriteVersion != null &&
            existing?.writeVersion != null &&
            saved.baseWriteVersion != existing.writeVersion
        draft = saved.draft
        rebaseConflict = hasServerVersionConflict
    }

    fun persistLocalDraft(nextDraft: ApplicationDraft) {
        draft = nextDraft
        val uid = ownerUid ?: return
        runCatching {
            draftVault.save(
                SavedApplicationDraft(
                    draft = nextDraft,
                    baseRevision = existing?.revisionId,
                    baseUpdatedAtMillis = existing?.updatedAtMillis,
                    baseWriteVersion = activeWriteVersion,
                ),
                owner = uid,
                appId = existing?.id,
            )
        }
    }

    val iconPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null || ownerUid == null) return@rememberLauncherForActivityResult
        val gen = identityGeneration
        scope.launch {
            isUploadingIcon = true
            errorMessage = null
            val res = runCatching {
                val pngBytes = ApplicationIconNormalizer.normalizeBitmapToPng1024(context, uri)
                val identity = accounts.authorization(forceRefresh = false)
                service.upload(pngBytes, ApplicationIconRole.APP_ICON, identity)
            }
            isUploadingIcon = false
            if (accounts.identityGeneration.value != gen) return@launch
            res.fold(
                onSuccess = { fileId ->
                    persistLocalDraft(draft.copy(appIconSrc = fileId))
                    Toast.makeText(context, "图标上传成功", Toast.LENGTH_SHORT).show()
                },
                onFailure = { errorMessage = PublishingError.message(it) },
            )
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!isSaving && !isUploadingIcon) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = if (existing == null) "新建云应用" else "编辑「${existing.application.name}」",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            if (rebaseConflict && existing != null) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "检测到远端版本已更新，本机草稿基于较旧版本。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(
                                onClick = {
                                    activeWriteVersion = existing.writeVersion
                                    rebaseConflict = false
                                    persistLocalDraft(draft)
                                },
                            ) {
                                Text("保留本地并同步版本")
                            }
                            TextButton(
                                onClick = {
                                    activeWriteVersion = existing.writeVersion
                                    draft = existing.draft
                                    rebaseConflict = false
                                    ownerUid?.let { runCatching { draftVault.remove(it, existing.id) } }
                                },
                            ) {
                                Text("采用远端版本")
                            }
                        }
                    }
                }
            }

            OutlinedTextField(
                value = draft.name,
                onValueChange = { persistLocalDraft(draft.copy(name = it)) },
                label = { Text("应用名称（1–50 字）") },
                singleLine = true,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.slug,
                onValueChange = { persistLocalDraft(draft.copy(slug = it.lowercase())) },
                label = { Text("应用标识 slug（小写字母/数字/连字符）") },
                singleLine = true,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.websiteUrl,
                onValueChange = { persistLocalDraft(draft.copy(websiteUrl = it)) },
                label = { Text("应用网址 (HTTPS)") },
                singleLine = true,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.privacyPolicyUrl,
                onValueChange = { persistLocalDraft(draft.copy(privacyPolicyUrl = it)) },
                label = { Text("隐私政策网址 (HTTPS)") },
                singleLine = true,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.supportUrl,
                onValueChange = { persistLocalDraft(draft.copy(supportUrl = it)) },
                label = { Text("支持网址 (HTTPS)") },
                singleLine = true,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.description,
                onValueChange = { persistLocalDraft(draft.copy(description = it)) },
                label = { Text("应用简介（最多 300 字）") },
                minLines = 2,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = draft.emoji,
                    onValueChange = { persistLocalDraft(draft.copy(emoji = it)) },
                    label = { Text("图标 Emoji") },
                    singleLine = true,
                    enabled = !isSaving,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = draft.themeColor,
                    onValueChange = { persistLocalDraft(draft.copy(themeColor = it)) },
                    label = { Text("主题色 #RRGGBB") },
                    singleLine = true,
                    enabled = !isSaving,
                    modifier = Modifier.weight(1f),
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (draft.appIconSrc.isNotBlank()) "已设置云图标资源" else "可选上传 1024×1024 应用图标",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                OutlinedButton(
                    onClick = { iconPicker.launch("image/*") },
                    enabled = !isSaving && !isUploadingIcon,
                ) {
                    Text(if (isUploadingIcon) "上传中…" else "选择图片上传")
                }
            }

            Text("可见范围", style = MaterialTheme.typography.labelLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ApplicationAudience.entries.forEach { aud ->
                    FilterChip(
                        selected = draft.audience == aud,
                        onClick = { persistLocalDraft(draft.copy(audience = aud)) },
                        label = { Text(aud.label) },
                    )
                }
            }

            Text("访问方式", style = MaterialTheme.typography.labelLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ApplicationAccessMode.entries.forEach { mode ->
                    FilterChip(
                        selected = draft.accessMode == mode,
                        onClick = { persistLocalDraft(draft.copy(accessMode = mode)) },
                        label = { Text(mode.label) },
                    )
                }
            }

            Text("发布阶段", style = MaterialTheme.typography.labelLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ApplicationReleaseStage.entries.forEach { stage ->
                    FilterChip(
                        selected = draft.releaseStage == stage,
                        onClick = { persistLocalDraft(draft.copy(releaseStage = stage)) },
                        label = { Text(stage.label) },
                    )
                }
            }

            draft.validationIssue?.let { issue ->
                Text(issue, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            errorMessage?.let { msg ->
                Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    enabled = !isSaving && !isUploadingIcon,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("取消")
                }
                Button(
                    onClick = {
                        val gen = identityGeneration
                        scope.launch {
                            isSaving = true
                            errorMessage = null
                            val res = runCatching {
                                val identity = accounts.authorization(forceRefresh = false)
                                service.save(
                                    id = existing?.id,
                                    draft = draft,
                                    writeVersion = activeWriteVersion,
                                    identity = identity,
                                )
                            }
                            isSaving = false
                            if (accounts.identityGeneration.value != gen) return@launch
                            res.fold(
                                onSuccess = { savedApp ->
                                    ownerUid?.let { runCatching { draftVault.remove(it, existing?.id) } }
                                    Toast.makeText(context, "已保存应用版本", Toast.LENGTH_SHORT).show()
                                    onSaved(savedApp)
                                },
                                onFailure = { errorMessage = PublishingError.message(it) },
                            )
                        }
                    },
                    enabled = !isSaving && !isUploadingIcon && draft.isValid,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (isSaving) "保存中…" else "保存")
                }
            }
        }
    }
}
