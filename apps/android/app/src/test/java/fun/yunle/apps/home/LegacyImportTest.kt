package `fun`.yunle.apps.home

import `fun`.yunle.apps.AppAppearance
import `fun`.yunle.apps.account.AccountAuthenticating
import `fun`.yunle.apps.account.AccountCredential
import `fun`.yunle.apps.account.AccountSession
import `fun`.yunle.apps.account.AccountStore
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.account.AccountVaultState
import `fun`.yunle.apps.account.CloudbaseAuthService
import `fun`.yunle.apps.account.InMemoryAccountVault
import `fun`.yunle.apps.account.SavedAccount
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LegacyImportTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun `rejects unknown keys and counts UTF-8 bytes`() {
        assertInvalid(mapOf("unknown_key" to "secret"))
        val key = "ylf:homescreen-sync-at"
        // A timestamp alone is retained without producing a Home configuration.
        val value = "多".repeat((LegacyLocalData.MAXIMUM_BYTES - key.length) / 3)
        assertNull(LegacyLocalData(mapOf(key to value)).configuration)
        assertInvalid(mapOf(key to "${value}多"))
    }

    @Test
    fun `account hints strip credentials and reject duplicate or invalid records`() {
        val key = "ylf_saved_accounts"
        val record = LegacyLocalData(mapOf(key to """
            [{"uid":"alice","nickname":"小云","accessToken":"secret","credential":{"refreshToken":"secret"}},
             {"uid":"bob","password":"secret"}]
        """.trimIndent()))
        assertEquals("""[{"uid":"alice","nickname":"小云"},{"uid":"bob"}]""", record.values[key])
        assertEquals(listOf("小云", "旧版账号"), record.accounts.map { it.label })
        assertEquals(record.id, LegacyLocalData(record.values).id)

        val tooMany = (1..11).joinToString(",", "[", "]") { """{"uid":"user-$it"}""" }
        listOf(
            tooMany,
            """[{"uid":"same"},{"uid":"same"}]""",
            """[{"uid":""}]""",
            """[{"uid":" alice"}]""",
            """[{"uid":"alice","nickname":"name\u007f"}]""",
            """[{"uid":"alice","nickname":"trailing "}]""",
            """[{"uid":"alice","nickname":false}]""",
            """[{"uid":"${"a".repeat(257)}"}]""",
        ).forEach { assertInvalid(mapOf(key to it)) }
    }

    @Test
    fun `options require supported values and Home fields require the legacy schema`() {
        val valid = mapOf(
            "ylf_theme_mode" to "system",
            "ylf:cloud-sync-enabled" to "false",
            "ylf:cloud-auto-sync" to "true",
            "ylf:dock-visible" to "true",
            "ylf_icon_style" to "liquid-glass",
            "ylf:preview-window-size" to "small",
            "ylf:in-app-browser-mode" to "immersive",
            "ylf:external-link-mode" to "safari-view",
            "ylf:session-limit-preference" to "7",
        )
        assertTrue(LegacyLocalData(valid).hasOtherSettings)
        valid.keys.forEach { assertInvalid(valid + (it to "invalid")) }
        listOf(
            mapOf("ylf:homescreen-apps" to """[{"appId":5}]"""),
            mapOf("ylf:dock-apps" to """[{"appId":"app"},{"appId":"app"}]"""),
            mapOf("ylf:recent-apps-v2" to """[{"appId":"app","usedAt":"123"}]"""),
            mapOf("ylf:homescreen-apps" to "[]", "ylf:homescreen-sync-at" to "-1"),
        ).forEach(::assertInvalid)
        assertEquals(HomeConfiguration(), LegacyLocalData(mapOf("ylf:dock-apps" to "[]")).configuration)
    }

    @Test
    fun `record id is the SHA-256 of compact sorted JSON`() {
        val first = LegacyLocalData(linkedMapOf("ylf_theme_mode" to "dark", "ylf:dock-visible" to "false"))
        val reversed = LegacyLocalData(first.values.entries.reversed().associate { it.toPair() })
        assertEquals("8a8341f4e1b0834a8fbdc53909df45d65fddd93e269f70fafa36b83e587222a1", first.id)
        assertEquals(first.id, reversed.id)
    }

    @Test
    fun `first load caches the scrubbed record and a new store reads it from disk`() = runBlocking {
        val fixture = Fixture()
        val values = recordValues + ("ylf_saved_accounts" to """[{"uid":"alice","token":"secret"}]""")
        var reads = 0
        val reader = LegacyLocalDataReading { reads++; values }

        val first = fixture.store(reader)
        first.load()
        assertTrue(first.isLoaded.value)
        assertFalse(first.isLoading.value)
        assertTrue(fixture.archiveFile.isFile)
        assertFalse(fixture.archiveFile.readText().contains("secret"))
        val second = fixture.store(reader)
        second.load()
        assertEquals(first.archive.value?.record?.id, second.archive.value?.record?.id)
        assertEquals(1, reads)
    }

    @Test
    fun `apply saves the claim before importing and creates a discoverable backup`() = runBlocking {
        val fixture = Fixture()
        fixture.library.add(fixture.library.snapshot.value.application("notes"))
        fixture.library.setDockVisible(false)
        val before = fixture.library.snapshot.value
        var persistedAppearance = AppAppearance.SYSTEM
        var homeChanges = 0
        fixture.library.onUserChange = {
            assertEquals(LegacyImportArchive.Claim(accountID = null), fixture.readArchive().claim)
            assertEquals(AppAppearance.SYSTEM, persistedAppearance)
            homeChanges++
        }
        val store = fixture.store(saveAppearance = { persistedAppearance = it; true })
        store.load()
        val confirmation = checkNotNull(store.prepareConfirmation())
        store.apply(confirmation)

        assertNull(store.error.value)
        assertEquals(LegacyImportArchive.Claim(accountID = null, completed = true), fixture.readArchive().claim)
        val snapshot = fixture.library.snapshot.value
        assertEquals(listOf("notes", "clock"), snapshot.installedIds)
        assertEquals(listOf("clock"), snapshot.dockIds)
        assertEquals(listOf(HomeRecentEntry("notes", 123L)), snapshot.recentEntries)
        assertEquals(456L, snapshot.configuration.updatedAt)
        assertEquals(before.cachedApplications, snapshot.cachedApplications)
        assertTrue(snapshot.hasPendingChanges)
        assertFalse(snapshot.syncEnabled)
        assertFalse(snapshot.autoSyncEnabled)
        assertTrue(snapshot.dockVisible)
        assertEquals(AppAppearance.DARK, persistedAppearance)
        assertEquals(1, homeChanges)

        val repository = HomeBackupRepository(fixture.library.storageDirectory)
        val ownerName = fixture.library.currentFileName
        val backup = repository.list(ownerName).single()
        assertEquals(HomeBackupKind.LEGACY, backup.kind)
        assertEquals("guest.before-legacy-${confirmation.recordID}.json", backup.id)
        assertEquals(before, repository.preview(backup.id, ownerName).snapshot)

        store.apply(confirmation)
        assertEquals(LegacyImportError.IDENTITY_CHANGED, store.error.value)
        assertNull(store.prepareConfirmation())
        fixture.accounts.select("alice")
        assertFalse(store.belongsToCurrentTarget)
        assertNull(store.visibleArchive)
        assertNull(store.prepareConfirmation())
        assertEquals(LegacyImportError.ALREADY_CLAIMED, store.error.value)
        assertFalse(fixture.library.contains("notes"))
    }

    @Test
    fun `a different account claiming the same record before apply wins`() = runBlocking {
        val fixture = Fixture()
        val store = fixture.store()
        store.load()
        val confirmation = checkNotNull(store.prepareConfirmation())
        val claimed = fixture.readArchive().copy(claim = LegacyImportArchive.Claim("alice"))
        fixture.archiveFile.writeText(claimed.toJson())

        store.apply(confirmation)

        assertEquals(LegacyImportError.ALREADY_CLAIMED, store.error.value)
        assertFalse(store.belongsToCurrentTarget)
        assertFalse(fixture.library.contains("notes"))
        assertEquals(claimed.claim, fixture.readArchive().claim)
    }

    @Test
    fun `identity generation alone invalidates a confirmation after switching back`() = runBlocking {
        val fixture = Fixture(activateHomeOnSelection = false)
        fixture.accounts.select("alice")
        fixture.library.activateAccount("alice")
        val store = fixture.store()
        store.load()
        val confirmation = checkNotNull(store.prepareConfirmation())
        fixture.accounts.select("bob")
        fixture.accounts.select("alice")
        assertEquals(confirmation.libraryGeneration, fixture.library.generation.value)

        store.apply(confirmation)
        assertEquals(LegacyImportError.IDENTITY_CHANGED, store.error.value)
        assertNull(fixture.readArchive().claim)
        assertFalse(fixture.library.contains("notes"))
    }

    @Test
    fun `a changed Home generation invalidates a confirmation`() = runBlocking {
        val fixture = Fixture()
        val store = fixture.store()
        store.load()
        val confirmation = checkNotNull(store.prepareConfirmation())
        fixture.library.activateAccount("alice")
        fixture.library.activateAccount(null)

        store.apply(confirmation)
        assertEquals(LegacyImportError.IDENTITY_CHANGED, store.error.value)
        assertNull(fixture.readArchive().claim)
    }

    @Test
    fun `archive replaced on disk after preview requires a new read`() = runBlocking {
        val fixture = Fixture()
        val store = fixture.store()
        store.load()
        val confirmation = checkNotNull(store.prepareConfirmation())
        val replacement = LegacyImportArchive(record = LegacyLocalData(mapOf("ylf_theme_mode" to "light")))
        fixture.archiveFile.writeText(replacement.toJson())

        store.apply(confirmation)
        assertEquals(LegacyImportError.RECORD_CHANGED, store.error.value)
        assertFalse(store.isLoaded.value)
        assertNull(fixture.readArchive().claim)
        assertFalse(fixture.library.contains("notes"))
        store.load(retry = true)
        assertNotNull(store.prepareConfirmation())
    }

    @Test
    fun `an archive written during the read keeps its claim`() = runBlocking {
        val fixture = Fixture()
        val started = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        val waiting = fixture.store(LegacyLocalDataReading {
            started.complete(Unit)
            finish.await()
            emptyMap()
        })
        val load = launch { waiting.load() }
        started.await()

        val writer = fixture.store()
        writer.load()
        writer.apply(checkNotNull(writer.prepareConfirmation()))
        finish.complete(Unit)
        load.join()

        assertEquals(writer.archive.value?.record?.id, waiting.archive.value?.record?.id)
        assertTrue(waiting.archive.value?.claim?.completed == true)
    }

    @Test
    fun `oversized archive is preserved without invoking the reader`() = runBlocking {
        val fixture = Fixture()
        fixture.archiveFile.parentFile!!.mkdirs()
        fixture.archiveFile.writeBytes(ByteArray(1_048_577))
        val store = fixture.store(LegacyLocalDataReading { error("Unexpected reader invocation") })

        store.load()

        assertEquals(LegacyImportError.INVALID_DATA, store.error.value)
        assertEquals(1_048_577L, fixture.archiveFile.length())
        assertFalse(store.isLoaded.value)
    }

    @Test
    fun `retry after a settings write fails does not reapply Home or replace its backup`() = runBlocking {
        val fixture = Fixture()
        val before = fixture.library.snapshot.value
        val first = fixture.store(saveAppearance = { false })
        first.load()
        first.apply(checkNotNull(first.prepareConfirmation()))
        assertEquals(LegacyImportError.STORAGE, first.error.value)
        assertFalse(checkNotNull(fixture.readArchive().claim).completed)

        val reloadedLibrary = HomeLibrary(fixture.library.storageDirectory)
        val imported = reloadedLibrary.snapshot.value
        val retry = fixture.store(library = reloadedLibrary)
        retry.load()
        retry.apply(checkNotNull(retry.prepareConfirmation()))

        assertNull(retry.error.value)
        assertTrue(checkNotNull(fixture.readArchive().claim).completed)
        assertEquals(imported, reloadedLibrary.snapshot.value)
        val repository = HomeBackupRepository(reloadedLibrary.storageDirectory)
        val ownerName = reloadedLibrary.currentFileName
        val backup = repository.list(ownerName).single()
        assertEquals(before, repository.preview(backup.id, ownerName).snapshot)
    }

    @Test
    fun `quick close and reopen awaits the in-flight load and finishes cleanly`() = runBlocking {
        val fixture = Fixture()
        var reads = 0
        val started = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        val store = fixture.store(LegacyLocalDataReading {
            reads++
            started.complete(Unit)
            finish.await()
            recordValues
        })

        val first = launch { store.load() }
        started.await()
        first.cancelAndJoin()

        val second = launch { store.load() }
        finish.complete(Unit)
        second.join()

        assertTrue(store.isLoaded.value)
        assertFalse(store.isLoading.value)
        assertNull(store.error.value)
        assertEquals(1, reads)
        assertNotNull(store.archive.value)
        assertNotNull(store.prepareConfirmation())
    }

    @Test
    fun `unwritable destination fails apply without leaving an orphan durable claim`() = runBlocking {
        val libraryDir = tempFolder.newFolder("UnwritableGuest")
        File(libraryDir, "guest.json").writeText("{not-json")
        val library = HomeLibrary(libraryDir)
        val fixture = Fixture(customLibrary = library)
        val store = fixture.store(library = library)
        store.load()
        val confirmation = checkNotNull(store.prepareConfirmation())

        store.apply(confirmation)

        assertEquals(LegacyImportError.STORAGE, store.error.value)
        assertNull(fixture.readArchive().claim)
        assertNull(store.archive.value?.claim)

        fixture.accounts.select("alice")
        store.apply(checkNotNull(store.prepareConfirmation()))

        assertNull(store.error.value)
        assertEquals(LegacyImportArchive.Claim("alice", completed = true), fixture.readArchive().claim)
        assertTrue(library.contains("notes"))
    }

    private fun assertInvalid(values: Map<String, String>) {
        val error = assertThrows(LegacyImportException::class.java) { LegacyLocalData(values) }
        assertEquals(LegacyImportError.INVALID_DATA, error.error)
    }

    private inner class Fixture(
        activateHomeOnSelection: Boolean = true,
        customLibrary: HomeLibrary? = null,
    ) {
        val library = customLibrary ?: HomeLibrary(tempFolder.newFolder("HomeLibrary"))
        private val archiveDirectory = File(tempFolder.root, "LegacyImport")
        val archiveFile = File(archiveDirectory, "record-v1.json")
        private val savedAccounts = listOf("alice", "bob").map { id ->
            SavedAccount(
                user = AccountUser(id = id, name = id),
                credential = AccountCredential(id, "refresh-$id", Long.MAX_VALUE),
            )
        }
        private val api = object : AccountAuthenticating by CloudbaseAuthService() {
            override suspend fun user(accessToken: String, deviceID: String): AccountUser =
                savedAccounts.first { it.credential.accessToken == accessToken }.user
        }
        private val vault = InMemoryAccountVault(AccountVaultState(accounts = savedAccounts).toJson().toString().toByteArray())
        val accounts = AccountStore(
            session = AccountSession(api = api, vault = vault),
            identityDidChange = { if (activateHomeOnSelection) library.activateAccount(it) },
        )

        fun store(
            reader: LegacyLocalDataReading = LegacyLocalDataReading { recordValues },
            library: HomeLibrary = this.library,
            saveAppearance: (AppAppearance) -> Boolean = { true },
        ) = LegacyImportStore(library, accounts, reader, archiveDirectory, saveAppearance)

        fun readArchive(): LegacyImportArchive = LegacyImportArchive.fromJson(archiveFile.readText())
    }

    private companion object {
        val recordValues = mapOf(
            "ylf:homescreen-apps" to """[{"appId":"notes"},{"appId":"clock"}]""",
            "ylf:dock-apps" to """[{"appId":"clock"}]""",
            "ylf:recent-apps-v2" to """[{"appId":"notes","usedAt":123}]""",
            "ylf:homescreen-sync-at" to "456",
            "ylf_theme_mode" to "dark",
            "ylf:cloud-sync-enabled" to "false",
            "ylf:cloud-auto-sync" to "false",
            "ylf:dock-visible" to "true",
        )
    }
}
