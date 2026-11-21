package `fun`.yunle.apps.ui.catalog

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.BoundedHttpsImageLoader
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.catalog.ApplicationAcquisitionError
import `fun`.yunle.apps.catalog.ApplicationAcquisitionException
import `fun`.yunle.apps.catalog.ApplicationAcquisitionQuote
import `fun`.yunle.apps.catalog.ApplicationAcquisitionServing
import `fun`.yunle.apps.catalog.ApplicationAcquisitionState
import `fun`.yunle.apps.catalog.ApplicationShareAppearance
import `fun`.yunle.apps.catalog.ApplicationShareCardRenderer
import `fun`.yunle.apps.catalog.ApplicationShareExportDirectory
import `fun`.yunle.apps.catalog.ApplicationShareExporter
import `fun`.yunle.apps.catalog.DeveloperProfile
import `fun`.yunle.apps.catalog.DeveloperProfileError
import `fun`.yunle.apps.catalog.DeveloperProfileServing
import `fun`.yunle.apps.catalog.PersonalMarketLaunchAuthorization
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.OutputStream

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DeveloperApplicationsSheet(
    login: String,
    service: DeveloperProfileServing,
    onLaunchApp: (CatalogApp) -> Unit,
    onSelectAppDetail: (CatalogApp) -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var profile by remember(login) { mutableStateOf<DeveloperProfile?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var launchingId by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    suspend fun loadProfile() {
        isLoading = true
        errorMessage = null
        val outcome = runCatching { service.profile(login) }
        isLoading = false
        outcome.fold(
            onSuccess = { profile = it },
            onFailure = { errorMessage = DeveloperProfileError.message(it) },
        )
    }

    LaunchedEffect(login) {
        loadProfile()
    }

    ModalBottomSheet(onDismissRequest = { if (launchingId == null) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "@$login 的公开应用",
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
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(msg, style = MaterialTheme.typography.bodyMedium)
                        OutlinedButton(
                            onClick = { scope.launch { loadProfile() } },
                            enabled = launchingId == null,
                        ) {
                            Text("重试")
                        }
                    }
                }
            }

            if (isLoading && profile == null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            profile?.let { loaded ->
                Text(
                    text = "共 ${loaded.items.size} 个公开作品",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (loaded.items.isEmpty()) {
                    Text(
                        text = "该开发者暂未公开应用。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    loaded.items.forEach { app ->
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
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                AppIconBadge(app = app, size = 48.dp)
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(
                                        text = app.name,
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        text = app.description.ifBlank { app.browseCategory },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    TextButton(
                                        onClick = {
                                            onDismiss()
                                            onSelectAppDetail(app)
                                        },
                                        enabled = launchingId == null,
                                    ) {
                                        Text("详情")
                                    }
                                    if (app.launchUrl != null) {
                                        FilledTonalButton(
                                            onClick = {
                                                scope.launch {
                                                    launchingId = app.id
                                                    errorMessage = null
                                                    val res = runCatching {
                                                        PersonalMarketLaunchAuthorization.resolve(app, service)
                                                    }
                                                    launchingId = null
                                                    res.fold(
                                                        onSuccess = { authorized ->
                                                            onDismiss()
                                                            onLaunchApp(authorized)
                                                        },
                                                        onFailure = { err ->
                                                            errorMessage = DeveloperProfileError.message(err)
                                                        },
                                                    )
                                                }
                                            },
                                            enabled = launchingId == null,
                                        ) {
                                            Text(if (launchingId == app.id) "校验中" else "打开")
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
internal fun ApplicationAcquisitionSheet(
    app: CatalogApp,
    accounts: AccountStore,
    service: ApplicationAcquisitionServing,
    onLaunchAuthorized: (CatalogApp) -> Unit,
    onNavigateToMe: () -> Unit,
    onOpenWallet: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var quote by remember(app.id) { mutableStateOf<ApplicationAcquisitionQuote?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var isPurchasing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    suspend fun checkEntitlement() {
        val activeUser = accounts.user?.takeIf { it.isUsable } ?: return
        val gen = identityGeneration
        isLoading = true
        errorMessage = null
        val outcome = runCatching {
            val identity = accounts.authorization(forceRefresh = false)
            service.check(app.id, identity)
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return
        outcome.fold(
            onSuccess = { quote = it },
            onFailure = { errorMessage = ApplicationAcquisitionError.message(it) },
        )
    }

    LaunchedEffect(app.id, overview.activeID, identityGeneration) {
        quote = null
        checkEntitlement()
    }

    ModalBottomSheet(onDismissRequest = { if (!isPurchasing) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                AppIconBadge(app = app, size = 52.dp)
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = app.name,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = "应用访问权益与解锁",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (overview.activeUser?.isUsable != true) {
                Text(
                    text = "请先登录云乐坊账号，再核对会员、兑换或购买访问权益。",
                    style = MaterialTheme.typography.bodyMedium,
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
                        Text(msg, style = MaterialTheme.typography.bodyMedium)
                        OutlinedButton(
                            onClick = { scope.launch { checkEntitlement() } },
                            enabled = !isPurchasing,
                        ) {
                            Text("重新核对")
                        }
                    }
                }
            }

            if (isLoading && quote == null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 20.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            quote?.let { current ->
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
                        when (current.state) {
                            ApplicationAcquisitionState.ALLOWED -> {
                                val reasonText = when (current.reason) {
                                    "member" -> "当前账号享有有效云乐坊会员权益。"
                                    "purchased" -> "你已拥有该应用的使用权限。"
                                    else -> "该应用当前可直接访问。"
                                }
                                Text(
                                    text = "已解锁 · 可立即使用",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(reasonText, style = MaterialTheme.typography.bodyMedium)
                                Button(
                                    onClick = {
                                        onDismiss()
                                        onLaunchAuthorized(current.application)
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text("立即启动")
                                }
                            }

                            ApplicationAcquisitionState.MEMBERSHIP_REQUIRED -> {
                                Text(
                                    text = "需要云乐坊会员",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    text = "该应用仅对云乐坊有效会员开放。前往钱包查看会员权益后可立即启动。",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Button(
                                    onClick = {
                                        onDismiss()
                                        onOpenWallet()
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text("查看会员权益")
                                }
                            }

                            ApplicationAcquisitionState.PURCHASE_REQUIRED -> {
                                Text(
                                    text = "使用云币解锁",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    text = "需要支付 ${current.coinCost} 云币（当前余额 ${current.balance} 云币）。",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                if (current.balance < current.coinCost) {
                                    Text(
                                        text = "当前云币余额不足，请先前往钱包充值。",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                    Button(
                                        onClick = {
                                            onDismiss()
                                            onOpenWallet()
                                        },
                                        modifier = Modifier.fillMaxWidth(),
                                    ) {
                                        Text("前往钱包充值")
                                    }
                                } else {
                                    Button(
                                        onClick = {
                                            val gen = identityGeneration
                                            scope.launch {
                                                isPurchasing = true
                                                errorMessage = null
                                                val res = runCatching {
                                                    val identity = accounts.authorization(forceRefresh = false)
                                                    service.purchase(app.id, current.coinCost, identity)
                                                }
                                                isPurchasing = false
                                                if (accounts.identityGeneration.value != gen) return@launch
                                                res.fold(
                                                    onSuccess = { purchased ->
                                                        quote = purchased
                                                        Toast.makeText(context, "解锁成功", Toast.LENGTH_SHORT).show()
                                                    },
                                                    onFailure = { err ->
                                                        errorMessage = ApplicationAcquisitionError.message(err)
                                                        if (err is ApplicationAcquisitionException &&
                                                            err.error == ApplicationAcquisitionError.PRICE_CHANGED
                                                        ) {
                                                            checkEntitlement()
                                                        }
                                                    },
                                                )
                                            }
                                        },
                                        enabled = !isPurchasing,
                                        modifier = Modifier.fillMaxWidth(),
                                    ) {
                                        Text(if (isPurchasing) "正在兑换…" else "支付 ${current.coinCost} 云币解锁")
                                    }
                                }
                            }

                            ApplicationAcquisitionState.INVITATION_REQUIRED -> {
                                Text(
                                    text = "需要受邀访问",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    text = "该应用当前设为受邀或限定访客使用，请联系作者或加入对应的个人工坊。",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
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
internal fun ApplicationShareSheet(app: CatalogApp, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val shareUrl = remember(app) { ApplicationShareExporter.publicUrlOrNull(app) }
    var appearance by remember(app.key) { mutableStateOf(ApplicationShareAppearance.LIGHT) }
    var preview by remember(app, appearance) { mutableStateOf<Bitmap?>(null) }
    var previewError by remember(app, appearance) { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var pendingPoster by remember { mutableStateOf<Bitmap?>(null) }
    val savePng = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/png")) { uri ->
        val poster = pendingPoster
        pendingPoster = null
        if (uri != null && poster != null) {
            busy = true
            scope.launch {
                try {
                    withShareFeedback(context) {
                        writeShareDocument(context, uri) { it.write(ApplicationShareCardRenderer.pngBytes(poster)) }
                        Toast.makeText(context, "海报已保存", Toast.LENGTH_SHORT).show()
                    }
                } finally {
                    busy = false
                }
            }
        }
    }

    LaunchedEffect(app, appearance) {
        try {
            ApplicationShareExporter.requirePosterUrl(app)
            val icon = ApplicationShareExporter.loadIcon(app) { BoundedHttpsImageLoader.loadBitmap(it.logo) }
            preview = withContext(Dispatchers.Default) { ApplicationShareCardRenderer.render(app, appearance, icon) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            previewError = error.localizedMessage ?: "无法生成海报预览。"
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
            Text("分享应用海报", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (option in ApplicationShareAppearance.entries) {
                    FilterChip(
                        selected = appearance == option,
                        onClick = { appearance = option },
                        enabled = !busy,
                        label = { Text(option.label) },
                    )
                }
            }

            val poster = preview
            val error = previewError
            when {
                poster != null -> Image(
                    bitmap = poster.asImageBitmap(),
                    contentDescription = "${app.name} · ${appearance.label}二维码海报",
                    modifier = Modifier.fillMaxWidth().height(320.dp),
                    contentScale = ContentScale.Fit,
                )
                error != null -> Text(error, color = MaterialTheme.colorScheme.error)
                else -> CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedButton(
                    enabled = shareUrl != null,
                    onClick = {
                        if (shareUrl != null) {
                            context.getSystemService(ClipboardManager::class.java)
                                ?.setPrimaryClip(ClipData.newPlainText(app.name, shareUrl))
                            Toast.makeText(context, "链接已复制", Toast.LENGTH_SHORT).show()
                        }
                    },
                ) { Text("复制链接") }
                OutlinedButton(
                    enabled = poster != null && !busy,
                    onClick = {
                        if (poster == null) return@OutlinedButton
                        val filename = ApplicationShareExporter.posterFilename(app, appearance)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            busy = true
                            scope.launch {
                                try {
                                    withShareFeedback(context) {
                                        val bytes = withContext(Dispatchers.Default) {
                                            ApplicationShareCardRenderer.pngBytes(poster)
                                        }
                                        ApplicationShareExporter.savePngToGallery(context, bytes, filename)
                                        Toast.makeText(context, "海报已保存至相册", Toast.LENGTH_SHORT).show()
                                    }
                                } finally {
                                    busy = false
                                }
                            }
                        } else {
                            pendingPoster = poster
                            scope.launch { withShareFeedback(context) { savePng.launch(filename) } }
                        }
                    },
                ) { Text("保存海报") }
                Button(
                    enabled = poster != null && !busy,
                    onClick = {
                        val selectedAppearance = appearance
                        busy = true
                        scope.launch {
                            try {
                                withShareFeedback(context) {
                                    val file = ApplicationShareExporter.exportSinglePng(context, app, selectedAppearance)
                                    shareExport(context, file, "image/png", "分享 ${app.name}")
                                }
                            } finally {
                                busy = false
                            }
                        }
                    },
                ) { Text("分享海报") }
            }
        }
    }
}

private data class ShareExportProgress(val completed: Int, val total: Int, val name: String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ApplicationShareCatalogSheet(apps: List<CatalogApp>, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val exporter = remember(context) { ApplicationShareExporter(context.cacheDir) }
    val publicApps = remember(apps) {
        apps.filter { ApplicationShareExporter.publicUrlOrNull(it) != null }.distinctBy(CatalogApp::key)
    }
    var selectedKeys by remember { mutableStateOf(emptySet<String>()) }
    val selectedApps = publicApps.filter { it.key in selectedKeys }
    var appearances by remember { mutableStateOf(setOf(ApplicationShareAppearance.LIGHT)) }
    var exportJob by remember { mutableStateOf<Job?>(null) }
    var savingZip by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    val exportState = remember { mutableStateOf<ApplicationShareExportDirectory?>(null) }
    var exported by exportState
    val progressState = remember { MutableStateFlow<ShareExportProgress?>(null) }
    val progress by progressState.collectAsStateWithLifecycle()
    val saveZip = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        val file = exported?.zipFile
        if (uri != null && file != null) {
            savingZip = true
            scope.launch {
                try {
                    withShareFeedback(context) {
                        writeShareDocument(context, uri) { output -> file.inputStream().use { it.copyTo(output) } }
                        Toast.makeText(context, "ZIP 已保存", Toast.LENGTH_SHORT).show()
                    }
                } finally {
                    savingZip = false
                }
            }
        }
    }
    DisposableEffect(Unit) {
        onDispose { exportState.value?.discard() }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(0.86f).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("批量分享海报", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            notice?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            val result = exported
            when {
                exportJob != null -> {
                    val current = progress
                    if (current == null) {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    } else {
                        LinearProgressIndicator(
                            progress = { current.completed.toFloat() / current.total },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(if (current.completed == current.total) "正在打包 ZIP…" else {
                            "已处理 ${current.completed} / ${current.total} · ${current.name}"
                        })
                    }
                    OutlinedButton(onClick = { exportJob?.cancel() }) { Text("取消") }
                }
                result != null -> {
                    Text("已导出 ${result.manifest.cards.size} 张海报", style = MaterialTheme.typography.titleMedium)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (result.manifest.cards.isNotEmpty()) {
                            Button(onClick = {
                                scope.launch {
                                    withShareFeedback(context) {
                                        shareExport(context, result.zipFile, "application/zip", "分享导出包 (ZIP)")
                                    }
                                }
                            }) { Text("分享导出包 (ZIP)") }
                            OutlinedButton(
                                enabled = !savingZip,
                                onClick = {
                                    scope.launch {
                                        withShareFeedback(context) { saveZip.launch(ApplicationShareExporter.ZIP_FILENAME) }
                                    }
                                },
                            ) { Text("保存 ZIP") }
                        }
                        TextButton(
                            enabled = !savingZip,
                            onClick = {
                                result.discard()
                                exported = null
                            },
                        ) { Text("重新选择") }
                    }
                    if (result.manifest.failures.isNotEmpty()) {
                        Text("导出失败 · ${result.manifest.failures.size} 个应用", style = MaterialTheme.typography.titleSmall)
                        LazyColumn(
                            contentPadding = PaddingValues(bottom = 24.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(result.manifest.failures, key = { it.slug }) { failure ->
                                Text("${failure.slug}：${failure.message}", style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
                else -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (appearance in ApplicationShareAppearance.entries) {
                            FilterChip(
                                selected = appearance in appearances,
                                onClick = {
                                    appearances = if (appearance in appearances) appearances - appearance else appearances + appearance
                                },
                                label = { Text(appearance.label) },
                            )
                        }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Button(
                            enabled = selectedApps.isNotEmpty() && appearances.isNotEmpty(),
                            onClick = {
                                val requestedAppearances = appearances.toList()
                                notice = null
                                progressState.value = null
                                exportJob = scope.launch {
                                    try {
                                        exported = exporter.exportDirectory(
                                            apps = selectedApps,
                                            appearances = requestedAppearances,
                                            progress = { done, total, name ->
                                                progressState.value = ShareExportProgress(done, total, name)
                                            },
                                            iconLoader = { BoundedHttpsImageLoader.loadBitmap(it.logo) },
                                        )
                                    } catch (error: CancellationException) {
                                        notice = "已取消导出。"
                                        throw error
                                    } catch (error: Exception) {
                                        notice = error.localizedMessage ?: "无法导出海报。"
                                    } finally {
                                        exportJob = null
                                    }
                                }
                            },
                        ) { Text("导出海报") }
                        TextButton(
                            enabled = publicApps.isNotEmpty(),
                            onClick = {
                                selectedKeys = if (selectedApps.size == publicApps.size) emptySet()
                                else publicApps.mapTo(mutableSetOf(), CatalogApp::key)
                            },
                        ) { Text(if (publicApps.isNotEmpty() && selectedApps.size == publicApps.size) "清空选择" else "全选公开应用") }
                    }
                    if (publicApps.isEmpty()) {
                        Text("当前没有可分享的公开应用。")
                    } else {
                        Text("已选 ${selectedApps.size} / ${publicApps.size} 个应用", style = MaterialTheme.typography.labelLarge)
                        LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                            items(publicApps, key = CatalogApp::key) { app ->
                                val checked = app.key in selectedKeys
                                Row(
                                    modifier = Modifier.fillMaxWidth().toggleable(checked, role = Role.Checkbox) {
                                        selectedKeys = if (it) selectedKeys + app.key else selectedKeys - app.key
                                    }.padding(vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Checkbox(checked = checked, onCheckedChange = null)
                                    Text(app.name, style = MaterialTheme.typography.bodyLarge)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun shareExport(context: Context, file: File, mimeType: String, title: String) {
    val uri = ApplicationShareExporter.uriFor(context, file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newRawUri(file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, title))
}

private suspend fun writeShareDocument(context: Context, uri: Uri, write: (OutputStream) -> Unit) {
    withContext(Dispatchers.IO) {
        checkNotNull(context.contentResolver.openOutputStream(uri, "wt")) { "无法打开保存位置。" }.use(write)
    }
}

private suspend fun withShareFeedback(context: Context, action: suspend () -> Unit) {
    try {
        action()
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        Toast.makeText(context, error.localizedMessage ?: "无法完成分享或保存。", Toast.LENGTH_SHORT).show()
    }
}
