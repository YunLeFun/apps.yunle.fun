package `fun`.yunle.apps

import android.content.Context
import `fun`.yunle.apps.account.AccountSession
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.CloudbaseAuthService
import `fun`.yunle.apps.account.KeystoreAccountVault
import `fun`.yunle.apps.assistant.AssistantHistoryStore
import `fun`.yunle.apps.assistant.AssistantService
import `fun`.yunle.apps.assistant.AssistantServing
import `fun`.yunle.apps.cache.ApplicationCacheRepository
import `fun`.yunle.apps.cache.ApplicationCacheStore
import `fun`.yunle.apps.cache.NativeGameResourceCacheStore
import `fun`.yunle.apps.catalog.ApplicationAcquisitionService
import `fun`.yunle.apps.catalog.ApplicationAcquisitionServing
import `fun`.yunle.apps.catalog.DeveloperProfileService
import `fun`.yunle.apps.catalog.DeveloperProfileServing
import `fun`.yunle.apps.catalog.WorkshopDiscoveryService
import `fun`.yunle.apps.catalog.WorkshopDiscoveryServing
import `fun`.yunle.apps.community.CommunityService
import `fun`.yunle.apps.community.CommunityServing
import `fun`.yunle.apps.games.NativeGameCatalogStore
import `fun`.yunle.apps.games.NativeGameHistoryStore
import `fun`.yunle.apps.games.NativePublicRoomService
import `fun`.yunle.apps.games.NativePublicRoomServing
import `fun`.yunle.apps.games.NativeRoomCreating
import `fun`.yunle.apps.games.NativeRoomCreationService
import `fun`.yunle.apps.home.HomeLibrary
import `fun`.yunle.apps.home.HomeSyncCoordinator
import `fun`.yunle.apps.home.HomeSyncService
import `fun`.yunle.apps.publishing.ApplicationDraftVault
import `fun`.yunle.apps.publishing.PublishingService
import `fun`.yunle.apps.publishing.PublishingServing
import `fun`.yunle.apps.wallet.PurchaseOwnershipJournal
import `fun`.yunle.apps.wallet.WalletService
import `fun`.yunle.apps.wallet.WalletServing
import `fun`.yunle.apps.webruntime.HostAuthorizationService
import `fun`.yunle.apps.webruntime.WebProfileRepository
import `fun`.yunle.apps.workshop.WorkshopService
import `fun`.yunle.apps.workshop.WorkshopServing
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class AppAppearance(val key: String, val label: String) {
    SYSTEM("system", "跟随系统"),
    LIGHT("light", "浅色"),
    DARK("dark", "深色");

    companion object {
        fun fromKey(key: String?): AppAppearance =
            entries.firstOrNull { it.key == key } ?: SYSTEM
    }
}

class YunlePreferences(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("yunle_settings", Context.MODE_PRIVATE)

    private val _appearance = MutableStateFlow(AppAppearance.fromKey(prefs.getString("appearance", "system")))
    val appearance: StateFlow<AppAppearance> = _appearance.asStateFlow()

    private val _showRecent = MutableStateFlow(prefs.getBoolean("home.showRecent", true))
    val showRecent: StateFlow<Boolean> = _showRecent.asStateFlow()

    private val _screenshotFeedbackEnabled = MutableStateFlow(prefs.getBoolean("feedback.screenshotPrompt", true))
    val screenshotFeedbackEnabled: StateFlow<Boolean> = _screenshotFeedbackEnabled.asStateFlow()

    private val _gameBackConfirmEnabled = MutableStateFlow(prefs.getBoolean("games.backConfirmEnabled", true))
    val gameBackConfirmEnabled: StateFlow<Boolean> = _gameBackConfirmEnabled.asStateFlow()

    fun setAppearance(next: AppAppearance) {
        prefs.edit().putString("appearance", next.key).apply()
        _appearance.value = next
    }

    fun setShowRecent(enabled: Boolean) {
        prefs.edit().putBoolean("home.showRecent", enabled).apply()
        _showRecent.value = enabled
    }

    fun setScreenshotFeedbackEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("feedback.screenshotPrompt", enabled).apply()
        _screenshotFeedbackEnabled.value = enabled
    }

    fun setGameBackConfirmEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("games.backConfirmEnabled", enabled).apply()
        _gameBackConfirmEnabled.value = enabled
    }

    internal fun rawPreferences(): android.content.SharedPreferences = prefs
}

