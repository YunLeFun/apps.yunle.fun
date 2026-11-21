package `fun`.yunle.apps

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.IntentCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.support.FeedbackScreenshot
import `fun`.yunle.apps.support.FeedbackScreenshotNormalizer
import `fun`.yunle.apps.support.SharedFeedbackRecord
import `fun`.yunle.apps.support.SupportAccess
import `fun`.yunle.apps.support.SupportCategory
import `fun`.yunle.apps.support.SupportCenterError
import `fun`.yunle.apps.support.SupportCenterException
import `fun`.yunle.apps.support.SupportFeedbackReceipt
import `fun`.yunle.apps.support.SupportFeedbackSubmission
import `fun`.yunle.apps.support.SupportProduct
import `fun`.yunle.apps.support.SupportUrlRules
import `fun`.yunle.apps.ui.support.ScreenshotStrip
import `fun`.yunle.apps.ui.support.SupportTicketDialog
import `fun`.yunle.apps.ui.support.readUriBytesLimited
import `fun`.yunle.apps.ui.theme.YunleTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

/** Handles Android system ACTION_SEND / ACTION_SEND_MULTIPLE image shares into guest feedback. */
class FeedbackShareReceiveActivity : ComponentActivity() {
    private var incomingUris by mutableStateOf<List<Uri>>(emptyList())
    private var incomingText by mutableStateOf<String?>(null)
    private var shareParseError by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        YunleContainer.ensureInitialized(applicationContext)
        parseShareIntent(intent)

        val appVersionName = runCatching {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0"
        }.getOrDefault("1.0")

