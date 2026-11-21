package `fun`.yunle.apps.ui.account

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
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
import androidx.compose.ui.platform.LocalLocale
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import `fun`.yunle.apps.AppAppearance
import `fun`.yunle.apps.BoundedHttpsImageLoader
import `fun`.yunle.apps.account.AccountError
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AccountOverview
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.account.CaptchaImage
import `fun`.yunle.apps.account.VerificationAddress
import `fun`.yunle.apps.account.VerificationChallenge
import `fun`.yunle.apps.home.HomeLibrarySnapshot
import `fun`.yunle.apps.home.HomeSyncPhase
import `fun`.yunle.apps.home.HomeSyncResolution
import java.text.SimpleDateFormat
import java.util.Base64
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MeScreen(
    overview: AccountOverview,
    isRestoring: Boolean,
    notice: String?,
    homeAppCount: Int,
    hasRecentApps: Boolean,
    homeSnapshot: HomeLibrarySnapshot = HomeLibrarySnapshot(),
    homeSyncPhase: HomeSyncPhase = HomeSyncPhase.Idle,
    initialShowSettings: Boolean = false,
    onInitialSettingsConsumed: () -> Unit = {},
    appearance: AppAppearance,
    showRecent: Boolean,
    dockVisible: Boolean,
    screenshotFeedbackEnabled: Boolean,
    appVersionName: String,
    accounts: AccountStore,
    onAppearanceChange: (AppAppearance) -> Unit,
    onShowRecentChange: (Boolean) -> Unit,
    onDockVisibleChange: (Boolean) -> Unit,
    onScreenshotFeedbackChange: (Boolean) -> Unit,
    onSyncNow: () -> Unit = {},
    onSyncEnabledChange: (Boolean) -> Unit = {},
    onAutoSyncEnabledChange: (Boolean) -> Unit = {},
    onResolveSyncConflict: (HomeSyncResolution) -> Unit = {},
    onOpenHomeBackups: () -> Unit = {},
    onOpenLegacyMigration: () -> Unit = {},
    onOpenMyWorkshops: () -> Unit = {},
    onOpenWorkshopLookup: () -> Unit = {},
    onOpenMyReports: () -> Unit = {},
    onOpenWallet: () -> Unit = {},
    onOpenMyApplications: () -> Unit = {},
    onOpenAssistant: () -> Unit = {},
    gameBackConfirmEnabled: Boolean = true,
    onGameBackConfirmChange: (Boolean) -> Unit = {},
    onOpenAppCache: () -> Unit = {},
    onOpenSupportCenter: () -> Unit = {},
    onOpenHelpAndDiagnostics: () -> Unit = {},
    onClearRecent: () -> Unit,
    onOpenUrl: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var showLoginSheet by rememberSaveable { mutableStateOf(false) }
    var showAccountManagement by rememberSaveable { mutableStateOf(false) }
    var showProfileEdit by rememberSaveable { mutableStateOf(false) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var showAbout by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(initialShowSettings) {
        if (initialShowSettings) {
            showSettings = true
            onInitialSettingsConsumed()
        }
    }

    val activeUser = overview.activeUser

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "我",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics { heading() },
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(key = "identity_card") {
                Surface(
                    onClick = {
                        if (activeUser != null) {
                            showProfileEdit = true
                        } else {
                            showLoginSheet = true
                        }
                    },
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        if (activeUser != null) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(14.dp),
                            ) {
                                AccountAvatar(user = activeUser, size = 52.dp)
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = activeUser.displayName,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSurface,
                                    )
                                    Text(
                                        text = activeUser.detail,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    if (!activeUser.description.isNullOrBlank()) {
                                        Text(
                                            text = activeUser.description,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }
                                TextButton(onClick = { showProfileEdit = true }) {
                                    Text("编辑资料")
                                }
                            }
                        } else {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(14.dp),
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(52.dp)
                                        .clip(CircleShape)
                                        .background(MaterialTheme.colorScheme.secondaryContainer),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        text = "云",
                                        style = MaterialTheme.typography.titleLarge,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                    )
                                }
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "登录云乐坊",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSurface,
                                    )
                                    Text(
                                        text = "继续你的应用生活",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Button(onClick = { showLoginSheet = true }) {
                                    Text("登录")
                                }
                            }
                        }

                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = "云居中的应用",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                text = homeAppCount.toString(),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }

            if (isRestoring) {
                item(key = "restoring_row") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(
                            text = "正在检查登录状态…",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            if (!notice.isNullOrBlank()) {
                item(key = "notice_card") {
                    Surface(
                        shape = MaterialTheme.shapes.medium,
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = notice,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(onClick = { scope.launch { accounts.restore() } }) {
                                Text("重试")
                            }
                        }
                    }
                }
            }

            item(key = "section_primary") {
                MeSectionCard {
                    MeMenuRow(
                        title = "账号管理",
                        subtitle = if (overview.users.isEmpty()) "添加或切换本机保存的云乐坊账号" else "已保存 ${overview.users.size} 个账号",
                        onClick = { showAccountManagement = true },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "设置",
                        subtitle = "外观模式（${appearance.label}）、云居常用栏与最近使用",
                        onClick = { showSettings = true },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "关于云乐坊",
                        subtitle = "版本 $appVersionName · 隐私政策与服务条款",
                        onClick = { showAbout = true },
                    )
                }
            }

            item(key = "section_services") {
                MeSectionCard {
                    MeMenuRow(
                        title = "钱包与云乐坊会员",
                        subtitle = "查看云币余额、收支明细与会员权益",
                        onClick = onOpenWallet,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "AI 助手",
                        subtitle = "对话检索并发现适合你的云乐坊应用",
                        onClick = onOpenAssistant,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "个人工坊",
                        subtitle = "创建与管理我的工坊、审批访客及已加入工坊",
                        onClick = onOpenMyWorkshops,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "按编号打开工坊",
                        subtitle = "输入 6 位编号或工坊链接直达",
                        onClick = onOpenWorkshopLookup,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "我的举报",
                        subtitle = "查看应用或评价举报与审核结果",
                        onClick = onOpenMyReports,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "我的应用发布",
                        subtitle = "新建、编辑、投稿审核与管理云应用",
                        onClick = onOpenMyApplications,
                    )
                }
            }

            item(key = "section_support") {
                Text(
                    text = "支持",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .padding(start = 4.dp, top = 4.dp)
                        .semantics { heading() },
                )
                Spacer(modifier = Modifier.height(6.dp))
                MeSectionCard {
                    MeMenuRow(
                        title = "帮助与诊断日志",
                        subtitle = "查看使用文档、截图反馈开关与上报脱敏日志",
                        onClick = onOpenHelpAndDiagnostics,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    MeMenuRow(
                        title = "支持中心与反馈",
                        subtitle = "提交问题反馈、查看需求墙与我的反馈工单",
                        onClick = onOpenSupportCenter,
                    )
                }
            }
        }
    }

    if (showLoginSheet) {
        LoginModalSheet(
            accounts = accounts,
            onDismiss = { showLoginSheet = false },
            onOpenUrl = onOpenUrl,
        )
    }

    if (showAccountManagement) {
        AccountManagementModalSheet(
            overview = overview,
            accounts = accounts,
            onAddAccount = {
                showAccountManagement = false
                showLoginSheet = true
            },
            onDismiss = { showAccountManagement = false },
        )
    }

    if (showProfileEdit && activeUser != null) {
        ProfileEditDialog(
            user = activeUser,
            accounts = accounts,
            onDismiss = { showProfileEdit = false },
        )
    }

    if (showSettings) {
        SettingsModalSheet(
            signedIn = activeUser != null,
            appearance = appearance,
            showRecent = showRecent,
            dockVisible = dockVisible,
            screenshotFeedbackEnabled = screenshotFeedbackEnabled,
            hasRecentApps = hasRecentApps,
            homeSnapshot = homeSnapshot,
            homeSyncPhase = homeSyncPhase,
            onAppearanceChange = onAppearanceChange,
            onShowRecentChange = onShowRecentChange,
            onDockVisibleChange = onDockVisibleChange,
            onScreenshotFeedbackChange = onScreenshotFeedbackChange,
            onSyncNow = onSyncNow,
            onSyncEnabledChange = onSyncEnabledChange,
            onAutoSyncEnabledChange = onAutoSyncEnabledChange,
            onResolveSyncConflict = onResolveSyncConflict,
            onOpenHomeBackups = {
                showSettings = false
                onOpenHomeBackups()
            },
            onOpenLegacyMigration = {
                showSettings = false
                onOpenLegacyMigration()
            },
            gameBackConfirmEnabled = gameBackConfirmEnabled,
            onGameBackConfirmChange = onGameBackConfirmChange,
            onOpenAppCache = {
                showSettings = false
                onOpenAppCache()
            },
            onClearRecent = onClearRecent,
            onDismiss = { showSettings = false },
        )
    }

    if (showAbout) {
        AboutDialog(
            appVersionName = appVersionName,
            onOpenUrl = onOpenUrl,
            onDismiss = { showAbout = false },
        )
    }
}