object YunleContainer {
    @Volatile
    private var initialized = false

    lateinit var accounts: AccountStore
        private set

    lateinit var webProfiles: WebProfileRepository
        private set

    internal lateinit var homeLibrary: HomeLibrary
        private set

    internal lateinit var homeSync: HomeSyncCoordinator
        private set

    @Volatile
    private var cachedCatalogApps: List<CatalogApp> = emptyList()

    lateinit var preferences: YunlePreferences
        private set

    internal lateinit var nativeGameCatalogStore: NativeGameCatalogStore
        private set

    internal lateinit var nativeGameHistoryStore: NativeGameHistoryStore
        private set

    internal lateinit var gameResourceCache: NativeGameResourceCacheStore
        private set

    internal lateinit var applicationCacheStore: ApplicationCacheStore
        private set

    internal lateinit var assistantHistoryStore: AssistantHistoryStore
        private set

    internal lateinit var purchaseJournal: PurchaseOwnershipJournal
        private set

    internal lateinit var draftVault: ApplicationDraftVault
        private set
    internal lateinit var sharedFeedbackHistory: `fun`.yunle.apps.support.SharedFeedbackHistoryStore
        private set
    internal lateinit var diagnosticLogStore: `fun`.yunle.apps.diagnostics.DiagnosticLogStore
        private set
    internal lateinit var diagnosticUploadStore: `fun`.yunle.apps.diagnostics.DiagnosticUploadStore
        private set