        setContent {
            val appearance by YunleContainer.preferences.appearance.collectAsStateWithLifecycle()
            val darkTheme = when (appearance) {
                AppAppearance.SYSTEM -> isSystemInDarkTheme()
                AppAppearance.LIGHT -> false
                AppAppearance.DARK -> true
            }
            YunleTheme(darkTheme = darkTheme) {
                ShareFeedbackScreen(
                    imageUris = incomingUris,
                    initialDescription = incomingText.orEmpty(),
                    initialError = shareParseError,
                    appVersionName = appVersionName,
                    onOpenUrl = { url -> openInCustomTab(this@FeedbackShareReceiveActivity, Uri.parse(url)) },
                    onFinish = { finish() },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        parseShareIntent(intent)
    }

    private fun parseShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.take(4000)
        if (!sharedText.isNullOrBlank()) {
            incomingText = sharedText
        }
        val uris: List<Uri> = when (action) {
            Intent.ACTION_SEND -> listOfNotNull(
                IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java),
            )
            Intent.ACTION_SEND_MULTIPLE -> IntentCompat.getParcelableArrayListExtra(
                intent,
                Intent.EXTRA_STREAM,
                Uri::class.java,
            ).orEmpty()
            else -> emptyList()
        }
        if (uris.isEmpty()) {
            incomingUris = emptyList()
            shareParseError = "未收到可读取的截图图片。"
        } else if (uris.size > FeedbackScreenshot.MAXIMUM_COUNT) {
            incomingUris = uris.take(FeedbackScreenshot.MAXIMUM_COUNT)
            shareParseError = "一次最多支持提交 ${FeedbackScreenshot.MAXIMUM_COUNT} 张截图，已保留前 ${FeedbackScreenshot.MAXIMUM_COUNT} 张。"
        } else {
            incomingUris = uris
            shareParseError = null
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShareFeedbackScreen(
    imageUris: List<Uri>,
    initialDescription: String,
    initialError: String?,
    appVersionName: String,
    onOpenUrl: (String) -> Unit,
    onFinish: () -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()

    var screenshots by remember { mutableStateOf<List<FeedbackScreenshot>>(emptyList()) }
    var isImporting by remember { mutableStateOf(imageUris.isNotEmpty()) }
    var isSubmitting by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf(initialError) }
    var product by rememberSaveable { mutableStateOf("www") }
    var category by rememberSaveable { mutableStateOf("problem") }
    var description by rememberSaveable { mutableStateOf(initialDescription) }
    var guestAccess by remember { mutableStateOf<SupportAccess?>(null) }
    var lastDigest by remember { mutableStateOf<List<String>>(emptyList()) }
    var idempotencyKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
    var receipt by remember { mutableStateOf<SupportFeedbackReceipt?>(null) }
    var confirmSubmission by remember { mutableStateOf<SupportFeedbackSubmission?>(null) }
    var showTicket by remember { mutableStateOf(false) }

    LaunchedEffect(initialDescription) {
        if (receipt == null && initialDescription.isNotBlank() && description.isBlank()) {
            description = initialDescription
        }
    }

    LaunchedEffect(imageUris) {
        receipt = null
        showTicket = false
        confirmSubmission = null
        if (imageUris.isEmpty()) {
            screenshots = emptyList()
            isImporting = false
            return@LaunchedEffect
        }
        isImporting = true
        val prepared = withContext(Dispatchers.IO) {
            val out = mutableListOf<FeedbackScreenshot>()
            var failure: String? = null
            for (uri in imageUris.take(FeedbackScreenshot.MAXIMUM_COUNT)) {
                val res = runCatching {
                    val raw = readUriBytesLimited(context, uri, FeedbackScreenshot.MAXIMUM_INPUT_BYTES)
                        ?: throw SupportCenterException(SupportCenterError.INVALID_SCREENSHOT)
                    FeedbackScreenshotNormalizer.prepare(raw, maximumPixels = 12_000_000.0)
                }
                res.fold(
                    onSuccess = { out.add(it) },
                    onFailure = { err ->
                        failure = (err as? SupportCenterException)?.message
                            ?: SupportCenterError.INVALID_SCREENSHOT.defaultMessage
                    },
                )
            }
            out to failure
        }
        screenshots = prepared.first
        if (prepared.second != null) {
            errorMessage = prepared.second
        } else if (initialError != null) {
            errorMessage = initialError
        }
        isImporting = false
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            TopAppBar(
                title = { Text("分享截图到云乐坊反馈") },
                actions = {
                    TextButton(onClick = onFinish) {
                        Text("关闭")
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            val currentReceipt = receipt
            if (currentReceipt != null) {
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            text = "截图反馈已收到",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = "产品：${SupportProduct.title(currentReceipt.productId)}",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        if (!currentReceipt.ticketId.isNullOrBlank()) {
                            Text(
                                text = "工单编号：${currentReceipt.ticketId}",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        Text(
                            text = "本次回执已保存在本机“支持中心 -> 反馈管理 -> 系统分享反馈记录”中。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (!currentReceipt.ticketId.isNullOrBlank()) {
                                Button(onClick = { showTicket = true }) {
                                    Text("查看工单")
                                }
                            }
                            OutlinedButton(onClick = onFinish) {
                                Text("完成")
                            }
                        }
                    }
                }
            } else {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = "仅上传重新压缩后的截图像素与你填写的文字，原文件名、照片 Exif 元数据和账号凭证不会被上传。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(12.dp),
                    )
                }

                if (isImporting) {
                    Box(
                        modifier = Modifier.fillMaxWidth().padding(20.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                } else if (screenshots.isNotEmpty()) {
                    ScreenshotStrip(
                        screenshots = screenshots,
                        enabled = !isSubmitting,
                        onRemove = { id -> screenshots = screenshots.filterNot { it.id == id } },
                    )
                }

                if (!errorMessage.isNullOrBlank()) {
                    Text(
                        text = errorMessage.orEmpty(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }

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
                    label = { Text("问题描述（5 - 4000 字）") },
                    minLines = 4,
                    maxLines = 7,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = { Text("${description.trim().length} / 4000") },
                )

                val trimmedLen = description.trim().length
                Button(
                    enabled = !isImporting && !isSubmitting && trimmedLen in 5..4000,
                    onClick = {
                        val candidate = SupportFeedbackSubmission.fromScreenshots(
                            product = product,
                            category = category,
                            description = description,
                            screenshots = screenshots,
                            context = SupportFeedbackSubmission.Context(
                                source = "apps-android-share",
                                version = appVersionName,
                            ),
                        )
                        runCatching { candidate.validate() }
                            .onSuccess { confirmSubmission = candidate }
                            .onFailure { err -> errorMessage = err.message }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (isSubmitting) "正在提交…" else "提交截图反馈")
                }
            }
        }
    }

    confirmSubmission?.let { frozen ->
        AlertDialog(
            onDismissRequest = { confirmSubmission = null },
            title = { Text("确认提交截图反馈") },
            text = {
                Text(
                    "将向「${SupportProduct.title(frozen.productId)}」提交这段描述与 ${frozen.images.size} 张脱敏压缩截图。",
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        confirmSubmission = null
                        val digest = listOf(frozen.productId, frozen.category, frozen.description) +
                            screenshots.map { it.sha256Hex() }
                        if (digest != lastDigest) {
                            lastDigest = digest
                            idempotencyKey = UUID.randomUUID().toString()
                        }
                        isSubmitting = true
                        errorMessage = null
                        scope.launch {
                            runCatching {
                                val access = guestAccess ?: YunleContainer.supportService.connect(identity = null, consent = false)
                                    .also { guestAccess = it }
                                val res = YunleContainer.supportService.submit(
                                    product = frozen.productId,
                                    category = frozen.category,
                                    description = frozen.description,
                                    screenshots = screenshots,
                                    key = idempotencyKey,
                                    access = access,
                                    context = frozen.context,
                                )
                                if (SupportUrlRules.ticketUrl(res, requiringGuestAccess = true) == null) {
                                    throw SupportCenterException(SupportCenterError.INVALID_RESPONSE)
                                }
                                res
                            }.onSuccess { res ->
                                val record = SharedFeedbackRecord(
                                    receipt = res,
                                    createdAtMillis = System.currentTimeMillis(),
                                )
                                YunleContainer.sharedFeedbackHistory.save(
                                    record = record,
                                    expectedUserId = YunleContainer.accounts.user?.id,
                                )
                                receipt = res
                                isSubmitting = false
                            }.onFailure { err ->
                                if ((err as? SupportCenterException)?.error == SupportCenterError.UNAUTHORIZED) {
                                    guestAccess = null
                                }
                                errorMessage = err.message ?: SupportCenterError.UNAVAILABLE.defaultMessage
                                isSubmitting = false
                            }
                        }
                    },
                ) {
                    Text("确认提交")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmSubmission = null }) {
                    Text("取消")
                }
            },
        )
    }

    if (showTicket && receipt != null) {
        SupportTicketDialog(
            receipt = receipt!!,
            cookies = emptyList(),
            externalUrl = receipt?.ticketUrl,
            ticketService = YunleContainer.supportTicketClient,
            onOpenUrl = onOpenUrl,
            onDismiss = { showTicket = false },
        )
    }
}
