package `fun`.yunle.apps.ui.wallet

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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.wallet.CoinLedgerEntry
import `fun`.yunle.apps.wallet.OnlineWebBillingProvider
import `fun`.yunle.apps.wallet.PurchaseOwnershipJournal
import `fun`.yunle.apps.wallet.WalletError
import `fun`.yunle.apps.wallet.WalletServing
import `fun`.yunle.apps.wallet.WalletSnapshot
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WalletModalSheet(
    accounts: AccountStore,
    service: WalletServing,
    journal: PurchaseOwnershipJournal,
    onOpenCheckoutUrl: (String) -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var snapshot by remember { mutableStateOf<WalletSnapshot?>(null) }
    var entries by remember { mutableStateOf<List<CoinLedgerEntry>>(emptyList()) }
    var nextSkip by remember { mutableStateOf<Int?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var isBusy by remember { mutableStateOf(false) }
    var statusNotice by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val billingProvider = remember(journal, onOpenCheckoutUrl) {
        OnlineWebBillingProvider(journal, onOpenCheckoutUrl)
    }

    suspend fun loadInitial() {
        val activeUser = accounts.user?.takeIf { it.isUsable } ?: run {
            snapshot = null
            entries = emptyList()
            nextSkip = null
            return
        }
        val gen = identityGeneration
        isLoading = true
        errorMessage = null
        val outcome = runCatching {
            val identity = accounts.authorization(forceRefresh = false)
            val snap = service.account(identity)
            val page = service.transactions(skip = 0, limit = 20, identity = identity)
            snap to page
        }
        isLoading = false
        if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return
        outcome.fold(
            onSuccess = { (snap, page) ->
                snapshot = snap
                entries = page.items
                nextSkip = page.nextSkip
            },
            onFailure = { errorMessage = WalletError.message(it) },
        )
    }

    LaunchedEffect(overview.activeID, identityGeneration) {
        loadInitial()
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
                Text(
                    text = "钱包与会员",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                if (overview.activeUser?.isUsable == true) {
                    TextButton(
                        onClick = {
                            val activeUser = accounts.user?.takeIf { it.isUsable } ?: return@TextButton
                            val gen = identityGeneration
                            scope.launch {
                                isBusy = true
                                statusNotice = null
                                errorMessage = null
                                val res = runCatching {
                                    val identity = accounts.authorization(forceRefresh = false)
                                    val rec = service.reconcile(identity)
                                    rec
                                }
                                isBusy = false
                                if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return@launch
                                res.fold(
                                    onSuccess = { rec ->
                                        statusNotice = if (rec.paid > 0) {
                                            "已核对并入账 ${rec.paid} 笔订单"
                                        } else {
                                            "已完成订单核对，暂无待入账订单"
                                        }
                                        loadInitial()
                                    },
                                    onFailure = { errorMessage = WalletError.message(it) },
                                )
                            }
                        },
                        enabled = !isBusy,
                    ) {
                        Text("对账刷新")
                    }
                }
            }

            if (overview.activeUser?.isUsable != true) {
                Text(
                    text = "登录云乐坊账号后可查看云币余额、收支明细与会员状态。",
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

            statusNotice?.let { msg ->
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(msg, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(12.dp))
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
                        OutlinedButton(onClick = { scope.launch { loadInitial() } }, enabled = !isBusy) {
                            Text("重试")
                        }
                    }
                }
            }

            if (isLoading && snapshot == null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            snapshot?.let { snap ->
                Surface(
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "可用云币",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                        )
                        Text(
                            text = "${snap.coin}",
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                        val memberText = if (snap.membership.isActive) {
                            val exp = snap.membership.expireAtMillis?.let(::formatWalletDate).orEmpty()
                            "${snap.membership.title} · 有效期至 $exp"
                        } else {
                            "当前未开通云乐坊会员"
                        }
                        Text(
                            text = memberText,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                        Button(
                            onClick = {
                                val uid = accounts.user?.id ?: return@Button
                                val ref = UUID.randomUUID().toString().replace("-", "").take(24)
                                runCatching {
                                    billingProvider.launchRecharge(context, ref, uid)
                                }.onFailure {
                                    Toast.makeText(context, WalletError.message(it), Toast.LENGTH_SHORT).show()
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("充值云币与开通会员")
                        }
                    }
                }
            }

            Text(
                text = "收支明细 (${entries.size})",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (entries.isEmpty() && !isLoading) {
                Text(
                    text = "暂无云币交易记录。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                entries.forEach { item ->
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
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = item.appId?.let { "${item.title} · $it" } ?: item.title,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    text = "${formatWalletDate(item.createdAtMillis)} · 余额 ${item.balanceAfter}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Text(
                                text = if (item.amount >= 0) "+${item.amount}" else "${item.amount}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = if (item.amount >= 0) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                            )
                        }
                    }
                }
            }

            nextSkip?.let { skip ->
                FilledTonalButton(
                    onClick = {
                        val activeUser = accounts.user?.takeIf { it.isUsable } ?: return@FilledTonalButton
                        val gen = identityGeneration
                        scope.launch {
                            isBusy = true
                            val res = runCatching {
                                val identity = accounts.authorization(forceRefresh = false)
                                service.transactions(skip = skip, limit = 20, identity = identity)
                            }
                            isBusy = false
                            if (accounts.identityGeneration.value != gen || accounts.user?.id != activeUser.id) return@launch
                            res.fold(
                                onSuccess = { page ->
                                    entries = entries + page.items
                                    nextSkip = page.nextSkip
                                },
                                onFailure = { errorMessage = WalletError.message(it) },
                            )
                        }
                    },
                    enabled = !isBusy,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (isBusy) "加载中…" else "加载更多")
                }
            }
        }
    }
}

private fun formatWalletDate(epochMillis: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(epochMillis))