    private val supportScope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Main.immediate,
    )

    val hostAuthService: HostAuthorizationService = HostAuthorizationService()
    internal val workshopService: WorkshopServing = WorkshopService()
    internal val communityService: CommunityServing = CommunityService()
    internal val developerProfileService: DeveloperProfileServing = DeveloperProfileService()
    internal val acquisitionService: ApplicationAcquisitionServing = ApplicationAcquisitionService()
    internal val discoveryService: WorkshopDiscoveryServing = WorkshopDiscoveryService()
    internal val publicRoomService: NativePublicRoomServing = NativePublicRoomService()
    internal val roomCreationService: NativeRoomCreating = NativeRoomCreationService(hostAuthService)
    internal val assistantService: AssistantServing = AssistantService()
    internal val walletService: WalletServing = WalletService()
    internal val publishingService: PublishingServing = PublishingService()
    internal val supportService: `fun`.yunle.apps.support.SupportCenterService by lazy {
        `fun`.yunle.apps.support.SupportCenterService(authorization = hostAuthService)
    }
    internal val supportTicketClient: `fun`.yunle.apps.support.SupportTicketClient by lazy {
        `fun`.yunle.apps.support.SupportTicketClient()
    }

    internal fun ensureInitialized(context: Context, accountSession: AccountSession? = null) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            val appContext = context.applicationContext
            val profilesRepo = WebProfileRepository(
                file = File(appContext.noBackupFilesDir, "WebProfiles/ownership-v1.json"),
            )
            val library = HomeLibrary(
                directory = File(appContext.noBackupFilesDir, "HomeLibrary"),
            )
            val gameHistory = NativeGameHistoryStore(
                directory = File(appContext.noBackupFilesDir, "Games/History"),
            )
            gameHistory.activate(null)
            val prefs = YunlePreferences(appContext)
            val gameCatalog = NativeGameCatalogStore(
                cacheFile = File(appContext.cacheDir, "Games/catalog-v1.json"),
                bundledLoader = {
                    runCatching {
                        appContext.assets.open("native-game-catalog-v1.json").bufferedReader().use { it.readText() }
                    }.getOrNull()
                },
            )
            val gameResources = NativeGameResourceCacheStore(
                rootDir = File(appContext.cacheDir, "GameResources"),
                prefs = prefs.rawPreferences(),
            )
            val appCacheRepo = ApplicationCacheRepository(
                directory = File(appContext.cacheDir, "CloudApplicationDownloads"),
            )
            val appCache = ApplicationCacheStore(
                repository = appCacheRepo,
                prefs = prefs.rawPreferences(),
            )
            val aiHistory = AssistantHistoryStore(
                directory = File(appContext.noBackupFilesDir, "Assistant/History"),
            )
            aiHistory.activate(null)
            val journal = PurchaseOwnershipJournal(
                file = File(appContext.noBackupFilesDir, "Wallet/purchase-owners-v2.json"),
            )
            val drafts = ApplicationDraftVault(
                directory = File(appContext.noBackupFilesDir, "ApplicationDrafts"),
            )
            val shareHistory = `fun`.yunle.apps.support.SharedFeedbackHistoryStore(
                file = File(appContext.noBackupFilesDir, "Support/share-history.json"),
            )
            shareHistory.activate(null)
            val diagLogs = `fun`.yunle.apps.diagnostics.DiagnosticLogStore(
                directory = File(appContext.noBackupFilesDir, "Diagnostics/Logs"),
            )
            diagLogs.activateAccount(null)
            val session = accountSession ?: AccountSession(api = CloudbaseAuthService(), vault = KeystoreAccountVault(appContext))
            var coordinator: HomeSyncCoordinator? = null
            var diagUploads: `fun`.yunle.apps.diagnostics.DiagnosticUploadStore? = null
            val store = AccountStore(
                session = session,
                accountWillRemove = { removedId ->
                    profilesRepo.retire(removedId)
                },
                accountDidRemove = { HostSession.closeAll() },
                identityDidChange = { activeId ->
                    HostSession.closeAll()
                    library.activateAccount(activeId)
                    gameHistory.activate(activeId)
                    aiHistory.activate(activeId)
                    shareHistory.activate(activeId)
                    diagLogs.activateAccount(activeId)
                    diagUploads?.identityChanged()
                    coordinator?.identityChanged()
                },
            )
            shareHistory.activate(store.user?.id)
            diagLogs.activateAccount(store.user?.id)
            val uploads = `fun`.yunle.apps.diagnostics.DiagnosticUploadStore(
                accounts = store,
                logs = diagLogs,
                service = `fun`.yunle.apps.diagnostics.DiagnosticService(),
                receiptDirectory = File(appContext.noBackupFilesDir, "Diagnostics/Receipts"),
                scope = supportScope,
            )
            diagUploads = uploads
            diagLogs.record(
                `fun`.yunle.apps.diagnostics.DiagnosticLogLevel.INFO,
                "Application initialized",
            )
            val sync = HomeSyncCoordinator(
                service = HomeSyncService(),
                library = library,
                accounts = store,
                catalogProvider = { cachedCatalogApps },
            )
            coordinator = sync
            webProfiles = profilesRepo
            homeLibrary = library
            homeSync = sync
            preferences = prefs
            nativeGameCatalogStore = gameCatalog
            nativeGameHistoryStore = gameHistory
            gameResourceCache = gameResources
            applicationCacheStore = appCache
            assistantHistoryStore = aiHistory
            purchaseJournal = journal
            draftVault = drafts
            sharedFeedbackHistory = shareHistory
            diagnosticLogStore = diagLogs
            diagnosticUploadStore = uploads
            accounts = store
            initialized = true
        }
    }

    internal fun updateCatalogApps(applications: List<CatalogApp>) {
        cachedCatalogApps = applications
        if (initialized) {
            homeLibrary.updateCatalog(applications)
        }
    }

    internal fun selectWebProfile(applicationID: String, launchUrl: String): WebProfileRepository.Selection {
        val principal = accounts.user?.id?.let { WebProfileRepository.Principal.Account(it) }
            ?: WebProfileRepository.Principal.Guest
        return webProfiles.select(principal, applicationID, launchUrl)
    }
}
