package `fun`.yunle.apps.ui.assistant

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.assistant.AssistantError
import `fun`.yunle.apps.assistant.AssistantException
import `fun`.yunle.apps.assistant.AssistantHistoryStore
import `fun`.yunle.apps.assistant.AssistantMessage
import `fun`.yunle.apps.assistant.AssistantRunAccumulator
import `fun`.yunle.apps.assistant.AssistantRunInput
import `fun`.yunle.apps.assistant.AssistantServing
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun AssistantModalSheet(
    accounts: AccountStore,
    service: AssistantServing,
    historyStore: AssistantHistoryStore,
    catalogApps: List<CatalogApp>,
    homeInstalledIds: Set<String>,
    onLaunchApp: (CatalogApp) -> Unit,
    onToggleHome: (CatalogApp) -> Unit,
    onSelectAppDetail: (CatalogApp) -> Unit,
    onOpenWallet: () -> Unit,
    onNavigateToMe: () -> Unit,
    onDismiss: () -> Unit,
) {
    val overview by accounts.overview.collectAsStateWithLifecycle()
    val identityGeneration by accounts.identityGeneration.collectAsStateWithLifecycle()
    val persistedMessages by historyStore.messages.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var threadId by remember(overview.activeID) { mutableStateOf(UUID.randomUUID().toString()) }
    var promptInput by remember { mutableStateOf("") }
    var activeJob by remember { mutableStateOf<Job?>(null) }
    var errorState by remember { mutableStateOf<AssistantError?>(null) }
    var liveAssistant by remember { mutableStateOf<AssistantMessage?>(null) }

    val displayedMessages = remember(persistedMessages, liveAssistant) {
        val current = liveAssistant
        if (current != null) persistedMessages + current else persistedMessages
    }
    val activeUser = overview.activeUser?.takeIf { it.isUsable }
    val isStreaming = activeJob?.isActive == true

    fun updateAssistant(msg: AssistantMessage) {
        liveAssistant = msg
    }

    fun sendMessages(historyWithUser: List<AssistantMessage>) {
        val user = activeUser ?: return
        val gen = identityGeneration
        errorState = null
        val assistantMsgId = UUID.randomUUID().toString()
        val runId = UUID.randomUUID().toString()
        val accumulator = AssistantRunAccumulator(threadId = threadId, runId = runId)
        updateAssistant(
            AssistantMessage(
                id = assistantMsgId,
                role = AssistantMessage.Role.ASSISTANT,
                content = "",
                status = AssistantMessage.Status.STREAMING,
                toolStatus = accumulator.status,
            ),
        )
        activeJob = scope.launch {
            try {
                val identity = accounts.authorization(forceRefresh = false)
                val inputMessages = historyWithUser.takeLast(32).map { m ->
                    AssistantRunInput.InputMessage(m.id, m.role, m.content)
                }
                val runInput = AssistantRunInput(
                    threadId = threadId,
                    runId = runId,
                    messages = inputMessages,
                )
                service.streamEvents(runInput, identity).collect { event ->
                    if (accounts.identityGeneration.value != gen || accounts.user?.id != user.id) {
                        throw AssistantException(AssistantError.IDENTITY_CHANGED)
                    }
                    accumulator.apply(event)
                    updateAssistant(
                        AssistantMessage(
                            id = assistantMsgId,
                            role = AssistantMessage.Role.ASSISTANT,
                            content = accumulator.content,
                            cards = accumulator.cards.toList(),
                            status = if (accumulator.finished) AssistantMessage.Status.DONE else AssistantMessage.Status.STREAMING,
                            toolStatus = accumulator.status,
                        ),
                    )
                }
                if (accounts.identityGeneration.value == gen && accounts.user?.id == user.id) {
                    val finalized = AssistantMessage(
                        id = assistantMsgId,
                        role = AssistantMessage.Role.ASSISTANT,
                        content = accumulator.content,
                        cards = accumulator.cards.toList(),
                        status = AssistantMessage.Status.DONE,
                        toolStatus = null,
                    )
                    liveAssistant = null
                    historyStore.save(historyWithUser + finalized, user.id)
                }
            } catch (_: CancellationException) {
                val stopped = AssistantMessage(
                    id = assistantMsgId,
                    role = AssistantMessage.Role.ASSISTANT,
                    content = accumulator.content,
                    cards = accumulator.cards.toList(),
                    status = AssistantMessage.Status.STOPPED,
                    toolStatus = null,
                )
                liveAssistant = null
                if (accumulator.content.isNotBlank() || accumulator.cards.isNotEmpty()) {
                    historyStore.save(historyWithUser + stopped, user.id)
                }
            } catch (t: Throwable) {
                if (accounts.identityGeneration.value != gen || accounts.user?.id != user.id) {
                    liveAssistant = null
                    errorState = AssistantError.IDENTITY_CHANGED
                } else {
                    val err = (t as? AssistantException)?.error ?: AssistantError.UNAVAILABLE
                    errorState = err
                    val partial = AssistantMessage(
                        id = assistantMsgId,
                        role = AssistantMessage.Role.ASSISTANT,
                        content = accumulator.content,
                        cards = accumulator.cards.toList(),
                        status = AssistantMessage.Status.FAILED,
                        toolStatus = null,
                    )
                    liveAssistant = null
                    if (accumulator.content.isNotBlank() || accumulator.cards.isNotEmpty()) {
                        historyStore.save(historyWithUser + partial, user.id)
                    }
                }
            } finally {
                activeJob = null
            }
        }
    }

    ModalBottomSheet(onDismissRequest = {
        activeJob?.cancel()
        onDismiss()
    }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "AI 找应用",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = "说出场景或需求，帮你推荐云乐坊公开应用",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (activeUser != null && displayedMessages.isNotEmpty()) {
                    TextButton(
                        onClick = {
                            activeJob?.cancel()
                            liveAssistant = null
                            errorState = null
                            threadId = UUID.randomUUID().toString()
                            historyStore.clear(activeUser.id)
                        },
                    ) {
                        Text("新对话")
                    }
                }
            }

            if (activeUser == null) {
                Text(
                    text = "请先登录云乐坊账号后使用 AI 找应用助手。",
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

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 160.dp, max = 380.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (displayedMessages.isEmpty()) {
                    Text(
                        text = "试试问我：「帮我找个做简历或学做菜的应用」",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    displayedMessages.forEach { message ->
                        val isUser = message.role == AssistantMessage.Role.USER
                        Surface(
                            shape = MaterialTheme.shapes.large,
                            color = if (isUser) {
                                MaterialTheme.colorScheme.primaryContainer
                            } else {
                                MaterialTheme.colorScheme.surfaceContainerLow
                            },
                            border = if (isUser) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(
                                modifier = Modifier.padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    text = if (isUser) "我" else "云乐坊 AI",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                message.toolStatus?.let { tool ->
                                    Text(
                                        text = tool,
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                                if (message.content.isNotBlank()) {
                                    Text(
                                        text = message.content,
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                }
                                if (message.cards.isNotEmpty()) {
                                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                                    message.cards.forEach { card ->
                                        val resolved = card.resolve(catalogApps)
                                        Surface(
                                            shape = MaterialTheme.shapes.medium,
                                            color = MaterialTheme.colorScheme.surface,
                                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                            modifier = Modifier.fillMaxWidth(),
                                        ) {
                                            Row(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .padding(10.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                            ) {
                                                if (resolved != null) {
                                                    AppIconBadge(app = resolved, size = 40.dp)
                                                }
                                                Column(modifier = Modifier.weight(1f)) {
                                                    Text(
                                                        text = resolved?.name ?: card.name,
                                                        style = MaterialTheme.typography.titleSmall,
                                                        fontWeight = FontWeight.SemiBold,
                                                        maxLines = 1,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                    card.reason?.let { reason ->
                                                        Text(
                                                            text = reason,
                                                            style = MaterialTheme.typography.bodySmall,
                                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                            maxLines = 2,
                                                            overflow = TextOverflow.Ellipsis,
                                                        )
                                                    }
                                                }
                                                if (resolved != null) {
                                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                                        TextButton(
                                                            onClick = {
                                                                onDismiss()
                                                                onSelectAppDetail(resolved)
                                                            },
                                                        ) {
                                                            Text("详情")
                                                        }
                                                        TextButton(onClick = { onToggleHome(resolved) }) {
                                                            Text(if (resolved.id in homeInstalledIds || resolved.homeKey in homeInstalledIds) "已在云居" else "加入")
                                                        }
                                                        FilledTonalButton(
                                                            onClick = {
                                                                onDismiss()
                                                                onLaunchApp(resolved)
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
                            }
                        }
                    }
                }
            }

            errorState?.let { err ->
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.55f),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = err.defaultMessage,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.weight(1f),
                        )
                        if (err == AssistantError.MEMBERSHIP_REQUIRED) {
                            TextButton(
                                onClick = {
                                    onDismiss()
                                    onOpenWallet()
                                },
                            ) {
                                Text("开通会员")
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = promptInput,
                    onValueChange = { if (it.length <= 2000) promptInput = it },
                    placeholder = { Text("描述你想找的应用…") },
                    enabled = !isStreaming,
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                if (isStreaming) {
                    OutlinedButton(onClick = { activeJob?.cancel() }) {
                        Text("停止")
                    }
                } else {
                    Button(
                        onClick = {
                            val trimmed = promptInput.trim()
                            if (trimmed.isEmpty()) return@Button
                            val nextMessages = persistedMessages + AssistantMessage(
                                id = UUID.randomUUID().toString(),
                                role = AssistantMessage.Role.USER,
                                content = trimmed,
                            )
                            promptInput = ""
                            historyStore.save(nextMessages, activeUser.id)
                            sendMessages(nextMessages)
                        },
                        enabled = promptInput.isNotBlank(),
                    ) {
                        Text("发送")
                    }
                }
            }
        }
    }
}
