package `fun`.yunle.apps.ui.support

import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.diagnostics.DiagnosticClientContext
import `fun`.yunle.apps.diagnostics.DiagnosticLogEntry
import `fun`.yunle.apps.diagnostics.DiagnosticLogLevel
import `fun`.yunle.apps.diagnostics.DiagnosticLogStore
import `fun`.yunle.apps.diagnostics.DiagnosticUploadConfirmation
import `fun`.yunle.apps.diagnostics.DiagnosticUploadRules
import `fun`.yunle.apps.diagnostics.DiagnosticUploadStore
import `fun`.yunle.apps.support.FeedbackScreenshot
import `fun`.yunle.apps.support.FeedbackScreenshotNormalizer
import `fun`.yunle.apps.support.SharedFeedbackHistoryStore
import `fun`.yunle.apps.support.SharedFeedbackRecord
import `fun`.yunle.apps.support.SupportBoardItem
import `fun`.yunle.apps.support.SupportCategory
import `fun`.yunle.apps.support.SupportCenterController
import `fun`.yunle.apps.support.SupportCenterError
import `fun`.yunle.apps.support.SupportCenterException
import `fun`.yunle.apps.support.SupportCenterServing
import `fun`.yunle.apps.support.SupportDestination
import `fun`.yunle.apps.support.SupportFeedbackReceipt
import `fun`.yunle.apps.support.SupportFeedbackSubmission
import `fun`.yunle.apps.support.SupportHttpCookie
import `fun`.yunle.apps.support.SupportPrivateItem
import `fun`.yunle.apps.support.SupportProduct
import `fun`.yunle.apps.support.SupportTicketScreenshot
import `fun`.yunle.apps.support.SupportTicketServing
import `fun`.yunle.apps.support.SupportTicketSnapshot
import `fun`.yunle.apps.support.SupportUrlRules
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

