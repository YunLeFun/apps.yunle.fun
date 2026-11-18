package `fun`.yunle.apps

import android.content.Context
import `fun`.yunle.apps.account.AccountSession
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.CloudbaseAuthService
import `fun`.yunle.apps.account.KeystoreAccountVault
import `fun`.yunle.apps.home.HomeLibrary
import `fun`.yunle.apps.home.HomeSyncCoordinator
import `fun`.yunle.apps.home.HomeSyncService
import `fun`.yunle.apps.webruntime.HostAuthorizationService
import `fun`.yunle.apps.webruntime.WebProfileRepository
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

    val hostAuthService: HostAuthorizationService = HostAuthorizationService()

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
            val prefs = YunlePreferences(appContext)
            val session = accountSession ?: AccountSession(api = CloudbaseAuthService(), vault = KeystoreAccountVault(appContext))
            var coordinator: HomeSyncCoordinator? = null
            val store = AccountStore(
                session = session,
                accountWillRemove = { removedId ->
                    profilesRepo.retire(removedId)
                },
                accountDidRemove = { HostSession.closeAll() },
                identityDidChange = { activeId ->
                    HostSession.closeAll()
                    library.activateAccount(activeId)
                    coordinator?.identityChanged()
                },
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
