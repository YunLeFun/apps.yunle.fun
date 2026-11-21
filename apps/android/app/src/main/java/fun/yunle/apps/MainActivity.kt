package `fun`.yunle.apps

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.RequiresApi
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.core.content.ContextCompat
import androidx.core.content.pm.PackageInfoCompat
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.home.HomeSyncPhase
import `fun`.yunle.apps.ui.AppRootScaffold
import `fun`.yunle.apps.ui.AppTab
import `fun`.yunle.apps.ui.account.MeScreen
import `fun`.yunle.apps.ui.assistant.AssistantModalSheet
import `fun`.yunle.apps.ui.catalog.ApplicationAcquisitionSheet
import `fun`.yunle.apps.ui.catalog.ApplicationShareSheet
import `fun`.yunle.apps.ui.catalog.CatalogFeedState
import `fun`.yunle.apps.ui.catalog.CatalogPaneMetadata
import `fun`.yunle.apps.ui.catalog.CatalogRoute
import `fun`.yunle.apps.ui.catalog.CatalogScreen
import `fun`.yunle.apps.ui.catalog.CatalogUiState
import `fun`.yunle.apps.ui.catalog.CatalogViewModel
import `fun`.yunle.apps.ui.catalog.DetailRoute
import `fun`.yunle.apps.ui.catalog.DetailScreen
import `fun`.yunle.apps.ui.catalog.DeveloperApplicationsSheet
import `fun`.yunle.apps.ui.catalog.ListDetailSceneStrategy
import `fun`.yunle.apps.ui.catalog.WorkshopScanOrLinkDialog
import `fun`.yunle.apps.diagnostics.DiagnosticLogLevel
import `fun`.yunle.apps.games.NativeGame
import `fun`.yunle.apps.games.NativeGameError
import `fun`.yunle.apps.games.NativeGameLaunchUrl
import `fun`.yunle.apps.games.NativeGameMode
import `fun`.yunle.apps.games.NativeGameRoomIntent
import `fun`.yunle.apps.games.NativePublicRoom
import `fun`.yunle.apps.ui.cache.ApplicationCacheSettingsSheet
import `fun`.yunle.apps.ui.community.ApplicationReviewsSheet
import `fun`.yunle.apps.ui.community.MyReportsSheet
import `fun`.yunle.apps.ui.games.GamesScreen
import `fun`.yunle.apps.ui.games.JoinRoomByCodeDialog
import `fun`.yunle.apps.ui.games.NativeGameResourcesSheet
import `fun`.yunle.apps.ui.games.NativeRoomCreationSheet
import `fun`.yunle.apps.ui.support.HelpAndDiagnosticsSheet
import `fun`.yunle.apps.ui.support.SupportCenterSheet
import `fun`.yunle.apps.ui.home.HomeBackupsSheet
import `fun`.yunle.apps.ui.home.HomeScreen
import `fun`.yunle.apps.ui.publishing.MyApplicationsSheet
import `fun`.yunle.apps.ui.theme.YunleTheme
import `fun`.yunle.apps.ui.wallet.WalletModalSheet
import `fun`.yunle.apps.ui.webruntime.WebProfileRecoverySheet
import `fun`.yunle.apps.ui.workshop.HomeWorkspacePickerSheet
import `fun`.yunle.apps.ui.workshop.MyWorkshopsSheet
import `fun`.yunle.apps.ui.workshop.PublicWorkshopSheet
import `fun`.yunle.apps.ui.workshop.WorkshopLookupDialog
import `fun`.yunle.apps.webruntime.HostAuthorizationError
import `fun`.yunle.apps.webruntime.HostAuthorizationException
import `fun`.yunle.apps.webruntime.HostSsoPolicy
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Android renders its 4-tab Material 3 shell and cloud application runtime host. */
class MainActivity : ComponentActivity() {
    private var launchedFromApp by mutableStateOf(false)
    private var externalDetailRequest by mutableStateOf<String?>(null)
    private var pendingDestination by mutableStateOf<NativeDestination?>(null)
    private var showScreenshotBanner by mutableStateOf(false)
    private var screenCaptureCallback: Any? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        YunleContainer.ensureInitialized(applicationContext)

        val initialDetailKey = if (savedInstanceState == null) {
            intent.getStringExtra(EXTRA_KEY)?.takeIf(CatalogApp::validKey)
        } else {
            null
        }
        launchedFromApp = savedInstanceState?.getBoolean(KEY_LAUNCHED_FROM_APP)
            ?: (initialDetailKey != null)
        if (savedInstanceState == null && initialDetailKey == null) {
            handleIncomingIntent(intent)
        }

        val (appVersionName, appVersionCode) = runCatching {
            val info = packageManager.getPackageInfo(packageName, 0)
            (info.versionName ?: "1.0") to PackageInfoCompat.getLongVersionCode(info).toString()
        }.getOrDefault("1.0" to "1")

