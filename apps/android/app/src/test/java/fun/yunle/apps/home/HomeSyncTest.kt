package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.account.AccountAuthenticating
import `fun`.yunle.apps.account.AccountError
import `fun`.yunle.apps.account.AccountException
import `fun`.yunle.apps.account.AccountSession
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.account.AuthTokenResponse
import `fun`.yunle.apps.account.AuthorizedAccount
import `fun`.yunle.apps.account.CaptchaImage
import `fun`.yunle.apps.account.VerificationAddress
import `fun`.yunle.apps.account.VerificationChallenge
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

private class SyncTestAccountApi : AccountAuthenticating {
    val usersByToken = mutableMapOf<String, AccountUser>()
    var refreshCounter = 0

    override suspend fun passwordSignIn(
        identifier: String,
        password: String,
        deviceID: String,
        captcha: String?,
    ): AuthTokenResponse {
        val id = "user_alice"
        val token = "acc_${id}_${++refreshCounter}"
        usersByToken[token] = AccountUser(
            id = id,
            name = identifier,
            username = identifier,
            picture = "https://cdn.yunle.fun/avatars/alice.png",
        )
        return AuthTokenResponse(
            accessToken = token,
            refreshToken = "ref_alice_$refreshCounter",
            expiresIn = 3600,
            subject = id,
        )
    }

    override suspend fun sendVerification(
        address: VerificationAddress,
        deviceID: String,
        captcha: String?,
    ): VerificationChallenge = error("unused")

    override suspend fun verify(
        challenge: VerificationChallenge,
        code: String,
        deviceID: String,
        captcha: String?,
    ): AuthTokenResponse = error("unused")

    override suspend fun refresh(refreshToken: String, deviceID: String): AuthTokenResponse {
        val token = "acc_alice_${++refreshCounter}"
        usersByToken[token] = AccountUser(
            id = "user_alice",
            name = "alice",
            username = "alice",
            picture = "https://cdn.yunle.fun/avatars/alice.png",
        )
        return AuthTokenResponse(
            accessToken = token,
            refreshToken = "ref_alice_$refreshCounter",
            expiresIn = 3600,
            subject = "user_alice",
        )
    }

    override suspend fun user(accessToken: String, deviceID: String): AccountUser =
        usersByToken[accessToken] ?: throw AccountException(AccountError.EXPIRED_SESSION)

    override suspend fun signOut(accessToken: String, deviceID: String) {}

    override suspend fun updateProfile(
        userID: String,
        name: String,
        description: String,
        accessToken: String,
        deviceID: String,
    ) {}

    override suspend fun captcha(deviceID: String): CaptchaImage = error("unused")

    override suspend fun verifyCaptcha(token: String, text: String, deviceID: String): String = "ok"
}

private class FakeHomeSyncService(
    var remote: RemoteHomeScreen = RemoteHomeScreen(
        schemaVersion = 3,
        revision = null,
        configuration = HomeConfiguration(),
    ),
) : HomeSyncServing {
    var loadCalls = 0
    var saveCalls = 0
    var rejectToken: String? = null
    var conflictNextSave = false
    var nextRevision = "b".repeat(64)

    override suspend fun load(identity: AuthorizedAccount): RemoteHomeScreen {
        loadCalls += 1
        if (rejectToken != null && identity.accessToken == rejectToken) {
            throw HomeSyncException(HomeSyncError.UNAUTHORIZED)
        }
        return remote
    }

    override suspend fun save(write: HomeScreenWrite, identity: AuthorizedAccount): RemoteHomeScreen {
        saveCalls += 1
        if (rejectToken != null && identity.accessToken == rejectToken) {
            throw HomeSyncException(HomeSyncError.UNAUTHORIZED)
        }
        if (conflictNextSave) {
            conflictNextSave = false
            throw HomeSyncException(HomeSyncError.CONFLICT, remoteConflict = remote)
        }
        val saved = RemoteHomeScreen(
            schemaVersion = 3,
            revision = nextRevision,
            configuration = write.configuration,
        )
        remote = saved
        return saved
    }
}

class HomeSyncTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun sampleCatalogApp(
        id: String,
        key: String = id,
        slug: String? = null,
    ) = CatalogApp(
        id = id,
        key = key,
        name = "应用 $key",
        description = "测试应用",
        author = "云乐坊",
        ownerLogin = "yunle",
        category = "效率",
        emoji = "✨",
        launchUrl = "https://$key.yunle.fun/",
        logo = "https://cdn.yunle.fun/$key.png",
        themeColor = null,
        trustedHosts = emptyList(),
        immersive = false,
        slug = slug,
    )

    @Test
    fun `AccountUser fromJson resolves direct and user_metadata avatar fields`() {
        val direct = AccountUser.fromJson(
            JSONObject()
                .put("sub", "u1")
                .put("picture", "https://cdn.yunle.fun/a.png")
                .put("user_metadata", JSONObject().put("avatarUrl", "https://cdn.yunle.fun/b.png")),
        )
        assertEquals("https://cdn.yunle.fun/a.png", direct.picture)

        val nestedAvatarUrl = AccountUser.fromJson(
            JSONObject()
                .put("sub", "u2")
                .put("picture", JSONObject.NULL)
                .put("user_metadata", JSONObject().put("avatarUrl", "https://cdn.yunle.fun/meta.png")),
        )
        assertEquals("https://cdn.yunle.fun/meta.png", nestedAvatarUrl.picture)

        val nestedPicture = AccountUser.fromJson(
            JSONObject()
                .put("sub", "u3")
                .put("user_metadata", JSONObject().put("picture", "https://cdn.yunle.fun/meta2.jpg")),
        )
        assertEquals("https://cdn.yunle.fun/meta2.jpg", nestedPicture.picture)
    }

    @Test
    fun `HomeLibrary migrates legacy empty and non-empty M1 snapshots accurately`() {
        val dir = File(tempFolder.root, "HomeLibrary")
        dir.mkdirs()

        // Empty M1 guest file should not block cloud adopt after sign in
        File(dir, "guest.json").writeText(
            JSONObject()
                .put("version", 3)
                .put("dockVisible", false)
                .put("updatedAt", 0)
                .put("installedApps", org.json.JSONArray())
                .put("dockApps", org.json.JSONArray())
                .put("recentApps", org.json.JSONArray())
                .toString(),
        )

        val library = HomeLibrary(dir)
        assertFalse(library.snapshot.value.hasPendingChanges)
        assertTrue(library.snapshot.value.installedIds.isEmpty())

        // Non-empty M1 account file should keep items and mark pending changes
        val encodedAccount = java.util.Base64.getUrlEncoder().withoutPadding()
            .encodeToString("u_legacy".toByteArray(Charsets.UTF_8))
        File(dir, "$encodedAccount.json").writeText(
            JSONObject()
                .put("version", 3)
                .put("dockVisible", true)
                .put("updatedAt", 123456)
                .put("installedApps", org.json.JSONArray().put("web-resume"))
                .put("dockApps", org.json.JSONArray())
                .put("recentApps", org.json.JSONArray())
                .toString(),
        )

        library.activateAccount("u_legacy")
        assertTrue(library.snapshot.value.hasPendingChanges)
        assertEquals(listOf("web-resume"), library.snapshot.value.installedIds)
    }

    @Test
    fun `reference resolution supports id key slug and yun-home and cross-matches removal`() {
        val dir = File(tempFolder.root, "HomeResolution")
        val catalogApp = sampleCatalogApp(id = "67b1234567890abcdef12345", key = "ai-sfc", slug = "ai-sfc-legacy")
        val remote = RemoteHomeScreen(
            schemaVersion = 3,
            revision = "a".repeat(64),
            configuration = HomeConfiguration(
                installedApps = listOf(HomeAppReference("ai-sfc"), HomeAppReference("yun-home")),
                dockApps = listOf(HomeAppReference("ai-sfc-legacy")),
                updatedAt = 100L,
            ),
        )

        val library = HomeLibrary(dir)
        library.activateAccount("user_alice")
        library.adopt(remote, expectedAccountId = "user_alice", catalog = listOf(catalogApp))

        val snap = library.snapshot.value
        assertTrue(snap.contains(catalogApp))
        assertEquals(2, snap.applications.size)
        assertEquals("应用 ai-sfc", snap.applications[0].name)
        assertEquals("ai-sfc", snap.applications[0].homeReference)
        assertEquals("https://ai-sfc.yunle.fun/", snap.applications[0].launchUrl)
        assertEquals("Yun Home", snap.applications[1].name)
        assertEquals("https://home.yunle.fun/", snap.applications[1].launchUrl)
        assertEquals("应用 ai-sfc", snap.dockApplications[0].name)

        // Removing via catalogApp (whose id is hex ID) removes both marketShortName & slug refs
        library.remove(catalogApp)
        assertFalse(library.contains(catalogApp))
        assertEquals(listOf("yun-home"), library.snapshot.value.installedIds)
        assertTrue(library.snapshot.value.dockIds.isEmpty())
    }

    @Test(expected = HomeSyncException::class)
    fun `RemoteHomeScreen rejects non-empty configuration when revision is null`() {
        RemoteHomeScreen(
            schemaVersion = 3,
            revision = null,
            configuration = HomeConfiguration(
                installedApps = listOf(HomeAppReference("web-resume")),
                updatedAt = 1L,
            ),
        ).validate()
    }

    @Test
    fun `HomeSyncCoordinator adopts remote on sign in resolves conflicts and retries 401 refresh`() = runBlocking {
        val api = SyncTestAccountApi()
        val session = AccountSession(api = api)
        val library = HomeLibrary(File(tempFolder.root, "CoordLib"))
        val catalog = listOf(sampleCatalogApp(id = "id_resume", key = "web-resume"))

        val initialRemote = RemoteHomeScreen(
            schemaVersion = 3,
            revision = "a".repeat(64),
            configuration = HomeConfiguration(
                installedApps = listOf(HomeAppReference("web-resume")),
                updatedAt = 500L,
            ),
        )
        val service = FakeHomeSyncService(remote = initialRemote)
        var coordinator: HomeSyncCoordinator? = null
        val store = AccountStore(
            session = session,
            identityDidChange = { activeId ->
                library.activateAccount(activeId)
                coordinator?.identityChanged()
            },
        )
        coordinator = HomeSyncCoordinator(
            service = service,
            library = library,
            accounts = store,
            catalogProvider = { catalog },
            debounceMillis = 10L,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )

        store.passwordSignIn("alice@yunle.fun", "secret")
        coordinator.synchronize()?.join()

        assertEquals(HomeSyncPhase.Idle, coordinator.phase.value)
        assertEquals(listOf("web-resume"), library.snapshot.value.installedIds)
        assertEquals("应用 web-resume", library.snapshot.value.applications.first().name)

        // Force 401 once + test token refresh retry when pushing new local app
        val signedInToken = store.authorization(forceRefresh = false).accessToken
        service.rejectToken = signedInToken
        val secondApp = sampleCatalogApp(id = "id_calc", key = "calc")
        library.add(secondApp)
        coordinator.synchronize()?.join()

        assertEquals(HomeSyncPhase.Idle, coordinator.phase.value)
        assertEquals(listOf("web-resume", "id_calc"), service.remote.configuration.installedApps.map { it.appId })

        // Trigger conflict -> verify conflict phase -> resolve DEVICE pushes local over new remote revision
        val newerRemote = RemoteHomeScreen(
            schemaVersion = 3,
            revision = "c".repeat(64),
            configuration = HomeConfiguration(
                installedApps = listOf(HomeAppReference("yun-home")),
                updatedAt = 900L,
            ),
        )
        service.remote = newerRemote
        service.conflictNextSave = true
        val thirdApp = sampleCatalogApp(id = "id_notes", key = "notes")
        library.add(thirdApp)
        coordinator.synchronize()?.join()

        assertTrue(coordinator.phase.value is HomeSyncPhase.Conflict)
        coordinator.resolve(HomeSyncResolution.DEVICE)?.join()
        assertEquals(HomeSyncPhase.Idle, coordinator.phase.value)
        assertEquals(
            listOf("web-resume", "id_calc", "id_notes"),
            service.remote.configuration.installedApps.map { it.appId },
        )

        // Test CLOUD conflict resolution adopts remote and drops conflict
        service.remote = newerRemote
        service.conflictNextSave = true
        library.remove(thirdApp)
        coordinator.synchronize()?.join()
        assertTrue(coordinator.phase.value is HomeSyncPhase.Conflict)
        coordinator.resolve(HomeSyncResolution.CLOUD)
        assertEquals(HomeSyncPhase.Idle, coordinator.phase.value)
        assertEquals(listOf("yun-home"), library.snapshot.value.installedIds)
        assertNull(library.storageError.value)
    }
}
