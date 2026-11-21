package `fun`.yunle.apps.ui.catalog

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.catalog.ApplicationAcquisitionError
import `fun`.yunle.apps.catalog.ApplicationAcquisitionException
import `fun`.yunle.apps.catalog.ApplicationAcquisitionQuote
import `fun`.yunle.apps.catalog.ApplicationAcquisitionServing
import `fun`.yunle.apps.catalog.ApplicationAcquisitionState
import `fun`.yunle.apps.catalog.DeveloperProfile
import `fun`.yunle.apps.catalog.DeveloperProfileError
import `fun`.yunle.apps.catalog.DeveloperProfileServing
import `fun`.yunle.apps.catalog.PersonalMarketLaunchAuthorization
import kotlinx.coroutines.launch

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
internal fun ApplicationShareSheet(
    app: CatalogApp,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val shareUrl = remember(app.key) { "https://apps.yunle.fun/app/${app.key}" }
    var darkCard by remember { mutableStateOf(false) }

    val cardContainer = if (darkCard) Color(0xFF181A1F) else Color(0xFFFDFCFB)
    val cardText = if (darkCard) Color(0xFFF3F4F6) else Color(0xFF181A1F)
    val cardSubtext = if (darkCard) Color(0xFF9CA3AF) else Color(0xFF5F6368)
    val cardBorder = if (darkCard) Color(0xFF2D313B) else MaterialTheme.colorScheme.outlineVariant

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = "分享应用卡片",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = !darkCard,
                    onClick = { darkCard = false },
                    label = { Text("浅色卡片") },
                )
                FilterChip(
                    selected = darkCard,
                    onClick = { darkCard = true },
                    label = { Text("深色卡片") },
                )
            }

            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = cardContainer,
                border = BorderStroke(1.dp, cardBorder),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        AppIconBadge(app = app, size = 56.dp)
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = app.name,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = cardText,
                            )
                            Text(
                                text = "${app.author} · ${app.browseCategory}",
                                style = MaterialTheme.typography.labelMedium,
                                color = cardSubtext,
                            )
                        }
                    }
                    Text(
                        text = app.description.ifBlank { "在云乐坊工坊发现并使用这个轻量云应用。" },
                        style = MaterialTheme.typography.bodyMedium,
                        color = cardText.copy(alpha = 0.9f),
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                    HorizontalDivider(color = cardBorder.copy(alpha = 0.6f))
                    Text(
                        text = shareUrl,
                        style = MaterialTheme.typography.labelSmall,
                        color = cardSubtext,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                OutlinedButton(
                    onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        clipboard?.setPrimaryClip(ClipData.newPlainText(app.name, shareUrl))
                        Toast.makeText(context, "链接已复制", Toast.LENGTH_SHORT).show()
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("复制链接")
                }
                Button(
                    onClick = {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, app.name)
                            putExtra(
                                Intent.EXTRA_TEXT,
                                "推荐一个云乐坊应用「${app.name}」\n$shareUrl",
                            )
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "分享 ${app.name}"))
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("系统分享")
                }
            }
        }
    }
}