        setContent {
            val appearance by YunleContainer.preferences.appearance.collectAsStateWithLifecycle()
            val showRecent by YunleContainer.preferences.showRecent.collectAsStateWithLifecycle()
            val screenshotFeedbackEnabled by YunleContainer.preferences.screenshotFeedbackEnabled.collectAsStateWithLifecycle()
            val gameBackConfirmEnabled by YunleContainer.preferences.gameBackConfirmEnabled.collectAsStateWithLifecycle()

            val darkTheme = when (appearance) {
                AppAppearance.SYSTEM -> isSystemInDarkTheme()
                AppAppearance.LIGHT -> false
                AppAppearance.DARK -> true
            }

            YunleTheme(darkTheme = darkTheme) {
                val viewModel: CatalogViewModel = viewModel()
                val uiState by viewModel.uiState.collectAsStateWithLifecycle()
                val accountOverview by YunleContainer.accounts.overview.collectAsStateWithLifecycle()
                val isRestoringAccount by YunleContainer.accounts.isRestoring.collectAsStateWithLifecycle()
                val accountNotice by YunleContainer.accounts.notice.collectAsStateWithLifecycle()
                val homeSnapshot by YunleContainer.homeLibrary.snapshot.collectAsStateWithLifecycle()
                val homeStorageError by YunleContainer.homeLibrary.storageError.collectAsStateWithLifecycle()
                val homeSyncPhase by YunleContainer.homeSync.phase.collectAsStateWithLifecycle()
                val runningSessions by HostSession.runningSessions.collectAsStateWithLifecycle()
                val nativeGames by YunleContainer.nativeGameCatalogStore.games.collectAsStateWithLifecycle()
                val recentGameHistory by YunleContainer.nativeGameHistoryStore.entries.collectAsStateWithLifecycle()
                val scope = rememberCoroutineScope()

                var selectedTab by rememberSaveable {
                    mutableStateOf(if (initialDetailKey != null) AppTab.WORKSHOP else AppTab.HOME)
                }
                var openSyncSettingsInMe by rememberSaveable { mutableStateOf(false) }
                var showHomeBackups by rememberSaveable { mutableStateOf(false) }
                var showMyWorkshops by rememberSaveable { mutableStateOf(false) }
                var showWorkshopLookup by rememberSaveable { mutableStateOf(false) }
                var showWorkspacePicker by rememberSaveable { mutableStateOf(false) }
                var showMyReports by rememberSaveable { mutableStateOf(false) }
                var showScanOrLink by rememberSaveable { mutableStateOf(false) }
                var showCreateRoom by rememberSaveable { mutableStateOf(false) }
                var showJoinRoom by rememberSaveable { mutableStateOf(false) }
                var showGameResources by rememberSaveable { mutableStateOf(false) }
                var showAppCacheSettings by rememberSaveable { mutableStateOf(false) }
                var showAssistant by rememberSaveable { mutableStateOf(false) }
                var showWallet by rememberSaveable { mutableStateOf(false) }
                var showMyApplications by rememberSaveable { mutableStateOf(false) }
                var showSupportCenter by rememberSaveable { mutableStateOf(false) }
                var showHelpAndDiagnostics by rememberSaveable { mutableStateOf(false) }
                var publicRooms by remember { mutableStateOf<List<NativePublicRoom>>(emptyList()) }
                var isLoadingRooms by remember { mutableStateOf(false) }
                var roomsError by remember { mutableStateOf<String?>(null) }
                var pendingGameLaunch by remember { mutableStateOf<Pair<NativeGame, NativeGameMode>?>(null) }
                var activePublicWorkshopId by rememberSaveable { mutableStateOf<String?>(null) }
                var activeDeveloperLogin by rememberSaveable { mutableStateOf<String?>(null) }
                var activeWorkspaceId by rememberSaveable { mutableStateOf<String?>(null) }
                var activeWorkspaceName by rememberSaveable { mutableStateOf<String?>(null) }
                var activeWorkshopApps by remember { mutableStateOf<List<CatalogApp>?>(null) }
                var recoveringApp by remember { mutableStateOf<CatalogApp?>(null) }
                var reviewsApp by remember { mutableStateOf<CatalogApp?>(null) }
                var acquiringApp by remember { mutableStateOf<CatalogApp?>(null) }
                var sharingApp by remember { mutableStateOf<CatalogApp?>(null) }
                var transientDetailApps by remember { mutableStateOf<Map<String, CatalogApp>>(emptyMap()) }
                var linkDialogDestination by remember { mutableStateOf<NativeDestination?>(null) }

                val startRoute: NavKey = remember {
                    if (initialDetailKey != null) DetailRoute(initialDetailKey) else CatalogRoute
                }
                val workshopBackStack = rememberNavBackStack(startRoute)

                LaunchedEffect(Unit) {
                    YunleContainer.accounts.prepareInitialRestore()
                    YunleContainer.accounts.consumeInitialRestore()
                }

                suspend fun refreshPublicRooms() {
                    isLoadingRooms = true
                    roomsError = null
                    val res = runCatching { YunleContainer.publicRoomService.rooms() }
                    isLoadingRooms = false
                    res.fold(
                        onSuccess = { publicRooms = it },
                        onFailure = { roomsError = NativeGameError.message(it) },
                    )
                }

                fun openNativeGame(game: NativeGame, mode: NativeGameMode) {
                    if (mode.requiresLogin && accountOverview.activeUser?.isUsable != true) {
                        pendingGameLaunch = game to mode
                        selectedTab = AppTab.ME
                        return
                    }
                    val base = runCatching { game.launchUrl(mode) }.getOrNull() ?: return
                    val launchUrl = NativeGameLaunchUrl.addingContext(
                        raw = base,
                        launchId = UUID.randomUUID(),
                        gameId = game.gameId,
                        modeId = mode.id,
                    ) ?: return
                    val options = JSONObject()
                        .put("url", launchUrl)
                        .put("title", game.name)
                        .put("orientation", mode.orientation ?: "system")
                        .put("displayMode", "immersive")
                        .put("trustedHosts", JSONArray().put("play.yunle.fun"))
                        .put(
                            "app",
                            JSONObject()
                                .put("id", game.appId)
                                .put("slug", game.gameId)
                                .put("name", game.name)
                                .put("emoji", "🎮")
                                .put("description", game.description),
                        )
                    HostSession.openRaw(this@MainActivity, game.appId, options.toString())
                }

                fun openGameRoom(intent: NativeGameRoomIntent) {
                    val options = JSONObject()
                        .put("url", intent.url)
                        .put("title", "联机房间 #${intent.inviteCode}")
                        .put("displayMode", "titlebar")
                        .put("trustedHosts", JSONArray().put("play.yunle.fun"))
                        .put(
                            "app",
                            JSONObject()
                                .put("id", "play")
                                .put("slug", "play")
                                .put("name", "云乐坊游戏大厅")
                                .put("emoji", "🎮"),
                        )
                    HostSession.openRaw(this@MainActivity, "play-room-${intent.inviteCode}", options.toString())
                }

                LaunchedEffect(selectedTab) {
                    if (selectedTab == AppTab.GAMES) {
                        launch { YunleContainer.nativeGameCatalogStore.load() }
                        launch { refreshPublicRooms() }
                    }
                }

                LaunchedEffect(accountOverview.activeID, accountOverview.activeUser) {
                    val pending = pendingGameLaunch
                    if (pending != null && accountOverview.activeUser?.isUsable == true) {
                        pendingGameLaunch = null
                        openNativeGame(pending.first, pending.second)
                    }
                }

                LaunchedEffect(accountOverview.activeID) {
                    activeWorkspaceId = null
                    activeWorkspaceName = null
                    activeWorkshopApps = null
                }

                LaunchedEffect(uiState.feed) {
                    val loaded = uiState.feed as? CatalogFeedState.Loaded ?: return@LaunchedEffect
                    YunleContainer.updateCatalogApps(loaded.apps)
                }

                val requestedKey = externalDetailRequest
                LaunchedEffect(requestedKey) {
                    if (requestedKey != null) {
                        selectedTab = AppTab.WORKSHOP
                        pushDetailRoute(workshopBackStack, requestedKey)
                        externalDetailRequest = null
                    }
                }

                fun handleNativeDestination(destination: NativeDestination) {
                    when (destination) {
                        is NativeDestination.Application -> {
                            selectedTab = AppTab.WORKSHOP
                            pushDetailRoute(workshopBackStack, destination.key)
                        }
                        is NativeDestination.Workshop -> {
                            activePublicWorkshopId = destination.id
                        }
                        is NativeDestination.Developer -> {
                            activeDeveloperLogin = destination.login
                        }
                        else -> {
                            linkDialogDestination = destination
                        }
                    }
                }

                val incomingDestination = pendingDestination
                LaunchedEffect(incomingDestination) {
                    if (incomingDestination != null) {
                        handleNativeDestination(incomingDestination)
                        pendingDestination = null
                    }
                }

                BackHandler(
                    enabled = !launchedFromApp && selectedTab != AppTab.HOME &&
                        !(selectedTab == AppTab.WORKSHOP && workshopBackStack.size > 1),
                ) {
                    selectedTab = AppTab.HOME
                }

                fun openApplication(app: CatalogApp) {
                    YunleContainer.homeLibrary.recordUse(app)
                    HostSession.open(this@MainActivity, app)
                    if (launchedFromApp) finish()
                }

                fun openTransientAppDetail(app: CatalogApp) {
                    transientDetailApps = transientDetailApps + (app.id to app) + (app.key to app)
                    selectedTab = AppTab.WORKSHOP
                    pushDetailRoute(workshopBackStack, app.id)
                }

                BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                    val useNavigationRail = maxWidth >= 840.dp
                    AppRootScaffold(
                        selectedTab = selectedTab,
                        useNavigationRail = useNavigationRail,
                        onSelectTab = { selectedTab = it },
                    ) {
                        when (selectedTab) {
                            AppTab.HOME -> HomeScreen(
                                snapshot = homeSnapshot,
                                storageError = homeStorageError,
                                syncPhase = homeSyncPhase,
                                showRecent = showRecent,
                                minimizedAppName = uiState.minimizedAppName,
                                activeUser = accountOverview.activeUser,
                                onBrowseWorkshop = { selectedTab = AppTab.WORKSHOP },
                                onResumeSession = { HostSession.resume(this@MainActivity) },
                                onLaunchOrDetail = { app ->
                                    if (app.launchUrl != null) {
                                        openApplication(app)
                                    } else {
                                        openTransientAppDetail(app)
                                    }
                                },
                                onOpenDetail = { app ->
                                    openTransientAppDetail(app)
                                },
                                onAddApp = YunleContainer.homeLibrary::add,
                                onTogglePin = { app, pinned ->
                                    YunleContainer.homeLibrary.setPinned(app, pinned)
                                },
                                onSetPinnedBatch = YunleContainer.homeLibrary::setPinned,
                                onRemoveApp = { app ->
                                    YunleContainer.homeLibrary.remove(app)
                                },
                                onReorderDock = { keys ->
                                    YunleContainer.homeLibrary.reorder(keys, inDock = true)
                                },
                                onReorderItems = YunleContainer.homeLibrary::reorderItems,
                                onCreateFolder = { name, keys, anchor ->
                                    YunleContainer.homeLibrary.createFolder(name, keys, anchor)
                                },
                                onAddToFolder = YunleContainer.homeLibrary::addToFolder,
                                onRemoveFromFolder = YunleContainer.homeLibrary::removeFromFolder,
                                onRenameFolder = YunleContainer.homeLibrary::renameFolder,
                                onReorderFolder = YunleContainer.homeLibrary::reorderFolder,
                                onDissolveFolder = YunleContainer.homeLibrary::dissolveFolder,
                                onRetryStorage = {
                                    YunleContainer.homeLibrary.activateAccount(accountOverview.activeID)
                                    val loaded = uiState.feed as? CatalogFeedState.Loaded
                                    if (loaded != null) {
                                        YunleContainer.updateCatalogApps(loaded.apps)
                                    }
                                    YunleContainer.homeSync.recheck()
                                },
                                onSyncNow = { YunleContainer.homeSync.synchronize() },
                                onResolveSyncConflict = { resolution ->
                                    YunleContainer.homeSync.resolve(resolution)
                                },
                                onOpenSyncSettings = {
                                    openSyncSettingsInMe = true
                                    selectedTab = AppTab.ME
                                },
                                runningSessions = runningSessions,
                                onResumeRunningSession = { sessionKey ->
                                    HostSession.resumeSession(this@MainActivity, sessionKey)
                                },
                                onCloseRunningSession = { sessionKey ->
                                    HostSession.closeSession(sessionKey)
                                },
                                activeWorkspaceName = activeWorkspaceName,
                                onOpenWorkspacePicker = { showWorkspacePicker = true },
                                workshopApps = activeWorkshopApps,
                                onExitWorkspace = {
                                    activeWorkspaceId = null
                                    activeWorkspaceName = null
                                    activeWorkshopApps = null
                                },
                            )

                            AppTab.GAMES -> GamesScreen(
                                uiState = uiState,
                                onResumeSession = { HostSession.resume(this@MainActivity) },
                                onLaunchGame = { app -> openApplication(app) },
                                onSelectAppDetail = { app ->
                                    selectedTab = AppTab.WORKSHOP
                                    pushDetailRoute(workshopBackStack, app.id)
                                },
                                onRetry = viewModel::retry,
                                nativeGames = nativeGames,
                                recentHistory = recentGameHistory,
                                publicRooms = publicRooms,
                                isLoadingRooms = isLoadingRooms,
                                roomsError = roomsError,
                                onLaunchNativeGame = ::openNativeGame,
                                onJoinPublicRoom = ::openGameRoom,
                                onRefreshRooms = { scope.launch { refreshPublicRooms() } },
                                onCreateRoom = { showCreateRoom = true },
                                onJoinByCode = { showJoinRoom = true },
                                onManageGameResources = { showGameResources = true },
                            )

                            AppTab.WORKSHOP -> WorkshopTabContent(
                                backStack = workshopBackStack,
                                uiState = uiState,
                                homeInstalledIds = remember(homeSnapshot, uiState.feed) {
                                    val raw = homeSnapshot.installedIds.toSet() + homeSnapshot.dockIds.toSet()
                                    val loaded = (uiState.feed as? CatalogFeedState.Loaded)?.apps.orEmpty()
                                    raw + loaded.filter { homeSnapshot.contains(it) }.map { it.id }
                                },
                                activeUser = accountOverview.activeUser,
                                transientApps = transientDetailApps,
                                viewModel = viewModel,
                                onOpenAccount = { selectedTab = AppTab.ME },
                                onResumeSession = { HostSession.resume(this@MainActivity) },
                                onLaunchApp = ::openApplication,
                                onToggleHome = { app ->
                                    if (YunleContainer.homeLibrary.contains(app)) {
                                        YunleContainer.homeLibrary.remove(app)
                                    } else {
                                        YunleContainer.homeLibrary.add(app)
                                    }
                                },
                                onOpenWebDetails = { app ->
                                    openInCustomTab(
                                        this@MainActivity,
                                        Uri.Builder()
                                            .scheme("https")
                                            .authority("apps.yunle.fun")
                                            .appendPath("app")
                                            .appendPath(app.key)
                                            .build(),
                                    )
                                },
                                onOpenAppData = if (accountOverview.activeUser?.isUsable == true) {
                                    { app -> recoveringApp = app }
                                } else {
                                    null
                                },
                                onOpenMyWorkshops = { showMyWorkshops = true },
                                onOpenWorkshopLookup = { showWorkshopLookup = true },
                                onOpenScanOrLink = { showScanOrLink = true },
                                onOpenAssistant = { showAssistant = true },
                                onOpenReviews = { app -> reviewsApp = app },
                                onOpenDeveloper = { login -> activeDeveloperLogin = login },
                                onAcquireApp = { app -> acquiringApp = app },
                                onShareApp = { app -> sharingApp = app },
                                onFinishActivity = ::finish,
                            )

                            AppTab.ME -> MeScreen(
                                overview = accountOverview,
                                isRestoring = isRestoringAccount,
                                notice = accountNotice,
                                homeAppCount = homeSnapshot.applications.size,
                                hasRecentApps = homeSnapshot.recentEntries.isNotEmpty(),
                                homeSnapshot = homeSnapshot,
                                homeSyncPhase = homeSyncPhase,
                                initialShowSettings = openSyncSettingsInMe,
                                onInitialSettingsConsumed = { openSyncSettingsInMe = false },
                                appearance = appearance,
                                showRecent = showRecent,
                                dockVisible = homeSnapshot.dockVisible,
                                screenshotFeedbackEnabled = screenshotFeedbackEnabled,
                                appVersionName = appVersionName,
                                accounts = YunleContainer.accounts,
                                onAppearanceChange = YunleContainer.preferences::setAppearance,
                                onShowRecentChange = YunleContainer.preferences::setShowRecent,
                                onDockVisibleChange = YunleContainer.homeLibrary::setDockVisible,
                                onScreenshotFeedbackChange = YunleContainer.preferences::setScreenshotFeedbackEnabled,
                                onSyncNow = { YunleContainer.homeSync.synchronize() },
                                onSyncEnabledChange = YunleContainer.homeLibrary::setSyncEnabled,
                                onAutoSyncEnabledChange = YunleContainer.homeLibrary::setAutoSyncEnabled,
                                onResolveSyncConflict = { resolution ->
                                    YunleContainer.homeSync.resolve(resolution)
                                },
                                onOpenHomeBackups = { showHomeBackups = true },
                                onOpenMyWorkshops = { showMyWorkshops = true },
                                onOpenWorkshopLookup = { showWorkshopLookup = true },
                                onOpenMyReports = { showMyReports = true },
                                onOpenWallet = { showWallet = true },
                                onOpenMyApplications = { showMyApplications = true },
                                onOpenAssistant = { showAssistant = true },
                                gameBackConfirmEnabled = gameBackConfirmEnabled,
                                onGameBackConfirmChange = YunleContainer.preferences::setGameBackConfirmEnabled,
                                onOpenAppCache = { showAppCacheSettings = true },
                                onOpenSupportCenter = { showSupportCenter = true },
                                onOpenHelpAndDiagnostics = { showHelpAndDiagnostics = true },
                                onClearRecent = YunleContainer.homeLibrary::clearRecent,
                                onOpenUrl = { url -> openInCustomTab(this@MainActivity, Uri.parse(url)) },
                            )
                        }
                    }

                    recoveringApp?.let { targetApp ->
                        WebProfileRecoverySheet(
                            app = targetApp,
                            accounts = YunleContainer.accounts,
                            webProfiles = YunleContainer.webProfiles,
                            onCloseRuntime = { HostSession.closeAll() },
                            onDismiss = { recoveringApp = null },
                        )
                    }

                    if (showHomeBackups) {
                        HomeBackupsSheet(
                            accounts = YunleContainer.accounts,
                            homeLibrary = YunleContainer.homeLibrary,
                            onDismiss = { showHomeBackups = false },
                        )
                    }

                    if (showMyWorkshops) {
                        MyWorkshopsSheet(
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.workshopService,
                            onOpenWorkshop = { workshopId ->
                                showMyWorkshops = false
                                activePublicWorkshopId = workshopId
                            },
                            onDismiss = { showMyWorkshops = false },
                        )
                    }

                    if (showWorkshopLookup) {
                        WorkshopLookupDialog(
                            onOpenWorkshop = { workshopId ->
                                showWorkshopLookup = false
                                activePublicWorkshopId = workshopId
                            },
                            onDismiss = { showWorkshopLookup = false },
                        )
                    }

                    if (showWorkspacePicker) {
                        HomeWorkspacePickerSheet(
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.workshopService,
                            activeWorkshopId = activeWorkspaceId,
                            onSelectPersonal = {
                                activeWorkspaceId = null
                                activeWorkspaceName = null
                                activeWorkshopApps = null
                                showWorkspacePicker = false
                            },
                            onSelectWorkshop = { workshop, page ->
                                activeWorkspaceId = workshop.id
                                activeWorkspaceName = workshop.name
                                activeWorkshopApps = page.apps
                                showWorkspacePicker = false
                            },
                            onDismiss = { showWorkspacePicker = false },
                        )
                    }

                    if (showScanOrLink) {
                        WorkshopScanOrLinkDialog(
                            onDestination = ::handleNativeDestination,
                            onWorkshopCode = { code -> activePublicWorkshopId = code },
                            onDismiss = { showScanOrLink = false },
                        )
                    }

                    activePublicWorkshopId?.let { workshopId ->
                        PublicWorkshopSheet(
                            workshopId = workshopId,
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.workshopService,
                            onLaunchApp = ::openApplication,
                            onSelectAppDetail = ::openTransientAppDetail,
                            onNavigateToMe = {
                                activePublicWorkshopId = null
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { activePublicWorkshopId = null },
                        )
                    }

                    activeDeveloperLogin?.let { login ->
                        DeveloperApplicationsSheet(
                            login = login,
                            service = YunleContainer.developerProfileService,
                            onLaunchApp = ::openApplication,
                            onSelectAppDetail = ::openTransientAppDetail,
                            onDismiss = { activeDeveloperLogin = null },
                        )
                    }

                    reviewsApp?.let { targetApp ->
                        ApplicationReviewsSheet(
                            app = targetApp,
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.communityService,
                            onNavigateToMe = {
                                reviewsApp = null
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { reviewsApp = null },
                        )
                    }

                    if (showMyReports) {
                        MyReportsSheet(
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.communityService,
                            onNavigateToMe = {
                                showMyReports = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showMyReports = false },
                        )
                    }

                    acquiringApp?.let { targetApp ->
                        ApplicationAcquisitionSheet(
                            app = targetApp,
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.acquisitionService,
                            onLaunchAuthorized = ::openApplication,
                            onNavigateToMe = {
                                acquiringApp = null
                                selectedTab = AppTab.ME
                            },
                            onOpenWallet = {
                                acquiringApp = null
                                showWallet = true
                            },
                            onDismiss = { acquiringApp = null },
                        )
                    }

                    sharingApp?.let { targetApp ->
                        ApplicationShareSheet(
                            app = targetApp,
                            onDismiss = { sharingApp = null },
                        )
                    }

                    if (showCreateRoom) {
                        NativeRoomCreationSheet(
                            games = nativeGames,
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.roomCreationService,
                            onRoomCreated = ::openGameRoom,
                            onNavigateToMe = {
                                showCreateRoom = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showCreateRoom = false },
                        )
                    }

                    if (showJoinRoom) {
                        JoinRoomByCodeDialog(
                            onJoinRoom = ::openGameRoom,
                            onDismiss = { showJoinRoom = false },
                        )
                    }

                    if (showGameResources) {
                        val playProfileKey = remember(accountOverview.activeID) {
                            YunleContainer.selectWebProfile("play", "https://play.yunle.fun/").profileName
                        }
                        NativeGameResourcesSheet(
                            games = nativeGames,
                            profileKey = playProfileKey,
                            cacheStore = YunleContainer.gameResourceCache,
                            onDismiss = { showGameResources = false },
                        )
                    }

                    if (showAppCacheSettings) {
                        val loadedApps = (uiState.feed as? CatalogFeedState.Loaded)?.apps.orEmpty()
                        ApplicationCacheSettingsSheet(
                            catalogApps = loadedApps,
                            cacheStore = YunleContainer.applicationCacheStore,
                            onDismiss = { showAppCacheSettings = false },
                        )
                    }

                    if (showAssistant) {
                        val loadedApps = (uiState.feed as? CatalogFeedState.Loaded)?.apps.orEmpty()
                        val installedIds = remember(homeSnapshot, loadedApps) {
                            val raw = homeSnapshot.installedIds.toSet() + homeSnapshot.dockIds.toSet()
                            raw + loadedApps.filter { homeSnapshot.contains(it) }.map { it.id }
                        }
                        AssistantModalSheet(
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.assistantService,
                            historyStore = YunleContainer.assistantHistoryStore,
                            catalogApps = loadedApps,
                            homeInstalledIds = installedIds,
                            onLaunchApp = ::openApplication,
                            onToggleHome = { app ->
                                if (YunleContainer.homeLibrary.contains(app)) {
                                    YunleContainer.homeLibrary.remove(app)
                                } else {
                                    YunleContainer.homeLibrary.add(app)
                                }
                            },
                            onSelectAppDetail = ::openTransientAppDetail,
                            onOpenWallet = { showWallet = true },
                            onNavigateToMe = {
                                showAssistant = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showAssistant = false },
                        )
                    }

                    if (showWallet) {
                        WalletModalSheet(
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.walletService,
                            journal = YunleContainer.purchaseJournal,
                            onOpenCheckoutUrl = { url -> openInCustomTab(this@MainActivity, Uri.parse(url)) },
                            onNavigateToMe = {
                                showWallet = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showWallet = false },
                        )
                    }

                    if (showMyApplications) {
                        MyApplicationsSheet(
                            accounts = YunleContainer.accounts,
                            service = YunleContainer.publishingService,
                            draftVault = YunleContainer.draftVault,
                            onLaunchPreview = ::openApplication,
                            onNavigateToMe = {
                                showMyApplications = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showMyApplications = false },
                        )
                    }

                    if (showSupportCenter) {
                        SupportCenterSheet(
                            accounts = YunleContainer.accounts,
                            supportService = YunleContainer.supportService,
                            ticketService = YunleContainer.supportTicketClient,
                            shareHistory = YunleContainer.sharedFeedbackHistory,
                            appVersionName = appVersionName,
                            onOpenUrl = { url -> openInCustomTab(this@MainActivity, Uri.parse(url)) },
                            onNavigateToMe = {
                                showSupportCenter = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showSupportCenter = false },
                        )
                    }

                    if (showHelpAndDiagnostics) {
                        HelpAndDiagnosticsSheet(
                            accounts = YunleContainer.accounts,
                            logs = YunleContainer.diagnosticLogStore,
                            uploadStore = YunleContainer.diagnosticUploadStore,
                            screenshotFeedbackEnabled = screenshotFeedbackEnabled,
                            onScreenshotFeedbackChange = YunleContainer.preferences::setScreenshotFeedbackEnabled,
                            appVersionName = appVersionName,
                            appVersionCode = appVersionCode,
                            onOpenSupportCenter = { showSupportCenter = true },
                            onOpenUrl = { url -> openInCustomTab(this@MainActivity, Uri.parse(url)) },
                            onNavigateToMe = {
                                showHelpAndDiagnostics = false
                                selectedTab = AppTab.ME
                            },
                            onDismiss = { showHelpAndDiagnostics = false },
                        )
                    }

                    if (showScreenshotBanner) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .statusBarsPadding()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            contentAlignment = Alignment.TopCenter,
                        ) {
                            Surface(
                                shape = RoundedCornerShape(16.dp),
                                tonalElevation = 6.dp,
                                shadowElevation = 6.dp,
                                color = MaterialTheme.colorScheme.inverseSurface,
                                contentColor = MaterialTheme.colorScheme.inverseOnSurface,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Text(
                                        text = "检测到截屏，需要提交反馈吗？",
                                        style = MaterialTheme.typography.bodyMedium,
                                        modifier = Modifier.weight(1f),
                                    )
                                    TextButton(
                                        onClick = {
                                            showScreenshotBanner = false
                                            showSupportCenter = true
                                        },
                                    ) {
                                        Text(
                                            text = "去反馈",
                                            color = MaterialTheme.colorScheme.inversePrimary,
                                        )
                                    }
                                    TextButton(onClick = { showScreenshotBanner = false }) {
                                        Text(
                                            text = "忽略",
                                            color = MaterialTheme.colorScheme.inverseOnSurface,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    linkDialogDestination?.let { destination ->
                        IncomingDestinationDialog(
                            destination = destination,
                            activeUser = accountOverview.activeUser,
                            onOpenWeb = { url ->
                                linkDialogDestination = null
                                openInCustomTab(this@MainActivity, Uri.parse(url))
                            },
                            onNavigateToMe = {
                                linkDialogDestination = null
                                selectedTab = AppTab.ME
                            },
                            onDeliverCrossAppCallback = { callbackUrl ->
                                openCrossAppCallback(this@MainActivity, callbackUrl)
                            },
                            onDismiss = { linkDialogDestination = null },
                        )
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerScreenCaptureDetection()
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            unregisterScreenCaptureDetection()
        }
        super.onStop()
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun registerScreenCaptureDetection() {
        if (screenCaptureCallback != null) return
        val callback = ScreenCaptureCallback {
            YunleContainer.diagnosticLogStore.record(
                DiagnosticLogLevel.INFO,
                "Screen capture detected on main shell",
            )
            if (YunleContainer.preferences.screenshotFeedbackEnabled.value) {
                showScreenshotBanner = true
            }
        }
        screenCaptureCallback = callback
        runCatching { registerScreenCaptureCallback(ContextCompat.getMainExecutor(this), callback) }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun unregisterScreenCaptureDetection() {
        val callback = screenCaptureCallback as? ScreenCaptureCallback ?: return
        screenCaptureCallback = null
        runCatching { unregisterScreenCaptureCallback(callback) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val detailKey = intent?.getStringExtra(EXTRA_KEY)?.takeIf(CatalogApp::validKey)
        if (detailKey != null) {
            launchedFromApp = true
            externalDetailRequest = detailKey
            return
        }
        val rawData = intent?.dataString ?: return
        NativeDeepLinkRouter.parse(rawData)?.let { destination ->
            pendingDestination = destination
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(KEY_LAUNCHED_FROM_APP, launchedFromApp)
        super.onSaveInstanceState(outState)
    }

    companion object {
        private const val EXTRA_KEY = "fun.yunle.apps.detail"
        private const val KEY_LAUNCHED_FROM_APP = "fun.yunle.apps.launched_from_app"

        internal fun detailIntent(context: Context, key: String): Intent =
            Intent(context, MainActivity::class.java).putExtra(EXTRA_KEY, key)
    }
}

private fun pushDetailRoute(backStack: NavBackStack<NavKey>, appId: String) {
    val top = backStack.lastOrNull()
    if (top is DetailRoute) {
        backStack[backStack.lastIndex] = DetailRoute(appId)
    } else {
        backStack.add(DetailRoute(appId))
    }
}

@Composable
private fun WorkshopTabContent(
    backStack: NavBackStack<NavKey>,
    uiState: CatalogUiState,
    homeInstalledIds: Set<String>,
    activeUser: AccountUser?,
    transientApps: Map<String, CatalogApp> = emptyMap(),
    viewModel: CatalogViewModel,
    onOpenAccount: () -> Unit,
    onResumeSession: () -> Unit,
    onLaunchApp: (CatalogApp) -> Unit,
    onToggleHome: (CatalogApp) -> Unit,
    onOpenWebDetails: (CatalogApp) -> Unit,
    onOpenAppData: ((CatalogApp) -> Unit)? = null,
    onOpenMyWorkshops: (() -> Unit)? = null,
    onOpenWorkshopLookup: (() -> Unit)? = null,
    onOpenScanOrLink: (() -> Unit)? = null,
    onOpenAssistant: (() -> Unit)? = null,
    onOpenReviews: ((CatalogApp) -> Unit)? = null,
    onOpenDeveloper: ((String) -> Unit)? = null,
    onAcquireApp: ((CatalogApp) -> Unit)? = null,
    onShareApp: ((CatalogApp) -> Unit)? = null,
    onFinishActivity: () -> Unit,
) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val showTwoPane = maxWidth >= 840.dp
        val currentShowTwoPane by rememberUpdatedState(showTwoPane)
        val sceneStrategy = remember(showTwoPane) {
            ListDetailSceneStrategy(showTwoPane = showTwoPane)
        }
        val activeDetailIdState = remember(backStack) {
            derivedStateOf { (backStack.lastOrNull() as? DetailRoute)?.appId }
        }
        val hasCatalogEntryState = remember(backStack) {
            derivedStateOf { backStack.any { it is CatalogRoute } }
        }

        NavDisplay(
            backStack = backStack,
            onBack = {
                if (backStack.size > 1) {
                    backStack.removeAt(backStack.lastIndex)
                } else {
                    onFinishActivity()
                }
            },
            sceneStrategies = listOf(sceneStrategy),
            entryProvider = entryProvider {
                entry<CatalogRoute>(
                    metadata = CatalogPaneMetadata.listPane(),
                ) {
                    CatalogScreen(
                        uiState = uiState,
                        selectedAppId = if (currentShowTwoPane) activeDetailIdState.value else null,
                        initialListIndex = viewModel.savedListIndex,
                        initialListOffset = viewModel.savedListOffset,
                        homeInstalledIds = homeInstalledIds,
                        activeUser = activeUser,
                        onQueryChange = viewModel::updateQuery,
                        onCategoryChange = viewModel::updateCategory,
                        onSaveScrollPosition = viewModel::saveListPosition,
                        onRetry = viewModel::retry,
                        onOpenAccount = onOpenAccount,
                        onResumeSession = onResumeSession,
                        onSelectApp = { app -> pushDetailRoute(backStack, app.id) },
                        onLaunchApp = onLaunchApp,
                        onToggleHome = onToggleHome,
                        onOpenMyWorkshops = onOpenMyWorkshops,
                        onOpenWorkshopLookup = onOpenWorkshopLookup,
                        onOpenScanOrLink = onOpenScanOrLink,
                        onOpenAssistant = onOpenAssistant,
                    )
                }
                entry<DetailRoute>(
                    metadata = CatalogPaneMetadata.detailPane(),
                ) { route ->
                    val fallbackApp = transientApps[route.appId]
                    val resolvedApp = uiState.findApp(route.appId) ?: fallbackApp
                    val appInHome = resolvedApp?.id?.let { homeInstalledIds.contains(it) } == true
                    DetailScreen(
                        appId = route.appId,
                        uiState = uiState,
                        showBackNavigation = !currentShowTwoPane || !hasCatalogEntryState.value,
                        isInHome = appInHome,
                        fallbackApp = fallbackApp,
                        onBack = {
                            if (backStack.size > 1) {
                                backStack.removeAt(backStack.lastIndex)
                            } else {
                                onFinishActivity()
                            }
                        },
                        onRetry = viewModel::retry,
                        onResumeSession = onResumeSession,
                        onLaunchApp = onLaunchApp,
                        onToggleHome = onToggleHome,
                        onOpenWebDetails = onOpenWebDetails,
                        onOpenAppData = onOpenAppData,
                        onOpenReviews = onOpenReviews,
                        onOpenDeveloper = onOpenDeveloper,
                        onAcquireApp = onAcquireApp,
                        onShareApp = onShareApp,
                    )
                }
            },
        )
    }
}

@Composable
private fun IncomingDestinationDialog(
    destination: NativeDestination,
    activeUser: AccountUser?,
    onOpenWeb: (String) -> Unit,
    onNavigateToMe: () -> Unit,
    onDeliverCrossAppCallback: (String) -> Boolean,
    onDismiss: () -> Unit,
) {
    when (destination) {
        is NativeDestination.Application -> Unit

        is NativeDestination.Workshop -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text("个人工坊 #${destination.id}") },
                text = { Text("原生个人工坊视图正在完善中，可先在浏览器中打开查看此工坊页面。") },
                confirmButton = {
                    Button(onClick = { onOpenWeb("https://apps.yunle.fun/w/${destination.id}") }) {
                        Text("在浏览器中打开")
                    }
                },
                dismissButton = {
                    TextButton(onClick = onDismiss) {
                        Text("关闭")
                    }
                },
            )
        }

        is NativeDestination.Developer -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text("开发者 @${destination.login}") },
                text = { Text("原生开发者主页正在完善中，可先在浏览器中查看作者公开作品。") },
                confirmButton = {
                    Button(onClick = { onOpenWeb("https://apps.yunle.fun/developer/${destination.login}") }) {
                        Text("在浏览器中打开")
                    }
                },
                dismissButton = {
                    TextButton(onClick = onDismiss) {
                        Text("关闭")
                    }
                },
            )
        }

        NativeDestination.InvalidCrossAppAuth -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text("该授权请求无效") },
                text = { Text("请回到发起登录的 App 重新尝试。") },
                confirmButton = {
                    Button(onClick = onDismiss) {
                        Text("知道了")
                    }
                },
            )
        }