@Composable
private fun MeSectionCard(content: @Composable () -> Unit) {
    Surface(
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            content()
        }
    }
}

@Composable
private fun MeMenuRow(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private enum class LoginMethod(val label: String) {
    PHONE("手机号"),
    EMAIL("邮箱"),
    PASSWORD("密码"),
}

private enum class PendingCaptchaAction {
    SEND_CODE,
    SIGN_IN,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LoginModalSheet(
    accounts: AccountStore,
    onDismiss: () -> Unit,
    onOpenUrl: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var method by rememberSaveable { mutableStateOf(LoginMethod.PHONE) }
    var identifier by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var code by rememberSaveable { mutableStateOf("") }
    var challenge by remember { mutableStateOf<VerificationChallenge?>(null) }
    var resendAtMillis by rememberSaveable { mutableLongStateOf(0L) }
    var nowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var isBusy by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var pendingCaptcha by remember { mutableStateOf<PendingCaptchaAction?>(null) }

    LaunchedEffect(resendAtMillis) {
        while (resendAtMillis > System.currentTimeMillis()) {
            nowMillis = System.currentTimeMillis()
            delay(500)
        }
        nowMillis = System.currentTimeMillis()
    }

    val remainingSeconds = ((resendAtMillis - nowMillis + 999) / 1000).coerceAtLeast(0)

    fun performAction(action: PendingCaptchaAction, captchaToken: String? = null) {
        if (isBusy) return
        isBusy = true
        errorText = null
        scope.launch {
            try {
                when (action) {
                    PendingCaptchaAction.SEND_CODE -> {
                        val address = when (method) {
                            LoginMethod.PHONE -> VerificationAddress.phoneInput(identifier)
                            LoginMethod.EMAIL -> VerificationAddress.emailInput(identifier)
                            LoginMethod.PASSWORD -> return@launch
                        }
                        val sent = accounts.sendVerification(address, captchaToken)
                        challenge = sent
                        resendAtMillis = System.currentTimeMillis() + 60_000L
                    }

                    PendingCaptchaAction.SIGN_IN -> {
                        if (method == LoginMethod.PASSWORD) {
                            accounts.passwordSignIn(
                                identifier = identifier,
                                password = password,
                                captcha = captchaToken,
                            )
                            onDismiss()
                        } else {
                            val currentChallenge = challenge
                                ?: throw AccountException(AccountError.INVALID_VERIFICATION)
                            accounts.verify(
                                challenge = currentChallenge,
                                code = code.trim(),
                                captcha = captchaToken,
                            )
                            onDismiss()
                        }
                    }
                }
            } catch (e: AccountException) {
                if (e.error == AccountError.CAPTCHA_REQUIRED) {
                    pendingCaptcha = action
                } else {
                    errorText = e.error.message
                }
            } catch (t: Throwable) {
                errorText = AccountError.messageFor(t)
            } finally {
                isBusy = false
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!isBusy) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = "登录云乐坊",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = "让有趣的应用，成为日常。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LoginMethod.entries.forEach { item ->
                    FilterChip(
                        selected = method == item,
                        onClick = {
                            if (!isBusy && method != item) {
                                method = item
                                identifier = ""
                                password = ""
                                code = ""
                                challenge = null
                                errorText = null
                            }
                        },
                        label = { Text(item.label) },
                    )
                }
            }

            OutlinedTextField(
                value = identifier,
                onValueChange = { value ->
                    identifier = if (method == LoginMethod.PHONE) {
                        VerificationAddress.normalizedPhoneInput(value)
                    } else {
                        value
                    }
                    challenge = null
                    errorText = null
                },
                label = {
                    Text(
                        when (method) {
                            LoginMethod.PHONE -> "中国大陆手机号 (+86)"
                            LoginMethod.EMAIL -> "邮箱地址"
                            LoginMethod.PASSWORD -> "用户名、邮箱或手机号"
                        },
                    )
                },
                singleLine = true,
                enabled = !isBusy,
                keyboardOptions = KeyboardOptions(
                    keyboardType = when (method) {
                        LoginMethod.PHONE -> KeyboardType.Phone
                        LoginMethod.EMAIL -> KeyboardType.Email
                        LoginMethod.PASSWORD -> KeyboardType.Text
                    },
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            if (method == LoginMethod.PASSWORD) {
                OutlinedTextField(
                    value = password,
                    onValueChange = {
                        password = it
                        errorText = null
                    },
                    label = { Text("密码") },
                    singleLine = true,
                    enabled = !isBusy,
                    visualTransformation = if (passwordVisible) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    trailingIcon = {
                        TextButton(onClick = { passwordVisible = !passwordVisible }) {
                            Text(if (passwordVisible) "隐藏" else "显示")
                        }
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = code,
                        onValueChange = {
                            code = it.filter(Char::isDigit).take(6)
                            errorText = null
                        },
                        label = { Text("6 位验证码") },
                        singleLine = true,
                        enabled = !isBusy,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        modifier = Modifier.weight(1f),
                    )
                    FilledTonalButton(
                        onClick = { performAction(PendingCaptchaAction.SEND_CODE) },
                        enabled = !isBusy && remainingSeconds == 0L && identifier.isNotBlank(),
                        modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                    ) {
                        Text(if (remainingSeconds > 0) "${remainingSeconds}s" else "获取验证码")
                    }
                }
                Text(
                    text = if (challenge != null) {
                        "验证码已发送，输入后即可登录或完成注册。"
                    } else {
                        "未注册的手机号或邮箱验证后将自动创建云乐坊账号。"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (!errorText.isNullOrBlank()) {
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.errorContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = errorText!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(12.dp),
                    )
                }
            }

            Button(
                onClick = { performAction(PendingCaptchaAction.SIGN_IN) },
                enabled = !isBusy && identifier.isNotBlank() &&
                    (if (method == LoginMethod.PASSWORD) password.isNotEmpty() else code.length == 6),
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 48.dp),
            ) {
                if (isBusy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(if (method == LoginMethod.PASSWORD) "登录" else "登录或注册")
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 16.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = { onOpenUrl("https://www.yunle.fun/docs/terms-of-service") }) {
                    Text("服务条款")
                }
                Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = { onOpenUrl("https://www.yunle.fun/docs/privacy-policy") }) {
                    Text("隐私政策")
                }
            }
        }
    }

    val captchaTarget = pendingCaptcha
    if (captchaTarget != null) {
        CaptchaDialog(
            accounts = accounts,
            onVerified = { token ->
                pendingCaptcha = null
                performAction(captchaTarget, captchaToken = token)
            },
            onDismiss = { pendingCaptcha = null },
        )
    }
}

@Composable
private fun CaptchaDialog(
    accounts: AccountStore,
    onVerified: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var challenge by remember { mutableStateOf<CaptchaImage?>(null) }
    var text by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun loadCaptcha() {
        busy = true
        error = null
        challenge = null
        text = ""
        scope.launch {
            try {
                challenge = accounts.captcha()
            } catch (t: Throwable) {
                error = AccountError.messageFor(t)
            } finally {
                busy = false
            }
        }
    }

    LaunchedEffect(Unit) {
        loadCaptcha()
    }

    val decodedBitmap = remember(challenge?.data) {
        val raw = challenge?.data ?: return@remember null
        val comma = raw.indexOf(',')
        if (comma <= 0) return@remember null
        runCatching {
            val bytes = Base64.getDecoder().decode(raw.substring(comma + 1))
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
        }.getOrNull()
    }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("安全验证") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("请输入图片中的字符以继续。")
                if (decodedBitmap != null) {
                    Image(
                        bitmap = decodedBitmap,
                        contentDescription = "图片验证码",
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(80.dp),
                    )
                }
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text("图片中的字符") },
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(onClick = { loadCaptcha() }, enabled = !busy) {
                    Text("更换图片")
                }
                if (!error.isNullOrBlank()) {
                    Text(
                        text = error!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val current = challenge ?: return@Button
                    busy = true
                    error = null
                    scope.launch {
                        try {
                            val token = accounts.verifyCaptcha(current.token, text.trim())
                            onVerified(token)
                        } catch (t: Throwable) {
                            error = AccountError.messageFor(t)
                        } finally {
                            busy = false
                        }
                    }
                },
                enabled = !busy && challenge != null && text.isNotBlank(),
            ) {
                Text("验证")
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
private fun AccountManagementModalSheet(
    overview: AccountOverview,
    accounts: AccountStore,
    onAddAccount: () -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmRemoveUser by remember { mutableStateOf<AccountUser?>(null) }

    ModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "账号管理",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = "切换账号会结束正在运行的云应用。每个账号的云居与 Web 存储分别独立保存。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            overview.users.forEach { user ->
                val isCurrent = user.id == overview.activeID
                Surface(
                    onClick = {
                        if (!busy && !isCurrent) {
                            busy = true
                            error = null
                            scope.launch {
                                try {
                                    accounts.select(user.id)
                                } catch (t: Throwable) {
                                    error = AccountError.messageFor(t)
                                } finally {
                                    busy = false
                                }
                            }
                        }
                    },
                    shape = MaterialTheme.shapes.large,
                    color = if (isCurrent) {
                        MaterialTheme.colorScheme.secondaryContainer
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerLow
                    },
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        AccountAvatar(user = user, size = 40.dp)
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = user.displayName + if (isCurrent) "（当前账号）" else "",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = user.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(
                            onClick = { confirmRemoveUser = user },
                            enabled = !busy,
                        ) {
                            Text("移除", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }

            FilledTonalButton(
                onClick = onAddAccount,
                enabled = !busy,
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 48.dp),
            ) {
                Text("添加账号")
            }

            if (overview.activeUser != null) {
                OutlinedButton(
                    onClick = { confirmRemoveUser = overview.activeUser },
                    enabled = !busy,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier
                        .fillMaxWidth()
                        .defaultMinSize(minHeight = 48.dp),
                ) {
                    Text("退出当前账号")
                }
            }

            if (!error.isNullOrBlank()) {
                Text(
                    text = error!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }

    val targetRemove = confirmRemoveUser
    if (targetRemove != null) {
        AlertDialog(
            onDismissRequest = { confirmRemoveUser = null },
            title = { Text("从此设备移除账号？") },
            text = {
                Text("将退出 ${targetRemove.displayName}，并结束正在运行的云应用。已保存的云居会保留。")
            },
            confirmButton = {
                Button(
                    onClick = {
                        confirmRemoveUser = null
                        busy = true
                        error = null
                        scope.launch {
                            try {
                                accounts.remove(targetRemove.id)
                            } catch (t: Throwable) {
                                error = AccountError.messageFor(t)
                            } finally {
                                busy = false
                            }
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("退出并移除")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemoveUser = null }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun ProfileEditDialog(
    user: AccountUser,
    accounts: AccountStore,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf(user.name ?: user.displayName) }
    var description by rememberSaveable { mutableStateOf(user.description.orEmpty()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("编辑个人资料") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    AccountAvatar(user = user, size = 44.dp)
                    Column {
                        Text(
                            text = user.displayName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = user.detail,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("昵称") },
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("个人简介") },
                    minLines = 2,
                    maxLines = 5,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (!error.isNullOrBlank()) {
                    Text(
                        text = error!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    busy = true
                    error = null
                    scope.launch {
                        try {
                            accounts.updateProfile(name.trim(), description.trim())
                            onDismiss()
                        } catch (t: Throwable) {
                            error = AccountError.messageFor(t)
                        } finally {
                            busy = false
                        }
                    }
                },
                enabled = !busy && name.trim().isNotEmpty(),
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
private fun SettingsModalSheet(
    signedIn: Boolean,
    appearance: AppAppearance,
    showRecent: Boolean,
    dockVisible: Boolean,
    screenshotFeedbackEnabled: Boolean,
    hasRecentApps: Boolean,
    homeSnapshot: HomeLibrarySnapshot,
    homeSyncPhase: HomeSyncPhase,
    onAppearanceChange: (AppAppearance) -> Unit,
    onShowRecentChange: (Boolean) -> Unit,
    onDockVisibleChange: (Boolean) -> Unit,
    onScreenshotFeedbackChange: (Boolean) -> Unit,
    onSyncNow: () -> Unit,
    onSyncEnabledChange: (Boolean) -> Unit,
    onAutoSyncEnabledChange: (Boolean) -> Unit,
    onResolveSyncConflict: (HomeSyncResolution) -> Unit,
    onOpenHomeBackups: () -> Unit = {},
    onOpenLegacyMigration: () -> Unit = {},
    gameBackConfirmEnabled: Boolean = true,
    onGameBackConfirmChange: (Boolean) -> Unit = {},
    onOpenAppCache: () -> Unit = {},
    onClearRecent: () -> Unit,
    onDismiss: () -> Unit,
) {
    var confirmClearRecent by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = "设置",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )

            Text(
                text = "显示模式",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppAppearance.entries.forEach { mode ->
                    FilterChip(
                        selected = appearance == mode,
                        onClick = { onAppearanceChange(mode) },
                        label = { Text(mode.label) },
                    )
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            SettingsToggleRow(
                title = "显示最近使用",
                subtitle = "在云居底部显示最近打开过的应用",
                checked = showRecent,
                onCheckedChange = onShowRecentChange,
            )
            SettingsToggleRow(
                title = "显示常用应用",
                subtitle = "在云居顶部固定最多 4 个常用应用",
                checked = dockVisible,
                onCheckedChange = onDockVisibleChange,
            )
            SettingsToggleRow(
                title = "截屏后显示反馈入口",
                subtitle = "截屏后短暂显示反馈按钮，不会读取或上传截图",
                checked = screenshotFeedbackEnabled,
                onCheckedChange = onScreenshotFeedbackChange,
            )
            SettingsToggleRow(
                title = "游戏返回防误触",
                subtitle = "对局内无法网页后退时，需连续按两次返回才会退出",
                checked = gameBackConfirmEnabled,
                onCheckedChange = onGameBackConfirmChange,
            )

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Text(
                text = "云居同步",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            val syncStatusText = when {
                !signedIn -> "登录云乐坊账号后可跨设备同步云居应用"
                !homeSnapshot.syncEnabled -> "当前账号已关闭云居云同步"
                homeSyncPhase is HomeSyncPhase.Syncing -> "正在同步云居…"
                homeSyncPhase is HomeSyncPhase.Conflict -> "云端与本地的云居版本存在冲突"
                homeSyncPhase is HomeSyncPhase.Failed -> homeSyncPhase.message
                homeSnapshot.hasPendingChanges -> "有本地变更等待同步"
                homeSnapshot.lastSyncedAtMillis != null -> {
                    val formatted = SimpleDateFormat("MM-dd HH:mm", LocalLocale.current.platformLocale)
                        .format(Date(homeSnapshot.lastSyncedAtMillis))
                    "已同步（$formatted）"
                }
                else -> "准备同步"
            }
            Text(
                text = syncStatusText,
                style = MaterialTheme.typography.bodySmall,
                color = when (homeSyncPhase) {
                    is HomeSyncPhase.Failed -> MaterialTheme.colorScheme.error
                    is HomeSyncPhase.Conflict -> MaterialTheme.colorScheme.primary
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
            )

            if (signedIn) {
                SettingsToggleRow(
                    title = "云居云同步",
                    subtitle = "在已登录此账号的设备间同步云居应用和常用栏",
                    checked = homeSnapshot.syncEnabled,
                    onCheckedChange = onSyncEnabledChange,
                )
                if (homeSnapshot.syncEnabled) {
                    SettingsToggleRow(
                        title = "自动同步",
                        subtitle = "调整云居内容后自动与云端同步",
                        checked = homeSnapshot.autoSyncEnabled,
                        onCheckedChange = onAutoSyncEnabledChange,
                    )
                    if (homeSyncPhase is HomeSyncPhase.Conflict) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedButton(
                                onClick = { onResolveSyncConflict(HomeSyncResolution.DEVICE) },
                                modifier = Modifier
                                    .weight(1f)
                                    .defaultMinSize(minHeight = 48.dp),
                            ) {
                                Text("保留此设备版本")
                            }
                            Button(
                                onClick = { onResolveSyncConflict(HomeSyncResolution.CLOUD) },
                                modifier = Modifier
                                    .weight(1f)
                                    .defaultMinSize(minHeight = 48.dp),
                            ) {
                                Text("使用云端版本")
                            }
                        }
                    } else {
                        FilledTonalButton(
                            onClick = onSyncNow,
                            enabled = homeSyncPhase !is HomeSyncPhase.Syncing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .defaultMinSize(minHeight = 48.dp),
                        ) {
                            Text(if (homeSyncPhase is HomeSyncPhase.Syncing) "同步中…" else "立即同步云居")
                        }
                    }
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            FilledTonalButton(
                onClick = onOpenAppCache,
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 48.dp),
            ) {
                Text("离线缓存管理")
            }

            FilledTonalButton(
                onClick = onOpenHomeBackups,
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 48.dp),
            ) {
                Text("云居备份与恢复")
            }

            FilledTonalButton(
                onClick = onOpenLegacyMigration,
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 48.dp),
            ) {
                Text("旧版数据导入")
            }

            OutlinedButton(
                onClick = { confirmClearRecent = true },
                enabled = hasRecentApps,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 48.dp),
            ) {
                Text("清空最近使用记录")
            }
        }
    }

    if (confirmClearRecent) {
        AlertDialog(
            onDismissRequest = { confirmClearRecent = false },
            title = { Text("清空最近使用记录？") },
            text = { Text("云居里的应用会继续保留。") },
            confirmButton = {
                Button(
                    onClick = {
                        confirmClearRecent = false
                        onClearRecent()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("清空记录")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmClearRecent = false }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun SettingsToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
internal fun AccountAvatar(
    user: AccountUser,
    size: Dp,
    modifier: Modifier = Modifier,
) {
    val picture = user.picture?.trim()?.takeIf { it.isNotEmpty() }
    val bitmap by produceState<Bitmap?>(initialValue = null, key1 = picture) {
        value = if (picture != null) BoundedHttpsImageLoader.loadBitmap(picture) else null
    }
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        val loaded = bitmap
        if (loaded != null) {
            Image(
                bitmap = loaded.asImageBitmap(),
                contentDescription = "${user.displayName} 头像",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Text(
                text = user.displayName.take(1).ifEmpty { "云" },
                style = if (size >= 48.dp) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

@Composable
private fun AboutDialog(
    appVersionName: String,
    onOpenUrl: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("关于云乐坊") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("在工坊发现云应用，把喜欢的带回云居。")
                Text(
                    text = "版本：$appVersionName",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TextButton(onClick = { onOpenUrl("https://www.yunle.fun/docs/privacy-policy") }) {
                        Text("隐私政策")
                    }
                    TextButton(onClick = { onOpenUrl("https://www.yunle.fun/docs/terms-of-service") }) {
                        Text("服务条款")
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("好")
            }
        },
    )
}
