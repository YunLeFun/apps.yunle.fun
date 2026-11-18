package `fun`.yunle.apps.account

import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

class AccountSession(
    private val api: AccountAuthenticating = CloudbaseAuthService(),
    private val vault: AccountVault = InMemoryAccountVault(),
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val mutex = Mutex()
    private val refreshScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var state: AccountVaultState? = null
    private var dirty = false
    private var revision = 0
    private var selectionGeneration = 0
    private var signInAttempt: UUID? = null
    private val refreshes = mutableMapOf<String, RefreshFlight>()

    private data class RefreshFlight(
        val id: UUID,
        val original: AccountCredential,
        val deferred: Deferred<AuthTokenResponse>,
    )

    suspend fun overview(): AccountOverview = mutex.withLock {
        val current = loadLocked()
        AccountOverview(
            revision = revision,
            users = current.accounts.map { it.user },
            activeID = current.activeID,
        )
    }

    suspend fun overview(matching: AccountSignInCommit): AccountOverview = mutex.withLock {
        val current = loadLocked()
        if (current.activeID != matching.userID || selectionGeneration != matching.selectionGeneration) {
            throw AccountException(AccountError.SESSION_CHANGED)
        }
        AccountOverview(
            revision = revision,
            users = current.accounts.map { it.user },
            activeID = current.activeID,
        )
    }

    suspend fun restore() {
        val hasActive = mutex.withLock { loadLocked().activeID != null }
        if (!hasActive) return
        refreshProfile()
    }

    suspend fun passwordSignIn(
        identifier: String,
        password: String,
        captcha: String? = null,
        attemptID: UUID = UUID.randomUUID(),
    ): AccountSignInCommit {
        currentCoroutineContext().ensureActive()
        val deviceID = mutex.withLock {
            signInAttempt = attemptID
            requestDeviceIDLocked()
        }
        val response = api.passwordSignIn(identifier, password, deviceID, captcha)
        return accept(response, attemptID, deviceID)
    }

    suspend fun sendVerification(
        address: VerificationAddress,
        captcha: String? = null,
    ): VerificationChallenge {
        val deviceID = mutex.withLock { requestDeviceIDLocked() }
        return api.sendVerification(address, deviceID, captcha)
    }

    suspend fun verify(
        challenge: VerificationChallenge,
        code: String,
        captcha: String? = null,
        attemptID: UUID = UUID.randomUUID(),
    ): AccountSignInCommit {
        currentCoroutineContext().ensureActive()
        val deviceID = mutex.withLock {
            signInAttempt = attemptID
            requestDeviceIDLocked()
        }
        val response = api.verify(challenge, code, deviceID, captcha)
        return accept(response, attemptID, deviceID)
    }

    suspend fun cancelSignIn(attemptID: UUID? = null) = mutex.withLock {
        if (attemptID != null && signInAttempt != attemptID) return@withLock
        signInAttempt = null
    }

    suspend fun authorization(forceRefresh: Boolean = false): AuthorizedAccount {
        val (id, account, generation) = mutex.withLock {
            val current = loadLocked()
            flushLocked()
            val activeId = current.activeID ?: throw AccountException(AccountError.SIGNED_OUT)
            val saved = current.accounts.firstOrNull { it.user.id == activeId }
                ?: throw AccountException(AccountError.SIGNED_OUT)
            Triple(activeId, saved, selectionGeneration)
        }
        val credential = if (forceRefresh || account.credential.expiresAtMillis <= nowMillis() + 60_000L) {
            refresh(account)
        } else {
            account.credential
        }
        currentCoroutineContext().ensureActive()
        mutex.withLock {
            if (loadLocked().activeID != id || generation != selectionGeneration) {
                throw AccountException(AccountError.SESSION_CHANGED)
            }
            flushLocked()
        }
        return AuthorizedAccount(userID = id, accessToken = credential.accessToken)
    }

    suspend fun select(id: String) = mutex.withLock {
        val current = loadLocked()
        if (current.accounts.none { it.user.id == id }) {
            throw AccountException(AccountError.SIGNED_OUT)
        }
        if (current.activeID == id) return@withLock
        commitLocked(current.copy(activeID = id))
        signInAttempt = null
        selectionGeneration += 1
    }

    suspend fun remove(id: String): Deferred<Boolean> = mutex.withLock {
        val current = loadLocked()
        val account = current.accounts.firstOrNull { it.user.id == id }
            ?: throw AccountException(AccountError.SIGNED_OUT)
        val remaining = current.accounts.filterNot { it.user.id == id }
        val nextActive = if (current.activeID == id) null else current.activeID
        commitLocked(current.copy(accounts = remaining, activeID = nextActive))
        signInAttempt = null
        selectionGeneration += 1
        val deviceID = current.deviceID
        refreshScope.async {
            try {
                api.signOut(accessToken = account.credential.accessToken, deviceID = deviceID)
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    suspend fun refreshProfile() {
        val generation = mutex.withLock { selectionGeneration }
        var identity = authorization(forceRefresh = false)
        val deviceID = mutex.withLock { requestDeviceIDLocked() }
        val user = try {
            api.user(accessToken = identity.accessToken, deviceID = deviceID)
        } catch (e: AccountException) {
            if (e.error != AccountError.EXPIRED_SESSION) throw e
            mutex.withLock { requireCurrentLocked(identity, generation) }
            identity = authorization(forceRefresh = true)
            try {
                api.user(accessToken = identity.accessToken, deviceID = deviceID)
            } catch (retryError: AccountException) {
                if (retryError.error == AccountError.EXPIRED_SESSION) {
                    mutex.withLock {
                        requireCurrentLocked(identity, generation)
                        invalidateLocked(identity.userID)
                    }
                }
                throw retryError
            }
        }
        mutex.withLock {
            requireCurrentLocked(identity, generation)
            if (user.id != identity.userID) throw AccountException(AccountError.INVALID_RESPONSE)
            if (!user.isUsable) {
                invalidateLocked(identity.userID)
                throw AccountException(AccountError.BLOCKED_ACCOUNT)
            }
            val current = loadLocked()
            val index = current.accounts.indexOfFirst { it.user.id == identity.userID }
            if (current.activeID != identity.userID || index < 0) {
                throw AccountException(AccountError.SESSION_CHANGED)
            }
            val updatedAccounts = current.accounts.toMutableList()
            updatedAccounts[index] = updatedAccounts[index].copy(user = user)
            commitLocked(current.copy(accounts = updatedAccounts))
        }
    }

    suspend fun updateProfile(name: String, description: String) {
        val generation = mutex.withLock { selectionGeneration }
        val identity = authorization(forceRefresh = false)
        val deviceID = mutex.withLock {
            requireCurrentLocked(identity, generation)
            requestDeviceIDLocked()
        }
        api.updateProfile(
            userID = identity.userID,
            name = name,
            description = description,
            accessToken = identity.accessToken,
            deviceID = deviceID,
        )
        mutex.withLock { requireCurrentLocked(identity, generation) }
        refreshProfile()
    }

    suspend fun captcha(): CaptchaImage {
        val deviceID = mutex.withLock { requestDeviceIDLocked() }
        return api.captcha(deviceID)
    }

    suspend fun verifyCaptcha(token: String, text: String): String {
        val deviceID = mutex.withLock { requestDeviceIDLocked() }
        return api.verifyCaptcha(token, text, deviceID)
    }

    private suspend fun accept(
        response: AuthTokenResponse,
        attempt: UUID,
        deviceID: String,
    ): AccountSignInCommit {
        mutex.withLock {
            if (signInAttempt != attempt) throw AccountException(AccountError.SESSION_CHANGED)
        }
        val credential = response.credential(nowMillis())
        val user = api.user(accessToken = credential.accessToken, deviceID = deviceID)
        currentCoroutineContext().ensureActive()
        return mutex.withLock {
            if (signInAttempt != attempt) throw AccountException(AccountError.SESSION_CHANGED)
            if (user.id != response.subject) throw AccountException(AccountError.INVALID_RESPONSE)
            if (!user.isUsable) throw AccountException(AccountError.BLOCKED_ACCOUNT)
            val current = loadLocked()
            val updatedAccounts = buildList {
                add(SavedAccount(user = user, credential = credential))
                addAll(current.accounts.filterNot { it.user.id == user.id })
            }
            commitLocked(current.copy(accounts = updatedAccounts, activeID = user.id))
            signInAttempt = null
            selectionGeneration += 1
            AccountSignInCommit(
                attemptID = attempt,
                userID = user.id,
                selectionGeneration = selectionGeneration,
            )
        }
    }

    private suspend fun refresh(account: SavedAccount): AccountCredential {
        val id = account.user.id
        val flight = mutex.withLock {
            refreshes[id] ?: run {
                val deviceID = requestDeviceIDLocked()
                val token = account.credential.refreshToken
                RefreshFlight(
                    id = UUID.randomUUID(),
                    original = account.credential,
                    deferred = refreshScope.async { api.refresh(token, deviceID) },
                ).also { refreshes[id] = it }
            }
        }
        return try {
            val response = flight.deferred.await()
            mutex.withLock {
                val current = loadLocked()
                val index = current.accounts.indexOfFirst { it.user.id == id }
                if (index < 0) throw AccountException(AccountError.SIGNED_OUT)
                if (current.accounts[index].credential != flight.original) {
                    return@withLock current.accounts[index].credential
                }
                if (refreshes[id]?.id != flight.id) {
                    throw AccountException(AccountError.SESSION_CHANGED)
                }
                if (response.subject != id) {
                    throw AccountException(AccountError.INVALID_RESPONSE)
                }
                val credential = response.credential(nowMillis())
                val updated = current.accounts.toMutableList()
                updated[index] = updated[index].copy(credential = credential)
                refreshes.remove(id)
                commitLocked(current.copy(accounts = updated), retainingOnFailure = true)
                credential
            }
        } catch (t: Throwable) {
            mutex.withLock {
                if (refreshes[id]?.id == flight.id) {
                    refreshes.remove(id)
                }
                val accError = (t as? AccountException)?.error
                if ((accError == AccountError.EXPIRED_SESSION || accError == AccountError.BLOCKED_ACCOUNT) &&
                    loadLocked().accounts.firstOrNull { it.user.id == id }?.credential == flight.original
                ) {
                    invalidateLocked(id)
                }
            }
            throw t
        }
    }

    private fun invalidateLocked(id: String) {
        val current = loadLocked()
        val remaining = current.accounts.filterNot { it.user.id == id }
        val nextActive = if (current.activeID == id) {
            selectionGeneration += 1
            null
        } else {
            current.activeID
        }
        commitLocked(current.copy(accounts = remaining, activeID = nextActive), retainingOnFailure = true)
    }

    private fun requireCurrentLocked(identity: AuthorizedAccount, generation: Int) {
        val current = loadLocked()
        val tokenMatches = current.accounts
            .firstOrNull { it.user.id == identity.userID }
            ?.credential
            ?.accessToken == identity.accessToken
        if (selectionGeneration != generation || current.activeID != identity.userID || !tokenMatches) {
            throw AccountException(AccountError.SESSION_CHANGED)
        }
    }

    private fun loadLocked(): AccountVaultState {
        state?.let { return it }
        val bytes = vault.read()
        val loaded = if (bytes != null) {
            val parsed = try {
                AccountVaultState.fromJson(JSONObject(String(bytes, Charsets.UTF_8)))
            } catch (e: AccountException) {
                throw e
            } catch (e: Throwable) {
                throw AccountException(AccountError.UNSUPPORTED_VAULT, e)
            }
            val ids = parsed.accounts.map { it.user.id }
            val validDeviceUuid = runCatching { UUID.fromString(parsed.deviceID) }.isSuccess
            val validAccounts = parsed.accounts.all {
                it.user.isUsable &&
                    it.credential.accessToken.isNotEmpty() &&
                    it.credential.refreshToken.isNotEmpty()
            }
            val validActive = parsed.activeID == null || ids.contains(parsed.activeID)
            if (parsed.version != 1 || !validDeviceUuid || ids.distinct().size != ids.size || !validAccounts || !validActive) {
                throw AccountException(AccountError.UNSUPPORTED_VAULT)
            }
            parsed
        } else {
            dirty = true
            AccountVaultState()
        }
        state = loaded
        revision += 1
        return loaded
    }

    private fun requestDeviceIDLocked(): String {
        val loaded = loadLocked()
        flushLocked()
        return loaded.deviceID
    }

    private fun commitLocked(proposed: AccountVaultState, retainingOnFailure: Boolean = false) {
        val serialized = proposed.toJson().toString().toByteArray(Charsets.UTF_8)
        if (retainingOnFailure) {
            state = proposed
            dirty = true
            revision += 1
            flushLocked()
        } else {
            vault.write(serialized)
            state = proposed
            dirty = false
            revision += 1
        }
    }

    private fun flushLocked() {
        val current = state
        if (!dirty || current == null) return
        vault.write(current.toJson().toString().toByteArray(Charsets.UTF_8))
        dirty = false
    }
}

enum class AccountInitialRestorePhase {
    UNPREPARED,
    PENDING,
    RESTORING,
    SETTLED,
}

class AccountStore(
    private val session: AccountSession = AccountSession(),
    private val accountWillRemove: (String) -> Unit = {},
    private val accountDidRemove: (String) -> Unit = {},
    private val identityDidChange: (String?) -> Unit = {},
) {
    private val _overview = MutableStateFlow(AccountOverview())
    val overview: StateFlow<AccountOverview> = _overview.asStateFlow()

    private val _isRestoring = MutableStateFlow(false)
    val isRestoring: StateFlow<Boolean> = _isRestoring.asStateFlow()

    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    private val _identityGeneration = MutableStateFlow(UUID.randomUUID())
    val identityGeneration: StateFlow<UUID> = _identityGeneration.asStateFlow()

    private val _selectionOperationGeneration = MutableStateFlow(UUID.randomUUID())
    val selectionOperationGeneration: StateFlow<UUID> = _selectionOperationGeneration.asStateFlow()

    private val _initialRestorePhase = MutableStateFlow(AccountInitialRestorePhase.UNPREPARED)
    val initialRestorePhase: StateFlow<AccountInitialRestorePhase> = _initialRestorePhase.asStateFlow()

    private var selectionOperationEpoch = 0
    private var activeSignInAttemptID: UUID? = null
    private var lastProvenSuccess: AccountSignInSuccess? = null
    private var initialRestoreSelection: UUID? = null
    private val interactiveSignInSelections = mutableSetOf<UUID>()

    val user: AccountUser?
        get() = _overview.value.activeUser

    val currentBoundary: AccountRequestBoundary
        get() = AccountRequestBoundary(uid = user?.id, generation = _identityGeneration.value)

    fun isCurrent(success: AccountSignInSuccess): Boolean =
        lastProvenSuccess == success &&
            user?.isUsable == true &&
            success.target == currentBoundary

    fun prepareInitialRestore() {
        if (_initialRestorePhase.value != AccountInitialRestorePhase.UNPREPARED) return
        if (selectionOperationEpoch != 0 || _isRestoring.value) {
            _initialRestorePhase.value = AccountInitialRestorePhase.SETTLED
            return
        }
        if (user == null) {
            beginSelectionOperation(advancingSelectionEpoch = false)
        }
        initialRestoreSelection = _selectionOperationGeneration.value
        _initialRestorePhase.value = AccountInitialRestorePhase.PENDING
    }

    suspend fun consumeInitialRestore() {
        val selection = initialRestoreSelection
        if (_initialRestorePhase.value != AccountInitialRestorePhase.PENDING || selection == null) return
        if (selection != _selectionOperationGeneration.value || _isRestoring.value) {
            settleInitialRestore()
            return
        }
        _initialRestorePhase.value = AccountInitialRestorePhase.RESTORING
        _isRestoring.value = true
        try {
            if (publishInitialRestore(selection)) {
                try {
                    session.restore()
                    currentCoroutineContext().ensureActive()
                    if (initialRestoreIsCurrent(selection)) {
                        _notice.value = null
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: AccountException) {
                    if (e.error != AccountError.SESSION_CHANGED && initialRestoreIsCurrent(selection)) {
                        _notice.value = AccountError.messageFor(e)
                    }
                } catch (t: Throwable) {
                    if (initialRestoreIsCurrent(selection)) {
                        _notice.value = AccountError.messageFor(t)
                    }
                }
                publishInitialRestore(selection)
            }
        } finally {
            _isRestoring.value = false
            settleInitialRestore()
            reconcileInitialRestore(selection = _selectionOperationGeneration.value, reportingFor = selection)
        }
    }

    suspend fun restore() {
        if (_isRestoring.value) return
        if (user == null) {
            beginSelectionOperation(advancingSelectionEpoch = false)
        }
        _isRestoring.value = true
        try {
            publish()
            try {
                session.restore()
                _notice.value = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: AccountException) {
                if (e.error != AccountError.SESSION_CHANGED) {
                    _notice.value = AccountError.messageFor(e)
                }
            } catch (t: Throwable) {
                _notice.value = AccountError.messageFor(t)
            }
            publish()
        } finally {
            _isRestoring.value = false
        }
    }

    suspend fun passwordSignIn(
        identifier: String,
        password: String,
        captcha: String? = null,
        continuation: AccountSignInContinuation? = null,
        onCommitted: ((AccountSignInSuccess) -> Unit)? = null,
        attemptID: UUID = UUID.randomUUID(),
        onAuthenticated: (() -> Unit)? = null,
    ) {
        checkContinuation(continuation)
        val epoch = beginSelectionOperation()
        activeSignInAttemptID = attemptID
        val continuationGen = _selectionOperationGeneration.value
        interactiveSignInSelections.add(continuationGen)
        var published = false
        try {
            val commit = session.passwordSignIn(identifier, password, captcha, attemptID)
            publishSignIn(commit, epoch, continuationGen, continuation, onCommitted, onAuthenticated)
            published = true
        } finally {
            interactiveSignInSelections.remove(continuationGen)
            if (!published) {
                reconcileInitialRestore(selection = continuationGen)
            }
        }
    }

    suspend fun sendVerification(
        address: VerificationAddress,
        captcha: String? = null,
    ): VerificationChallenge = session.sendVerification(address, captcha)

    suspend fun verify(
        challenge: VerificationChallenge,
        code: String,
        captcha: String? = null,
        continuation: AccountSignInContinuation? = null,
        onCommitted: ((AccountSignInSuccess) -> Unit)? = null,
        attemptID: UUID = UUID.randomUUID(),
        onAuthenticated: (() -> Unit)? = null,
    ) {
        checkContinuation(continuation)
        val epoch = beginSelectionOperation()
        activeSignInAttemptID = attemptID
        val continuationGen = _selectionOperationGeneration.value
        interactiveSignInSelections.add(continuationGen)
        var published = false
        try {
            val commit = session.verify(challenge, code, captcha, attemptID)
            publishSignIn(commit, epoch, continuationGen, continuation, onCommitted, onAuthenticated)
            published = true
        } finally {
            interactiveSignInSelections.remove(continuationGen)
            if (!published) {
                reconcileInitialRestore(selection = continuationGen)
            }
        }
    }

    suspend fun cancelSignIn(attemptID: UUID? = null) {
        if (attemptID != null && activeSignInAttemptID != attemptID) return
        beginSelectionOperation()
        val selection = _selectionOperationGeneration.value
        session.cancelSignIn(attemptID)
        reconcileInitialRestore(selection = selection)
    }

    suspend fun authorization(forceRefresh: Boolean = false): AuthorizedAccount {
        return try {
            val identity = session.authorization(forceRefresh)
            publish()
            if (user?.id != identity.userID) {
                throw AccountException(AccountError.SESSION_CHANGED)
            }
            identity
        } catch (t: Throwable) {
            publish()
            throw t
        }
    }

    suspend fun select(id: String) {
        beginSelectionOperation()
        session.select(id)
        publish()
        restore()
    }

    suspend fun remove(id: String) {
        accountWillRemove(id)
        beginSelectionOperation()
        val revocation = session.remove(id)
        publish()
        accountDidRemove(id)
        val revoked = revocation.await()
        _notice.value = if (revoked) null else "已在此设备退出，暂时未能同步退出状态。"
    }

    suspend fun updateProfile(name: String, description: String) {
        try {
            session.updateProfile(name, description)
            publish()
        } catch (t: Throwable) {
            publish()
            throw t
        }
    }

    suspend fun captcha(): CaptchaImage = session.captcha()

    suspend fun verifyCaptcha(token: String, text: String): String =
        session.verifyCaptcha(token, text)

    private suspend fun publish() {
        try {
            apply(session.overview())
        } catch (t: Throwable) {
            _notice.value = AccountError.messageFor(t)
        }
    }

    private fun initialRestoreIsCurrent(selection: UUID): Boolean =
        _initialRestorePhase.value == AccountInitialRestorePhase.RESTORING &&
            initialRestoreSelection == selection &&
            _selectionOperationGeneration.value == selection

    private suspend fun publishInitialRestore(selection: UUID): Boolean {
        return try {
            val next = session.overview()
            currentCoroutineContext().ensureActive()
            if (!initialRestoreIsCurrent(selection)) return false
            apply(next)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (t: Throwable) {
            if (initialRestoreIsCurrent(selection)) {
                _notice.value = AccountError.messageFor(t)
            }
            false
        }
    }

    private suspend fun reconcileInitialRestore(selection: UUID, reportingFor: UUID? = null) {
        if (selection != _selectionOperationGeneration.value) return
        if (user == null && interactiveSignInSelections.contains(selection)) return
        try {
            val latest = session.overview()
            if (selection != _selectionOperationGeneration.value) return
            if (user == null && interactiveSignInSelections.contains(selection)) return
            apply(latest)
        } catch (e: CancellationException) {
            throw e
        } catch (t: Throwable) {
            if (reportingFor != null && initialRestoreIsCurrent(reportingFor)) {
                _notice.value = AccountError.messageFor(t)
            }
        }
    }

    private fun settleInitialRestore() {
        val phase = _initialRestorePhase.value
        if (phase != AccountInitialRestorePhase.PENDING && phase != AccountInitialRestorePhase.RESTORING) return
        initialRestoreSelection = null
        _initialRestorePhase.value = AccountInitialRestorePhase.SETTLED
    }

    private suspend fun publishSignIn(
        commit: AccountSignInCommit,
        epoch: Int,
        continuationGeneration: UUID,
        continuation: AccountSignInContinuation?,
        onCommitted: ((AccountSignInSuccess) -> Unit)?,
        onAuthenticated: (() -> Unit)?,
    ) {
        try {
            val next = session.overview(commit)
            checkContinuation(continuation)
            if (epoch != selectionOperationEpoch ||
                activeSignInAttemptID != commit.attemptID ||
                next.activeID != commit.userID ||
                next.activeUser?.isUsable != true ||
                (continuation != null && continuationGeneration != _selectionOperationGeneration.value)
            ) {
                throw AccountException(AccountError.SESSION_CHANGED)
            }
            if (next.revision >= _overview.value.revision) {
                apply(next)
            } else if (_overview.value.activeID != commit.userID || user?.isUsable != true) {
                throw AccountException(AccountError.SESSION_CHANGED)
            }
            _notice.value = null
            currentCoroutineContext().ensureActive()
            onAuthenticated?.invoke()
            if (continuation != null) {
                val success = AccountSignInSuccess(
                    requestID = continuation.requestID,
                    attemptID = commit.attemptID,
                    origin = continuation.origin,
                    target = AccountRequestBoundary(uid = commit.userID, generation = _identityGeneration.value),
                )
                lastProvenSuccess = success
                onCommitted?.invoke(success)
            }
        } catch (t: Throwable) {
            publish()
            throw t
        }
    }

    private suspend fun checkContinuation(continuation: AccountSignInContinuation?) {
        currentCoroutineContext().ensureActive()
        if (continuation == null) return
        if (continuation.origin.uid != null || user != null || continuation.origin != currentBoundary) {
            throw AccountException(AccountError.SESSION_CHANGED)
        }
    }

    private fun beginSelectionOperation(advancingSelectionEpoch: Boolean = true): Int {
        if (advancingSelectionEpoch) {
            selectionOperationEpoch += 1
            activeSignInAttemptID = null
        }
        lastProvenSuccess = null
        _selectionOperationGeneration.value = UUID.randomUUID()
        settleInitialRestore()
        return selectionOperationEpoch
    }

    private fun apply(next: AccountOverview) {
        if (next.revision < _overview.value.revision) return
        val previousActive = _overview.value.activeID
        _overview.value = next
        if (next.activeID != previousActive) {
            _identityGeneration.value = UUID.randomUUID()
            identityDidChange(next.activeID)
        }
    }
}