        is NativeDestination.CrossAppAuth -> {
            CrossAppAuthDialog(
                request = destination.request,
                activeUser = activeUser,
                onNavigateToMe = onNavigateToMe,
                onDeliverCallback = onDeliverCrossAppCallback,
                onDismiss = onDismiss,
            )
        }
    }
}

@Composable
private fun CrossAppAuthDialog(
    request: CrossAppAuthorizationRequest,
    activeUser: AccountUser?,
    onNavigateToMe: () -> Unit,
    onDeliverCallback: (String) -> Boolean,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var policy by remember(request) { mutableStateOf<HostSsoPolicy?>(null) }
    var issueTitle by remember(request) { mutableStateOf<String?>(null) }
    var issueMessage by remember(request) { mutableStateOf<String?>(null) }
    var isResolving by remember(request) { mutableStateOf(true) }
    var isIssuing by remember(request) { mutableStateOf(false) }

    LaunchedEffect(request) {
        isResolving = true
        issueTitle = null
        issueMessage = null
        policy = null
        runCatching {
            YunleContainer.hostAuthService.resolve(request.toHostSsoRequest())
        }.fold(
            onSuccess = {
                policy = it
                isResolving = false
            },
            onFailure = { error ->
                isResolving = false
                val authError = (error as? HostAuthorizationException)?.error
                if (authError == HostAuthorizationError.INVALID_REQUEST) {
                    issueTitle = "该授权请求无效"
                    issueMessage = "请回到发起登录的 App 重新尝试。"
                } else {
                    issueTitle = "暂时无法验证登录请求"
                    issueMessage = "请回到发起登录的 App 重试。"
                }
            },
        )
    }

    val currentPolicy = policy
    when {
        isResolving -> {
            AlertDialog(
                onDismissRequest = {},
                title = { Text("正在验证登录请求…") },
                text = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        CircularProgressIndicator()
                        Text("正在确认请求来源与权限范围", style = MaterialTheme.typography.bodyMedium)
                    }
                },
                confirmButton = {},
                dismissButton = {
                    TextButton(onClick = onDismiss) {
                        Text("取消")
                    }
                },
            )
        }

        issueTitle != null || currentPolicy == null -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text(issueTitle ?: "暂时无法验证登录请求") },
                text = { Text(issueMessage ?: "请回到发起登录的 App 重试。") },
                confirmButton = {
                    Button(onClick = onDismiss) {
                        Text("知道了")
                    }
                },
            )
        }

        activeUser?.isUsable != true -> {
            AlertDialog(
                onDismissRequest = {
                    CrossAppRedirect.Denied.callbackUrl(request)?.let(onDeliverCallback)
                    onDismiss()
                },
                title = { Text("${currentPolicy.applicationName} 申请使用你的云乐坊账号") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("来源：${currentPolicy.applicationOrigin}", style = MaterialTheme.typography.bodySmall)
                        Text("请先登录云乐坊账号后再确认授权。")
                    }
                },
                confirmButton = {
                    Button(onClick = onNavigateToMe) {
                        Text("去登录")
                    }
                },
                dismissButton = {
                    TextButton(
                        onClick = {
                            CrossAppRedirect.Denied.callbackUrl(request)?.let(onDeliverCallback)
                            onDismiss()
                        },
                    ) {
                        Text("取消")
                    }
                },
            )
        }

        else -> {
            AlertDialog(
                onDismissRequest = {
                    if (!isIssuing) {
                        CrossAppRedirect.Denied.callbackUrl(request)?.let(onDeliverCallback)
                        onDismiss()
                    }
                },
                title = { Text("${currentPolicy.applicationName} 申请使用你的云乐坊账号") },
                text = {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = "来源：${currentPolicy.applicationOrigin}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = "授权权限：${currentPolicy.permissionDescription}",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Text(
                            text = "当前账号：${activeUser.displayName}",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                },
                confirmButton = {
                    Button(
                        enabled = !isIssuing,
                        onClick = {
                            val expectedUid = activeUser.id
                            val expectedGen = YunleContainer.accounts.identityGeneration.value
                            isIssuing = true
                            scope.launch {
                                val result = runCatching {
                                    val identity = YunleContainer.accounts.authorization(forceRefresh = false)
                                    if (YunleContainer.accounts.identityGeneration.value != expectedGen ||
                                        YunleContainer.accounts.user?.id != expectedUid
                                    ) {
                                        error("account changed")
                                    }
                                    val issued = YunleContainer.hostAuthService.issue(
                                        request = request.toHostSsoRequest(),
                                        identity = identity,
                                    )
                                    if (YunleContainer.accounts.identityGeneration.value != expectedGen ||
                                        YunleContainer.accounts.user?.id != expectedUid
                                    ) {
                                        error("account changed")
                                    }
                                    issued
                                }
                                isIssuing = false
                                result.fold(
                                    onSuccess = { issued ->
                                        val callbackUrl = CrossAppRedirect.Approved(issued.code).callbackUrl(request)
                                        if (callbackUrl != null && onDeliverCallback(callbackUrl)) {
                                            onDismiss()
                                        } else {
                                            issueTitle = "无法返回${currentPolicy.applicationName}"
                                            issueMessage = "请更新${currentPolicy.applicationName}后重试。本次授权已作废。"
                                        }
                                    },
                                    onFailure = {
                                        issueTitle = "暂时无法完成授权"
                                        issueMessage = "账号状态已变化或服务暂不可用，请重试。"
                                    },
                                )
                            }
                        },
                    ) {
                        if (isIssuing) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("授权中…")
                        } else {
                            Text("确认授权")
                        }
                    }
                },
                dismissButton = {
                    TextButton(
                        enabled = !isIssuing,
                        onClick = {
                            CrossAppRedirect.Denied.callbackUrl(request)?.let(onDeliverCallback)
                            onDismiss()
                        },
                    ) {
                        Text("取消")
                    }
                },
            )
        }
    }
}