private data class TicketViewerTarget(
    val receipt: SupportFeedbackReceipt,
    val cookies: List<SupportHttpCookie>,
    val externalUrl: String? = null,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SupportCenterSheet(
    accounts: AccountStore,
    supportService: SupportCenterServing,
    ticketService: SupportTicketServing,
    shareHistory: SharedFeedbackHistoryStore,
    appVersionName: String,
    initialDestination: SupportDestination = SupportDestination.COMPOSE,
    initialProduct: String = "www",
    initialScreenshots: List<FeedbackScreenshot> = emptyList(),
    onOpenUrl: (String) -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val shareRecords by shareHistory.records.collectAsStateWithLifecycle()

    val controller = remember(accounts, supportService) {
        SupportCenterController(accounts = accounts, service = supportService, scope = scope)
    }
    DisposableEffect(controller) {
        onDispose { controller.close() }
    }

    val board by controller.board.collectAsStateWithLifecycle()
    val boardCursor by controller.boardCursor.collectAsStateWithLifecycle()
    val dashboard by controller.dashboard.collectAsStateWithLifecycle()
    val receipt by controller.receipt.collectAsStateWithLifecycle()
    val connected by controller.connected.collectAsStateWithLifecycle()
    val isLoading by controller.isLoading.collectAsStateWithLifecycle()
    val isSubmitting by controller.isSubmitting.collectAsStateWithLifecycle()
    val error by controller.error.collectAsStateWithLifecycle()
    val needsConsent by controller.needsConsent.collectAsStateWithLifecycle()

    var destination by rememberSaveable { mutableStateOf(initialDestination) }
    var product by rememberSaveable {
        mutableStateOf(if (initialProduct in SupportProduct.submissionIDs) initialProduct else "www")
    }
    var category by rememberSaveable { mutableStateOf("problem") }
    var description by rememberSaveable { mutableStateOf("") }
    var manageProduct by rememberSaveable { mutableStateOf<String?>(null) }
    var screenshots by remember { mutableStateOf(initialScreenshots) }
    var screenshotError by remember { mutableStateOf<String?>(null) }
    var importingImages by remember { mutableStateOf(false) }
    var activeTicket by remember { mutableStateOf<TicketViewerTarget?>(null) }

    val imagePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(FeedbackScreenshot.MAXIMUM_COUNT),
    ) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        val remaining = FeedbackScreenshot.MAXIMUM_COUNT - screenshots.size
        if (remaining <= 0) {
            screenshotError = SupportCenterError.INVALID_SCREENSHOT.defaultMessage
            return@rememberLauncherForActivityResult
        }
        val selected = uris.take(remaining)
        importingImages = true
        screenshotError = null
        scope.launch {
            val loaded = withContext(Dispatchers.IO) {
                selected.map { uri ->
                    runCatching {
                        val raw = readUriBytesLimited(context, uri, FeedbackScreenshot.MAXIMUM_INPUT_BYTES)
                            ?: throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
                        FeedbackScreenshotNormalizer.prepare(raw)
                    }
                }
            }
            val parsed = mutableListOf<FeedbackScreenshot>()
            var failureMessage: String? = null
            for (item in loaded) {
                item.fold(
                    onSuccess = { parsed.add(it) },
                    onFailure = { err ->
                        failureMessage = (err as? SupportCenterException)?.message
                            ?: SupportCenterError.INVALID_SCREENSHOT.defaultMessage
                    },
                )
            }
            if (parsed.isNotEmpty()) {
                screenshots = (screenshots + parsed).take(FeedbackScreenshot.MAXIMUM_COUNT)
            }
            screenshotError = failureMessage
            importingImages = false
        }
    }

    var lastActiveAccountId by remember { mutableStateOf(overview.activeID) }
    LaunchedEffect(overview.activeID, destination, manageProduct) {
        if (lastActiveAccountId != overview.activeID) {
            lastActiveAccountId = overview.activeID
            controller.identityChanged()
        }
        controller.load(destination = destination, product = manageProduct)
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "支持中心",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { onOpenUrl("https://support.yunle.fun") }) {
                        Text("网页版")
                    }
                    TextButton(onClick = onDismiss) {
                        Text("关闭")
                    }
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (tab in SupportDestination.entries) {
                    FilterChip(
                        selected = destination == tab,
                        onClick = { destination = tab },
                        label = { Text(tab.title) },
                    )
                }
            }

            if (needsConsent) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "需要授权支持中心读取当前云乐坊账号身份，以提交账号工单或查看历史记录。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Button(
                            onClick = {
                                scope.launch {
                                    controller.load(
                                        destination = destination,
                                        product = manageProduct,
                                        consent = true,
                                    )
                                }
                            },
                        ) {
                            Text("授权并连接")
                        }
                    }
                }
            } else if (!error.isNullOrBlank()) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.errorContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            text = error.orEmpty(),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(
                            onClick = {
                                scope.launch {
                                    controller.load(destination = destination, product = manageProduct)
                                }
                            },
                        ) {
                            Text("重试")
                        }
                    }
                }
            }

            when (destination) {
                SupportDestination.COMPOSE -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 480.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        val currentReceipt = receipt
                        if (currentReceipt != null) {
                            Surface(
                                shape = RoundedCornerShape(14.dp),
                                color = MaterialTheme.colorScheme.primaryContainer,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(
                                    modifier = Modifier.padding(14.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Text(
                                        text = "反馈已受理",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                                    )
                                    Text(
                                        text = "产品：${SupportProduct.title(currentReceipt.productId)}",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                    if (!currentReceipt.ticketId.isNullOrBlank()) {
                                        Text(
                                            text = "工单编号：${currentReceipt.ticketId}",
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                    }
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        if (!currentReceipt.ticketId.isNullOrBlank()) {
                                            Button(
                                                onClick = {
                                                    val sessionCookies = if (connected?.userID != null) {
                                                        connected?.cookies.orEmpty()
                                                    } else {
                                                        emptyList()
                                                    }
                                                    activeTicket = TicketViewerTarget(
                                                        receipt = currentReceipt,
                                                        cookies = sessionCookies,
                                                        externalUrl = currentReceipt.ticketUrl,
                                                    )
                                                },
                                            ) {
                                                Text("查看工单")
                                            }
                                        }
                                        OutlinedButton(
                                            onClick = {
                                                description = ""
                                                screenshots = emptyList()
                                                controller.clearReceipt()
                                            },
                                        ) {
                                            Text("继续反馈")
                                        }
                                    }
                                }
                            }
                        } else {
                            Text(
                                text = if (overview.activeUser != null) {
                                    "当前已以账号「${overview.activeUser?.displayName}」连接支持中心"
                                } else {
                                    "当前以访客身份提交反馈（仅本机保留访客工单回执）"
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )

                            Text(
                                text = "所属产品",
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Medium,
                            )
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                for (id in SupportProduct.submissionIDs) {
                                    FilterChip(
                                        selected = product == id,
                                        onClick = { product = id },
                                        label = { Text(SupportProduct.title(id)) },
                                    )
                                }
                            }

                            Text(
                                text = "反馈类型",
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Medium,
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for ((key, label) in SupportCategory.options) {
                                    FilterChip(
                                        selected = category == key,
                                        onClick = { category = key },
                                        label = { Text(label) },
                                    )
                                }
                            }

                            OutlinedTextField(
                                value = description,
                                onValueChange = { if (it.length <= 4000) description = it },
                                label = { Text("问题描述或建议（5 - 4000 字）") },
                                minLines = 4,
                                maxLines = 7,
                                modifier = Modifier.fillMaxWidth(),
                                supportingText = {
                                    Text("${description.trim().length} / 4000")
                                },
                            )

                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = "附件截图（${screenshots.size}/${FeedbackScreenshot.MAXIMUM_COUNT}）",
                                        style = MaterialTheme.typography.labelLarge,
                                    )
                                    if (screenshots.size < FeedbackScreenshot.MAXIMUM_COUNT) {
                                        FilledTonalButton(
                                            enabled = !importingImages && !isSubmitting,
                                            onClick = {
                                                imagePicker.launch(
                                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                                                )
                                            },
                                        ) {
                                            Text(if (importingImages) "处理中…" else "添加截图")
                                        }
                                    }
                                }
                                if (!screenshotError.isNullOrBlank()) {
                                    Text(
                                        text = screenshotError.orEmpty(),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                }
                                if (screenshots.isNotEmpty()) {
                                    ScreenshotStrip(
                                        screenshots = screenshots,
                                        enabled = !isSubmitting,
                                        onRemove = { id ->
                                            screenshots = screenshots.filterNot { it.id == id }
                                        },
                                    )
                                }
                            }

                            val trimmedLen = description.trim().length
                            val canSubmit = connected != null && !isLoading && !isSubmitting && trimmedLen in 5..4000
                            Button(
                                enabled = canSubmit,
                                onClick = {
                                    scope.launch {
                                        controller.submit(
                                            product = product,
                                            category = category,
                                            description = description,
                                            screenshots = screenshots,
                                            context = SupportFeedbackSubmission.Context(
                                                source = "apps-android",
                                                version = appVersionName,
                                            ),
                                        )
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(
                                    when {
                                        isSubmitting -> "正在提交…"
                                        isLoading -> "正在连接支持中心…"
                                        else -> "提交反馈"
                                    },
                                )
                            }
                        }
                    }
                }

                SupportDestination.BOARD -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 200.dp, max = 460.dp),
                    ) {
                        if (isLoading && board.isEmpty()) {
                            Box(
                                modifier = Modifier.fillMaxWidth().padding(32.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator()
                            }
                        } else if (board.isEmpty()) {
                            Text(
                                text = "暂时没有公开的需求墙内容。",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(vertical = 20.dp),
                            )
                        } else {
                            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                items(board, key = { it.id }) { item ->
                                    SupportBoardCard(item)
                                }
                                if (boardCursor != null) {
                                    item(key = "board_more") {
                                        OutlinedButton(
                                            enabled = !isLoading,
                                            onClick = {
                                                scope.launch {
                                                    controller.load(destination = SupportDestination.BOARD, more = true)
                                                }
                                            },
                                            modifier = Modifier.fillMaxWidth(),
                                        ) {
                                            Text(if (isLoading) "加载中…" else "加载更多")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SupportDestination.MANAGE -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 200.dp, max = 460.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (overview.activeUser == null) {
                            item(key = "manage_guest") {
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Column(
                                        modifier = Modifier.padding(14.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Text(
                                            text = "登录后可查看账号下的全部工单与进度",
                                            style = MaterialTheme.typography.bodyMedium,
                                        )
                                        FilledTonalButton(onClick = onNavigateToMe) {
                                            Text("前往登录")
                                        }
                                    }
                                }
                            }
                        } else {
                            val currentDash = dashboard
                            if (currentDash != null) {
                                item(key = "manage_filters") {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .horizontalScroll(rememberScrollState()),
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        FilterChip(
                                            selected = manageProduct == null,
                                            onClick = { manageProduct = null },
                                            label = { Text("默认产品") },
                                        )
                                        for (pid in currentDash.productIds) {
                                            FilterChip(
                                                selected = manageProduct == pid || (manageProduct == null && currentDash.productId == pid),
                                                onClick = { manageProduct = pid },
                                                label = { Text(SupportProduct.title(pid)) },
                                            )
                                        }
                                    }
                                }
                                if (currentDash.privateFeedback.items.isEmpty()) {
                                    item(key = "manage_empty") {
                                        Text(
                                            text = "${SupportProduct.title(currentDash.productId)} 暂无你提交的反馈记录。",
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                } else {
                                    items(currentDash.privateFeedback.items, key = { it.id }) { item ->
                                        SupportPrivateCard(
                                            item = item,
                                            onOpenTicket = { ticketId ->
                                                activeTicket = TicketViewerTarget(
                                                    receipt = SupportFeedbackReceipt(
                                                        id = item.id,
                                                        productId = item.productId,
                                                        ticketId = ticketId,
                                                        ticketUrl = null,
                                                    ),
                                                    cookies = connected?.cookies.orEmpty(),
                                                )
                                            },
                                        )
                                    }
                                    if (currentDash.privateFeedback.nextCursor != null) {
                                        item(key = "manage_more") {
                                            OutlinedButton(
                                                enabled = !isLoading,
                                                onClick = {
                                                    scope.launch {
                                                        controller.load(
                                                            destination = SupportDestination.MANAGE,
                                                            product = manageProduct,
                                                            more = true,
                                                        )
                                                    }
                                                },
                                                modifier = Modifier.fillMaxWidth(),
                                            ) {
                                                Text(if (isLoading) "加载中…" else "加载更多")
                                            }
                                        }
                                    }
                                }
                            } else if (isLoading) {
                                item(key = "manage_loading") {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        CircularProgressIndicator()
                                    }
                                }
                            }
                        }

                        if (shareRecords.isNotEmpty()) {
                            item(key = "share_history_header") {
                                HorizontalDivider(modifier = Modifier.padding(top = 6.dp))
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = "系统分享反馈记录（本机）",
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    TextButton(onClick = shareHistory::clear) {
                                        Text("清空")
                                    }
                                }
                            }
                            items(shareRecords, key = { "share_${it.id}" }) { record ->
                                ShareRecordCard(
                                    record = record,
                                    onOpenTicket = {
                                        activeTicket = TicketViewerTarget(
                                            receipt = record.receipt,
                                            cookies = emptyList(),
                                            externalUrl = record.receipt.ticketUrl,
                                        )
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    activeTicket?.let { target ->
        SupportTicketDialog(
            receipt = target.receipt,
            cookies = target.cookies,
            externalUrl = target.externalUrl,
            ticketService = ticketService,
            onOpenUrl = onOpenUrl,
            onDismiss = { activeTicket = null },
        )
    }
}

@Composable
internal fun SupportTicketDialog(
    receipt: SupportFeedbackReceipt,
    cookies: List<SupportHttpCookie>,
    externalUrl: String? = null,
    ticketService: SupportTicketServing,
    onOpenUrl: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var reloadTick by remember { mutableIntStateOf(0) }
    var snapshot by remember { mutableStateOf<SupportTicketSnapshot?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(receipt, reloadTick) {
        isLoading = true
        errorMessage = null
        runCatching { ticketService.load(receipt, cookies) }
            .onSuccess {
                snapshot = it
                isLoading = false
            }
            .onFailure {
                errorMessage = it.message ?: "暂时无法读取工单，请稍后重试。"
                isLoading = false
            }
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(18.dp),
            tonalElevation = 6.dp,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = snapshot?.detail?.ticket?.let { "工单 #${it.number}" } ?: "工单详情",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        val validWebUrl = externalUrl ?: receipt.ticketUrl
                        if (!validWebUrl.isNullOrBlank()) {
                            TextButton(onClick = { onOpenUrl(validWebUrl) }) {
                                Text("网页查看")
                            }
                        }
                        TextButton(onClick = onDismiss) {
                            Text("关闭")
                        }
                    }
                }

                when {
                    isLoading -> {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(28.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                    errorMessage != null -> {
                        Text(
                            text = errorMessage.orEmpty(),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                        )
                        FilledTonalButton(onClick = { reloadTick++ }) {
                            Text("重试")
                        }
                    }
                    snapshot != null -> {
                        val snap = snapshot!!
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(max = 420.dp)
                                .verticalScroll(rememberScrollState()),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = MaterialTheme.colorScheme.surfaceContainerLow,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(
                                    modifier = Modifier.padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Text(
                                        text = snap.detail.ticket.title,
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Text(
                                        text = "${SupportProduct.title(snap.detail.ticket.productId)} · ${snap.detail.ticket.statusTitle}",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                            }

                            if (snap.screenshots.isNotEmpty()) {
                                Text(
                                    text = "工单截图",
                                    style = MaterialTheme.typography.labelLarge,
                                )
                                Row(
                                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    for (shot in snap.screenshots) {
                                        TicketScreenshotThumb(
                                            item = shot,
                                            snapshot = snap,
                                            ticketService = ticketService,
                                        )
                                    }
                                }
                            }

                            for (msg in snap.detail.messages) {
                                val isTeam = msg.author == "team"
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = if (isTeam) {
                                        MaterialTheme.colorScheme.secondaryContainer
                                    } else {
                                        MaterialTheme.colorScheme.surfaceContainerLow
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Column(
                                        modifier = Modifier.padding(12.dp),
                                        verticalArrangement = Arrangement.spacedBy(4.dp),
                                    ) {
                                        Text(
                                            text = "${msg.authorTitle} · ${msg.createdAt}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                        Text(
                                            text = msg.content,
                                            style = MaterialTheme.typography.bodySmall,
                                        )
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

@Composable
private fun TicketScreenshotThumb(
    item: SupportTicketScreenshot,
    snapshot: SupportTicketSnapshot,
    ticketService: SupportTicketServing,
) {
    val bitmap by produceState<android.graphics.Bitmap?>(initialValue = null, item.id, snapshot) {
        value = runCatching {
            val bytes = ticketService.screenshotBytes(item, snapshot)
            withContext(Dispatchers.Default) {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        }.getOrNull()
    }
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier.size(88.dp),
    ) {
        val loaded = bitmap
        if (loaded != null) {
            Image(
                bitmap = loaded.asImageBitmap(),
                contentDescription = "工单截图 ${item.width}x${item.height}",
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(88.dp),
            )
        } else {
            Box(contentAlignment = Alignment.Center) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        }
    }
}

@Composable
internal fun ScreenshotStrip(
    screenshots: List<FeedbackScreenshot>,
    enabled: Boolean,
    onRemove: (String) -> Unit,
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        for (shot in screenshots) {
            val preview = remember(shot.id) {
                BitmapFactory.decodeByteArray(shot.data, 0, shot.data.size)
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.size(82.dp),
                ) {
                    if (preview != null) {
                        Image(
                            bitmap = preview.asImageBitmap(),
                            contentDescription = "待上传截图 ${shot.width}x${shot.height}",
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(82.dp),
                        )
                    }
                }
                Text(
                    text = "${shot.data.size / 1024} KB",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(
                    enabled = enabled,
                    onClick = { onRemove(shot.id) },
                ) {
                    Text("移除")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HelpAndDiagnosticsSheet(
    accounts: AccountStore,
    logs: DiagnosticLogStore,
    uploadStore: DiagnosticUploadStore,
    screenshotFeedbackEnabled: Boolean,
    onScreenshotFeedbackChange: (Boolean) -> Unit,
    appVersionName: String,
    appVersionCode: String,
    onOpenSupportCenter: () -> Unit,
    onOpenUrl: (String) -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val entries by logs.entries.collectAsStateWithLifecycle()
    val storageError by logs.storageError.collectAsStateWithLifecycle()
    val isUploading by uploadStore.isUploading.collectAsStateWithLifecycle()
    val uploadError by uploadStore.error.collectAsStateWithLifecycle()
    val storageNotice by uploadStore.storageNotice.collectAsStateWithLifecycle()
    val receipt by uploadStore.receipt.collectAsStateWithLifecycle()

    var windowHours by rememberSaveable { mutableIntStateOf(24) }
    var issueDescription by rememberSaveable { mutableStateOf("") }
    var pendingConfirm by remember { mutableStateOf<DiagnosticUploadConfirmation?>(null) }
    var prepareError by remember { mutableStateOf<String?>(null) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "帮助与诊断日志",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                TextButton(onClick = onDismiss) {
                    Text("关闭")
                }
            }

            Surface(
                shape = RoundedCornerShape(14.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "常见问题与支持",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(onClick = { onOpenUrl("https://www.yunle.fun/docs") }) {
                            Text("查看帮助文档")
                        }
                        OutlinedButton(onClick = {
                            onDismiss()
                            onOpenSupportCenter()
                        }) {
                            Text("打开支持中心")
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "截图时提示快捷反馈",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                text = "检测到系统截图后显示快捷反馈横幅或记录（Android 14+）",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = screenshotFeedbackEnabled,
                            onCheckedChange = onScreenshotFeedbackChange,
                        )
                    }
                }
            }

            receipt?.let { currentReceipt ->
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = "已生成支持编号（7 天内有效）",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                        Text(
                            text = currentReceipt.supportCode,
                            style = MaterialTheme.typography.headlineSmall,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = "包含 ${currentReceipt.logCount} 条脱敏日志 · 过期时间 ${formatMillis(currentReceipt.expiresAt)}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        FilledTonalButton(
                            onClick = {
                                val clipboard = context.getSystemService(ClipboardManager::class.java)
                                clipboard?.setPrimaryClip(ClipData.newPlainText("supportCode", currentReceipt.supportCode))
                                Toast.makeText(context, "已复制支持编号", Toast.LENGTH_SHORT).show()
                            },
                        ) {
                            Text("复制支持编号")
                        }
                    }
                }
            }

            if (!storageNotice.isNullOrBlank()) {
                Text(
                    text = storageNotice.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (!storageError.isNullOrBlank()) {
                Text(
                    text = storageError.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Surface(
                shape = RoundedCornerShape(14.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "上传诊断日志排查问题",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "仅上传你确认时间范围内的脱敏日志与设备基础环境信息，不包含账号密钥或本地浏览数据。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (overview.activeUser == null) {
                        FilledTonalButton(onClick = onNavigateToMe) {
                            Text("登录后可上传诊断日志")
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            for (hours in listOf(1, 6, 24)) {
                                FilterChip(
                                    selected = windowHours == hours,
                                    onClick = {
                                        windowHours = hours
                                        prepareError = null
                                        uploadStore.invalidateConfirmation()
                                    },
                                    label = { Text("近 $hours 小时") },
                                )
                            }
                        }
                        OutlinedTextField(
                            value = issueDescription,
                            onValueChange = {
                                if (it.length <= DiagnosticUploadRules.MAX_ISSUE_DESCRIPTION_LENGTH) {
                                    issueDescription = it
                                    prepareError = null
                                    uploadStore.invalidateConfirmation()
                                }
                            },
                            label = { Text("补充说明遇到的问题（可选，最多 500 字）") },
                            minLines = 2,
                            maxLines = 4,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        val activeErr = prepareError ?: uploadError
                        if (!activeErr.isNullOrBlank()) {
                            Text(
                                text = activeErr,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                enabled = !isUploading && entries.isNotEmpty(),
                                onClick = {
                                    val end = System.currentTimeMillis()
                                    val start = end - windowHours * 3_600_000L
                                    val client = DiagnosticClientContext(
                                        appVersion = appVersionName,
                                        buildNumber = appVersionCode,
                                        platform = "android",
                                        route = "/me/diagnostics",
                                        timezone = TimeZone.getDefault().id,
                                        userAgent = "YunleFun-Android/$appVersionName (Android ${Build.VERSION.RELEASE})",
                                    )
                                    runCatching {
                                        uploadStore.prepare(
                                            startTime = start,
                                            endTime = end,
                                            issueDescription = issueDescription,
                                            client = client,
                                        )
                                    }.onSuccess { confirmation ->
                                        prepareError = null
                                        pendingConfirm = confirmation
                                    }.onFailure { err ->
                                        prepareError = err.message
                                    }
                                },
                            ) {
                                Text(if (isUploading) "正在上传…" else "生成上传摘要")
                            }
                            if (isUploading) {
                                OutlinedButton(onClick = uploadStore::cancelUpload) {
                                    Text("取消上传")
                                }
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "本机最近日志（${entries.size}/${DiagnosticUploadRules.MAX_ENTRIES}）",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (entries.isNotEmpty()) {
                    TextButton(onClick = logs::clear) {
                        Text("清空日志")
                    }
                }
            }

            if (entries.isEmpty()) {
                Text(
                    text = "暂无本机诊断日志记录。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        for (entry in entries.takeLast(20).reversed()) {
                            DiagnosticEntryRow(entry)
                        }
                    }
                }
            }
        }
    }

    pendingConfirm?.let { confirmation ->
        AlertDialog(
            onDismissRequest = { pendingConfirm = null },
            title = { Text("确认上传诊断日志") },
            text = {
                Text(
                    "本次将上传 ${confirmation.payload.logs.size} 条已脱敏日志（约 ${(confirmation.sizeBytes / 1024).coerceAtLeast(1)} KB），" +
                        "上传后将生成有效期 7 天的 12 位支持编号供客服排查问题。",
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        pendingConfirm = null
                        uploadStore.upload(confirmation)
                    },
                ) {
                    Text("确认上传")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingConfirm = null }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun SupportBoardCard(item: SupportBoardItem) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "${item.statusTitle} · ${item.voteCount} 票",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Text(
                text = SupportProduct.title(item.productId),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = item.publicContent,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
            if (!item.officialResponse.isNullOrBlank()) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = "官方回复：${item.officialResponse}",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SupportPrivateCard(
    item: SupportPrivateItem,
    onOpenTicket: (String) -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "${SupportProduct.title(item.productId)} · ${SupportCategory.title(item.category)}",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = item.statusTitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Text(
                text = item.description,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "${item.sourceSummary} · ${item.createdAt}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val ticketId = item.ticketId?.takeIf { SupportUrlRules.isValidIdentifier(it) }
                if (ticketId != null) {
                    TextButton(onClick = { onOpenTicket(ticketId) }) {
                        Text("查看工单")
                    }
                }
            }
        }
    }
}

@Composable
private fun ShareRecordCard(
    record: SharedFeedbackRecord,
    onOpenTicket: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = "${SupportProduct.title(record.receipt.productId)} · 编号 ${record.receipt.ticketId ?: record.receipt.id}",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = formatMillis(record.createdAtMillis),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!record.receipt.ticketId.isNullOrBlank()) {
                TextButton(onClick = onOpenTicket) {
                    Text("查看工单")
                }
            }
        }
    }
}

@Composable
private fun DiagnosticEntryRow(entry: DiagnosticLogEntry) {
    val levelColor = when (entry.level) {
        DiagnosticLogLevel.ERROR -> MaterialTheme.colorScheme.error
        DiagnosticLogLevel.WARN -> MaterialTheme.colorScheme.tertiary
        DiagnosticLogLevel.INFO -> MaterialTheme.colorScheme.primary
    }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = "[${entry.level.label}] ${formatMillis(entry.timestamp)}",
            style = MaterialTheme.typography.labelSmall,
            color = levelColor,
        )
        Text(
            text = entry.message,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
        )
    }
}

internal fun readUriBytesLimited(
    context: android.content.Context,
    uri: Uri,
    maxBytes: Int,
): ByteArray? = context.contentResolver.openInputStream(uri)?.use { stream ->
    val out = ByteArrayOutputStream()
    val buf = ByteArray(8192)
    var total = 0
    while (true) {
        val read = stream.read(buf)
        if (read <= 0) break
        total += read
        if (total > maxBytes) return null
        out.write(buf, 0, read)
    }
    out.toByteArray()
}

private fun formatMillis(millis: Long): String {
    val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA)
    return formatter.format(Date(millis))
}
