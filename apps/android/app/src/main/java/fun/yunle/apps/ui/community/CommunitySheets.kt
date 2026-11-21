package `fun`.yunle.apps.ui.community

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
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
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.community.AppReview
import `fun`.yunle.apps.community.CommunityError
import `fun`.yunle.apps.community.CommunityException
import `fun`.yunle.apps.community.CommunityServing
import `fun`.yunle.apps.community.CommunityValidation
import `fun`.yunle.apps.community.MyReport
import `fun`.yunle.apps.community.ReportDraft
import `fun`.yunle.apps.community.ReportReason
import `fun`.yunle.apps.community.ReportTarget
import `fun`.yunle.apps.community.ReportTargetType
import `fun`.yunle.apps.community.ReviewDraft
import `fun`.yunle.apps.community.ReviewList
import `fun`.yunle.apps.community.ReviewStatus
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun ApplicationReviewsSheet(
    app: CatalogApp,
    accounts: AccountStore,
    service: CommunityServing,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val appKey = remember(app) { CommunityValidation.appKeyFor(app) }
    var reviewList by remember(app.id) { mutableStateOf<ReviewList?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var statusNotice by remember { mutableStateOf<String?>(null) }
    var editingReview by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf(ReviewDraft()) }
    var confirmDelete by remember { mutableStateOf<AppReview?>(null) }
    var reportTarget by remember { mutableStateOf<ReportTarget?>(null) }

    suspend fun loadReviews() {
        val key = appKey ?: return
        val gen = identityGeneration
        val activeUser = accounts.user?.takeIf { it.isUsable }
        isLoading = true
        errorMessage = null
        val outcome = runCatching {
            val identity = activeUser?.let { accounts.authorization(forceRefresh = false) }
            service.listReviews(key, identity)
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen) return
        outcome.fold(
            onSuccess = { loaded ->
                reviewList = loaded
            },
            onFailure = { err ->
                errorMessage = CommunityError.message(err)
            },
        )
    }

    LaunchedEffect(app.id, overview.activeID, identityGeneration) {
        loadReviews()
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
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "${app.name} · 评分与评价",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = "评价仅来自云乐坊用户社区",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (appKey != null) {
                    TextButton(
                        onClick = {
                            if (overview.activeUser?.isUsable != true) {
                                Toast.makeText(context, "请先登录后提交举报", Toast.LENGTH_SHORT).show()
                                onDismiss()
                                onNavigateToMe()
                            } else {
                                reportTarget = ReportTarget(
                                    type = ReportTargetType.APP,
                                    id = appKey,
                                    label = "应用「${app.name}」",
                                    appKey = appKey,
                                )
                            }
                        },
                        enabled = !isBusy,
                    ) {
                        Text("举报应用")
                    }
                }
            }

            if (appKey == null) {
                Text(
                    text = "该应用暂未提供评价标识。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                return@Column
            }

            statusNotice?.let { notice ->
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = notice,
                        style = MaterialTheme.typography.bodyMedium,
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
                        Text(msg, style = MaterialTheme.typography.bodyMedium)
                        OutlinedButton(onClick = { scope.launch { loadReviews() } }, enabled = !isBusy) {
                            Text("重试")
                        }
                    }
                }
            }

            if (isLoading && reviewList == null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            reviewList?.let { loaded ->
                val summary = loaded.summary
                Surface(
                    shape = MaterialTheme.shapes.large,
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = String.format(Locale.US, "%.1f", summary.average),
                                style = MaterialTheme.typography.displaySmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                text = if (summary.count > 0) "共 ${summary.count} 条评分" else "暂无评分",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            for (star in 5 downTo 1) {
                                val count = summary.distribution[star] ?: 0
                                val progress = if (summary.count > 0) count.toFloat() / summary.count else 0f
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    Text(
                                        text = "${star}星",
                                        style = MaterialTheme.typography.labelSmall,
                                        modifier = Modifier.width(26.dp),
                                    )
                                    LinearProgressIndicator(
                                        progress = { progress },
                                        modifier = Modifier
                                            .weight(1f)
                                            .height(6.dp),
                                    )
                                    Text(
                                        text = count.toString(),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }

                // My Review / Compose section
                val activeUser = overview.activeUser?.takeIf { it.isUsable }
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
                        if (activeUser == null) {
                            Text(
                                text = "登录后即可撰写或管理自己的评价",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Button(
                                onClick = {
                                    onDismiss()
                                    onNavigateToMe()
                                },
                            ) {
                                Text("前往登录")
                            }
                        } else if (editingReview) {
                            Text(
                                text = if (loaded.myReview == null) "撰写评价" else "修改我的评价",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                for (star in 1..5) {
                                    FilterChip(
                                        selected = draft.rating == star,
                                        onClick = { draft = draft.copy(rating = star) },
                                        enabled = !isBusy,
                                        label = { Text("${star}★") },
                                    )
                                }
                            }
                            OutlinedTextField(
                                value = draft.title,
                                onValueChange = { if (it.length <= CommunityValidation.MAX_TITLE_LENGTH) draft = draft.copy(title = it) },
                                label = { Text("标题（选填，最多 100 字）") },
                                singleLine = true,
                                enabled = !isBusy,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            OutlinedTextField(
                                value = draft.content,
                                onValueChange = { if (it.length <= CommunityValidation.MAX_CONTENT_LENGTH) draft = draft.copy(content = it) },
                                label = { Text("评价内容（1-1000 字）") },
                                minLines = 3,
                                enabled = !isBusy,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                OutlinedButton(
                                    onClick = { editingReview = false },
                                    enabled = !isBusy,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("取消")
                                }
                                Button(
                                    onClick = {
                                        val gen = identityGeneration
                                        scope.launch {
                                            isBusy = true
                                            errorMessage = null
                                            statusNotice = null
                                            val result = runCatching {
                                                val identity = accounts.authorization(forceRefresh = false)
                                                service.submitReview(appKey, draft, identity)
                                            }
                                            isBusy = false
                                            if (accounts.identityGeneration.value != gen) return@launch
                                            result.fold(
                                                onSuccess = { submission ->
                                                    editingReview = false
                                                    statusNotice = submission.message ?: submission.status.label
                                                    loadReviews()
                                                },
                                                onFailure = { err ->
                                                    errorMessage = CommunityError.message(err)
                                                },
                                            )
                                        }
                                    },
                                    enabled = !isBusy && draft.isValid,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text(if (isBusy) "提交中…" else "提交评价")
                                }
                            }
                        } else if (loaded.myReview != null) {
                            val mine = loaded.myReview
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "我的评价 · ${"★".repeat(mine.rating)}",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Surface(
                                    shape = MaterialTheme.shapes.small,
                                    color = when (mine.status) {
                                        ReviewStatus.PUBLISHED -> MaterialTheme.colorScheme.secondaryContainer
                                        ReviewStatus.PENDING -> MaterialTheme.colorScheme.tertiaryContainer
                                        ReviewStatus.REJECTED -> MaterialTheme.colorScheme.errorContainer
                                    },
                                ) {
                                    Text(
                                        text = mine.status.label,
                                        style = MaterialTheme.typography.labelSmall,
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    )
                                }
                            }
                            mine.title?.let {
                                Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                            }
                            Text(mine.content, style = MaterialTheme.typography.bodyMedium)
                            mine.rejectedReason?.let { reason ->
                                Text(
                                    text = "未通过原因：$reason",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedButton(
                                    onClick = {
                                        draft = ReviewDraft.fromReview(mine)
                                        editingReview = true
                                    },
                                    enabled = !isBusy,
                                ) {
                                    Text("修改")
                                }
                                TextButton(
                                    onClick = { confirmDelete = mine },
                                    enabled = !isBusy,
                                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                                ) {
                                    Text("删除")
                                }
                            }
                        } else {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "分享你的使用体验",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Button(
                                    onClick = {
                                        draft = ReviewDraft()
                                        editingReview = true
                                    },
                                    enabled = !isBusy,
                                ) {
                                    Text("写评价")
                                }
                            }
                        }
                    }
                }

                // Public reviews list
                Text(
                    text = "社区评价 (${loaded.reviews.size})",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                if (loaded.reviews.isEmpty()) {
                    Text(
                        text = "还没有公开评价，欢迎成为第一位评价者。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    loaded.reviews.forEach { review ->
                        Surface(
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(
                                modifier = Modifier.padding(14.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = review.authorName,
                                            style = MaterialTheme.typography.titleSmall,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        Text(
                                            text = "${"★".repeat(review.rating)} · ${formatReviewDate(review.updatedAt)}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    TextButton(
                                        onClick = {
                                            if (overview.activeUser?.isUsable != true) {
                                                Toast.makeText(context, "请先登录后提交举报", Toast.LENGTH_SHORT).show()
                                                onDismiss()
                                                onNavigateToMe()
                                            } else {
                                                reportTarget = ReportTarget(
                                                    type = ReportTargetType.REVIEW,
                                                    id = review.id,
                                                    label = "${review.authorName} 的评价",
                                                    appKey = appKey,
                                                )
                                            }
                                        },
                                        enabled = !isBusy,
                                    ) {
                                        Text("举报")
                                    }
                                }
                                review.title?.let {
                                    Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                }
                                Text(review.content, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
        }
    }

    confirmDelete?.let { mine ->
        AlertDialog(
            onDismissRequest = { if (!isBusy) confirmDelete = null },
            title = { Text("删除我的评价？") },
            text = { Text("删除后将不再展示在应用评价列表中。") },
            dismissButton = {
                TextButton(onClick = { confirmDelete = null }, enabled = !isBusy) { Text("取消") }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val gen = identityGeneration
                        confirmDelete = null
                        scope.launch {
                            isBusy = true
                            errorMessage = null
                            val result = runCatching {
                                val identity = accounts.authorization(forceRefresh = false)
                                service.deleteReview(mine.id, identity)
                            }
                            isBusy = false
                            if (accounts.identityGeneration.value != gen) return@launch
                            result.fold(
                                onSuccess = {
                                    statusNotice = "评价已删除"
                                    loadReviews()
                                },
                                onFailure = { err ->
                                    errorMessage = CommunityError.message(err)
                                },
                            )
                        }
                    },
                    enabled = !isBusy,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("确认删除")
                }
            },
        )
    }

    reportTarget?.let { target ->
        ReportTargetDialog(
            target = target,
            accounts = accounts,
            service = service,
            onNavigateToMe = onNavigateToMe,
            onDismiss = { reportTarget = null },
            onSubmitted = {
                statusNotice = "举报已提交，我们会尽快审核处理。"
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MyReportsSheet(
    accounts: AccountStore,
    service: CommunityServing,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var reports by remember { mutableStateOf<List<MyReport>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    suspend fun loadReports() {
        val activeUser = accounts.user?.takeIf { it.isUsable }
        val gen = identityGeneration
        if (activeUser == null) {
            reports = emptyList()
            errorMessage = null
            return
        }
        isLoading = true
        errorMessage = null
        val result = runCatching {
            val identity = accounts.authorization(forceRefresh = false)
            service.myReports(identity)
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return
        result.fold(
            onSuccess = { reports = it },
            onFailure = { errorMessage = CommunityError.message(it) },
        )
    }

    LaunchedEffect(overview.activeID, identityGeneration) {
        loadReports()
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
                text = "我的举报",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            if (overview.activeUser?.isUsable != true) {
                Text(
                    text = "请先登录云乐坊账号后再查看你的举报记录。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = {
                        onDismiss()
                        onNavigateToMe()
                    },
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
                        OutlinedButton(onClick = { scope.launch { loadReports() } }) {
                            Text("重试")
                        }
                    }
                }
            }

            if (isLoading && reports.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else if (reports.isEmpty() && errorMessage == null) {
                Text(
                    text = "你还没有提交过举报记录。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                reports.forEach { report ->
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "${report.targetType.label} · ${report.appName ?: report.appKey ?: report.targetId}",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                                Surface(
                                    shape = MaterialTheme.shapes.small,
                                    color = MaterialTheme.colorScheme.secondaryContainer,
                                ) {
                                    Text(
                                        text = report.status.label,
                                        style = MaterialTheme.typography.labelSmall,
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    )
                                }
                            }
                            Text(
                                text = "原因：${report.reason.label} · ${formatReviewDate(report.createdAt)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            report.detail?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall)
                            }
                            report.handledAt?.let { handled ->
                                Text(
                                    text = "处理时间：${formatReviewDate(handled)}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ReportTargetDialog(
    target: ReportTarget,
    accounts: AccountStore,
    service: CommunityServing,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
    onSubmitted: () -> Unit = {},
) {
    val context = LocalContext.current
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var draft by remember { mutableStateOf(ReportDraft()) }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!isBusy) onDismiss() },
        title = { Text("举报 ${target.label}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "请选择举报原因（请如实反馈违规问题）：",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    ReportReason.entries.forEach { reason ->
                        FilterChip(
                            selected = draft.reason == reason,
                            onClick = { draft = draft.copy(reason = reason) },
                            enabled = !isBusy,
                            label = { Text(reason.label) },
                        )
                    }
                }
                OutlinedTextField(
                    value = draft.detail,
                    onValueChange = { if (it.length <= CommunityValidation.MAX_REPORT_DETAIL_LENGTH) draft = draft.copy(detail = it) },
                    label = { Text("补充说明（选填，最多 500 字）") },
                    minLines = 2,
                    enabled = !isBusy,
                    modifier = Modifier.fillMaxWidth(),
                )
                errorMessage?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isBusy) {
                Text("取消")
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val activeUser = accounts.user?.takeIf { it.isUsable }
                    if (activeUser == null) {
                        onDismiss()
                        onNavigateToMe()
                        return@Button
                    }
                    val gen = identityGeneration
                    scope.launch {
                        isBusy = true
                        errorMessage = null
                        val result = runCatching {
                            val identity = accounts.authorization(forceRefresh = false)
                            service.submitReport(target, draft, identity)
                        }
                        isBusy = false
                        if (accounts.identityGeneration.value != gen) return@launch
                        result.fold(
                            onSuccess = {
                                Toast.makeText(context, "举报已提交", Toast.LENGTH_SHORT).show()
                                onSubmitted()
                                onDismiss()
                            },
                            onFailure = { err ->
                                errorMessage = CommunityError.message(err)
                            },
                        )
                    }
                },
                enabled = !isBusy && draft.isValid,
            ) {
                Text(if (isBusy) "提交中…" else "提交举报")
            }
        },
    )
}

private fun formatReviewDate(epochMillis: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(epochMillis))
