package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountError
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.AuthorizedAccount
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

internal enum class HomeSyncResolution {
    DEVICE,
    CLOUD,
}

internal sealed class HomeSyncPhase {
    data object Idle : HomeSyncPhase()
    data object Syncing : HomeSyncPhase()
    data class Failed(val error: HomeSyncError, val message: String) : HomeSyncPhase()
    data class Conflict(val remote: RemoteHomeScreen) : HomeSyncPhase()
}

internal class HomeSyncCoordinator(
    private val service: HomeSyncServing,
    private val library: HomeLibrary,
    private val accounts: AccountStore,
    private val catalogProvider: () -> List<CatalogApp> = { emptyList() },
    private val debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    private val _phase = MutableStateFlow<HomeSyncPhase>(HomeSyncPhase.Idle)
    val phase: StateFlow<HomeSyncPhase> = _phase.asStateFlow()

    private val syncMutex = Mutex()
    private var scheduledJob: Job? = null
    private var activeSyncJob: Job? = null

    init {
        library.onUserChange = {
            schedule()
        }
    }

    fun identityChanged() {
        scheduledJob?.cancel()
        scheduledJob = null
        activeSyncJob?.cancel()
        activeSyncJob = null
        _phase.value = HomeSyncPhase.Idle
        if (accounts.user != null && library.snapshot.value.syncEnabled) {
            synchronize()
        }
    }

    fun schedule() {
        scheduledJob?.cancel()
        scheduledJob = null
        val snap = library.snapshot.value
        if (accounts.user == null || !snap.syncEnabled || !snap.autoSyncEnabled) {
            return
        }
        val expectedGeneration = accounts.identityGeneration.value
        val expectedAccountId = accounts.overview.value.activeID ?: return
        scheduledJob = scope.launch {
            delay(debounceMillis)
            if (accounts.identityGeneration.value != expectedGeneration ||
                accounts.overview.value.activeID != expectedAccountId
            ) {
                return@launch
            }
            synchronize()
        }
    }

    fun recheck() {
        val snap = library.snapshot.value
        if (accounts.user == null || !snap.syncEnabled || !snap.autoSyncEnabled) return
        if (_phase.value is HomeSyncPhase.Conflict) return
        synchronize()
    }

    fun synchronize(): Job? {
        scheduledJob?.cancel()
        scheduledJob = null
        val snap = library.snapshot.value
        val accountId = accounts.overview.value.activeID
        if (accounts.user == null || accountId == null || !snap.syncEnabled) {
            _phase.value = HomeSyncPhase.Idle
            return null
        }
        val expectedGeneration = accounts.identityGeneration.value
        val job = scope.launch {
            syncMutex.withLock {
                runSyncLocked(expectedGeneration = expectedGeneration, expectedAccountId = accountId)
            }
        }
        activeSyncJob = job
        return job
    }

    fun resolve(resolution: HomeSyncResolution): Job? {
        val conflict = (_phase.value as? HomeSyncPhase.Conflict)?.remote ?: return null
        val accountId = accounts.overview.value.activeID ?: return null
        val expectedGeneration = accounts.identityGeneration.value
        if (accounts.user == null) return null

        return when (resolution) {
            HomeSyncResolution.DEVICE -> {
                library.keepDevice(conflict, accountId)
                synchronize()
            }
            HomeSyncResolution.CLOUD -> {
                library.keepCloud(conflict, accountId, catalogProvider())
                if (accounts.identityGeneration.value == expectedGeneration) {
                    _phase.value = HomeSyncPhase.Idle
                }
                null
            }
        }
    }

    private suspend fun runSyncLocked(expectedGeneration: UUID, expectedAccountId: String) {
        if (!isCurrent(expectedGeneration, expectedAccountId)) return
        if (!library.snapshot.value.syncEnabled) {
            _phase.value = HomeSyncPhase.Idle
            return
        }
        _phase.value = HomeSyncPhase.Syncing

        try {
            while (isCurrent(expectedGeneration, expectedAccountId)) {
                val snap = library.snapshot.value
                if (!snap.syncEnabled) {
                    _phase.value = HomeSyncPhase.Idle
                    return
                }
                val pending = library.pendingWrite()
                if (pending != null) {
                    val (write, writeGeneration) = pending
                    val saved = authorized(expectedGeneration, expectedAccountId) { identity ->
                        service.save(write, identity)
                    }
                    if (!isCurrent(expectedGeneration, expectedAccountId)) return
                    library.acknowledge(saved, writeGeneration, expectedAccountId)
                    if (!library.snapshot.value.hasPendingChanges) {
                        _phase.value = HomeSyncPhase.Idle
                        return
                    }
                } else {
                    val remote = authorized(expectedGeneration, expectedAccountId) { identity ->
                        service.load(identity)
                    }
                    if (!isCurrent(expectedGeneration, expectedAccountId)) return
                    if (!library.snapshot.value.hasPendingChanges) {
                        library.adopt(remote, expectedAccountId, catalogProvider())
                        _phase.value = HomeSyncPhase.Idle
                        return
                    }
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: HomeSyncException) {
            if (!isCurrent(expectedGeneration, expectedAccountId)) return
            _phase.value = if (e.error == HomeSyncError.CONFLICT && e.remoteConflict != null) {
                HomeSyncPhase.Conflict(e.remoteConflict)
            } else {
                HomeSyncPhase.Failed(e.error, e.error.userMessage)
            }
        } catch (e: AccountException) {
            if (!isCurrent(expectedGeneration, expectedAccountId)) return
            _phase.value = HomeSyncPhase.Failed(
                error = HomeSyncError.UNAUTHORIZED,
                message = AccountError.messageFor(e),
            )
        } catch (_: Throwable) {
            if (!isCurrent(expectedGeneration, expectedAccountId)) return
            _phase.value = HomeSyncPhase.Failed(
                error = HomeSyncError.UNAVAILABLE,
                message = HomeSyncError.UNAVAILABLE.userMessage,
            )
        }
    }

    private suspend fun <T> authorized(
        expectedGeneration: UUID,
        expectedAccountId: String,
        block: suspend (AuthorizedAccount) -> T,
    ): T {
        val identity = accounts.authorization(forceRefresh = false)
        if (!isCurrent(expectedGeneration, expectedAccountId) || identity.userID != expectedAccountId) {
            throw CancellationException("Identity changed")
        }
        return try {
            block(identity)
        } catch (e: HomeSyncException) {
            if (e.error != HomeSyncError.UNAUTHORIZED) throw e
            val refreshed = accounts.authorization(forceRefresh = true)
            if (!isCurrent(expectedGeneration, expectedAccountId) || refreshed.userID != expectedAccountId) {
                throw CancellationException("Identity changed")
            }
            block(refreshed)
        }
    }

    private fun isCurrent(expectedGeneration: UUID, expectedAccountId: String): Boolean =
        accounts.identityGeneration.value == expectedGeneration &&
            accounts.overview.value.activeID == expectedAccountId &&
            accounts.user != null

    companion object {
        private const val DEFAULT_DEBOUNCE_MILLIS = 1_200L
    }
}