private fun openCrossAppCallback(activity: ComponentActivity, callbackUrl: String): Boolean {
    val uri = runCatching { Uri.parse(callbackUrl) }.getOrNull() ?: return false
    val intent = Intent(Intent.ACTION_VIEW, uri).apply {
        addCategory(Intent.CATEGORY_BROWSABLE)
        if (Build.VERSION.SDK_INT >= 30) {
            addFlags(Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
        }
    }
    val resolved = activity.packageManager.resolveActivity(intent, 0)
    if (resolved?.activityInfo?.packageName == activity.packageName) return false
    if (Build.VERSION.SDK_INT < 30) {
        val targetPackage = resolved?.activityInfo?.packageName ?: return false
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")).addCategory(Intent.CATEGORY_BROWSABLE)
        val browserPackages = activity.packageManager.queryIntentActivities(probe, 0)
            .mapNotNullTo(mutableSetOf()) { it.activityInfo?.packageName }
        if (browserPackages.contains(targetPackage)) return false
    }
    return runCatching {
        activity.startActivity(intent)
        true
    }.getOrDefault(false)
}

internal fun openInCustomTab(context: Context, uri: Uri) {
    runCatching { CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri) }
        .recoverCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
        .onFailure {
            android.widget.Toast.makeText(context, "无法打开浏览器", android.widget.Toast.LENGTH_SHORT).show()
        }
}
