package `fun`.yunle.apps

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
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
import `fun`.yunle.apps.ui.catalog.CatalogFeedState
import `fun`.yunle.apps.ui.catalog.CatalogPaneMetadata
import `fun`.yunle.apps.ui.catalog.CatalogRoute
import `fun`.yunle.apps.ui.catalog.CatalogScreen
import `fun`.yunle.apps.ui.catalog.CatalogUiState
import `fun`.yunle.apps.ui.catalog.CatalogViewModel
import `fun`.yunle.apps.ui.catalog.DetailRoute
import `fun`.yunle.apps.ui.catalog.DetailScreen
import `fun`.yunle.apps.ui.catalog.ListDetailSceneStrategy
import `fun`.yunle.apps.ui.games.GamesScreen
import `fun`.yunle.apps.ui.home.HomeScreen
import `fun`.yunle.apps.ui.theme.YunleTheme

/** Android renders its 4-tab Material 3 shell and cloud application runtime host. */
class MainActivity : ComponentActivity() {
    private var launchedFromApp by mutableStateOf(false)
    private var externalDetailRequest by mutableStateOf<String?>(null)

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

        val appVersionName = runCatching {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0"
        }.getOrDefault("1.0")

        setContent {
            val appearance by YunleContainer.preferences.appearance.collectAsStateWithLifecycle()
            val showRecent by YunleContainer.preferences.showRecent.collectAsStateWithLifecycle()
            val screenshotFeedbackEnabled by YunleContainer.preferences.screenshotFeedbackEnabled.collectAsStateWithLifecycle()

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

                var selectedTab by rememberSaveable {
                    mutableStateOf(if (initialDetailKey != null) AppTab.WORKSHOP else AppTab.HOME)
                }
                var openSyncSettingsInMe by rememberSaveable { mutableStateOf(false) }

                val startRoute: NavKey = remember {
                    if (initialDetailKey != null) DetailRoute(initialDetailKey) else CatalogRoute
                }
                val workshopBackStack = rememberNavBackStack(startRoute)

                LaunchedEffect(Unit) {
                    YunleContainer.accounts.prepareInitialRestore()
                    YunleContainer.accounts.consumeInitialRestore()
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
                                        selectedTab = AppTab.WORKSHOP
                                        pushDetailRoute(workshopBackStack, app.id)
                                    }
                                },
                                onOpenDetail = { app ->
                                    selectedTab = AppTab.WORKSHOP
                                    pushDetailRoute(workshopBackStack, app.id)
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
                                onClearRecent = YunleContainer.homeLibrary::clearRecent,
                                onOpenUrl = { url -> openInCustomTab(this@MainActivity, Uri.parse(url)) },
                            )
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra(EXTRA_KEY)?.takeIf(CatalogApp::validKey)?.let { key ->
            launchedFromApp = true
            externalDetailRequest = key
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
    viewModel: CatalogViewModel,
    onOpenAccount: () -> Unit,
    onResumeSession: () -> Unit,
    onLaunchApp: (CatalogApp) -> Unit,
    onToggleHome: (CatalogApp) -> Unit,
    onOpenWebDetails: (CatalogApp) -> Unit,
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
                    )
                }
                entry<DetailRoute>(
                    metadata = CatalogPaneMetadata.detailPane(),
                ) { route ->
                    val appInHome = uiState.findApp(route.appId)?.id?.let { homeInstalledIds.contains(it) } == true
                    DetailScreen(
                        appId = route.appId,
                        uiState = uiState,
                        showBackNavigation = !currentShowTwoPane || !hasCatalogEntryState.value,
                        isInHome = appInHome,
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
                    )
                }
            },
        )
    }
}

internal fun openInCustomTab(context: Context, uri: Uri) {
    runCatching { CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri) }
        .recoverCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
        .onFailure {
            android.widget.Toast.makeText(context, "无法打开浏览器", android.widget.Toast.LENGTH_SHORT).show()
        }
}
