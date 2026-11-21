package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files
import java.util.Base64
import java.util.UUID

class HomeBackupTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun app(id: String, name: String = "应用 $id") = CatalogApp(
        id = id,
        key = id,
        name = name,
        description = "测试应用",
        author = "云乐坊",
        ownerLogin = "yunle",
        category = "效率",
        emoji = "☁️",
        launchUrl = "https://$id.yunle.fun/",
        logo = null,
        themeColor = null,
        trustedHosts = listOf("$id.yunle.fun"),
        immersive = false,
    )

    @Test
    fun `validates all four backup filename patterns and rejects unsafe names`() {
        val uuid = UUID.randomUUID().toString()
        val digest = "a".repeat(64)
        val owner = "guest.json"

        assertEquals(HomeBackupKind.CONFLICT, HomeBackupRepository.kind("guest.conflict-$uuid.json", owner))
        assertEquals(HomeBackupKind.RESTORE, HomeBackupRepository.kind("guest.before-restore-$uuid.json", owner))
        assertEquals(HomeBackupKind.LEGACY, HomeBackupRepository.kind("guest.before-legacy-$digest.json", owner))
        assertEquals(
            HomeBackupKind.NATIVE_MIGRATION,
            HomeBackupRepository.kind("guest.before-native-migration-$digest.json", owner),
        )

        assertNull(HomeBackupRepository.kind("../guest.conflict-$uuid.json", owner))
        assertNull(HomeBackupRepository.kind("other.conflict-$uuid.json", owner))
        assertNull(HomeBackupRepository.kind("guest.conflict-not-a-uuid.json", owner))
        assertNull(HomeBackupRepository.kind("guest.before-legacy-${"A".repeat(64)}.json", owner))
        assertNull(HomeBackupRepository.kind("guest.before-legacy-${"a".repeat(63)}.json", owner))
    }

    @Test
    fun `keepCloud writes conflict backup preserving prior local applications`() {
        val dir = File(tempFolder.root, "HomeLibrary")
        val library = HomeLibrary(dir)
        library.activateAccount("alice")
        library.add(app("local_app", "本地应用"))
        assertEquals(listOf("local_app"), library.snapshot.value.installedIds)

        val remote = RemoteHomeScreen(
            schemaVersion = 3,
            revision = "b".repeat(64),
            configuration = HomeConfiguration(
                installedApps = listOf(HomeAppReference("cloud_app")),
                updatedAt = 500L,
            ),
        )
        val generationBefore = library.generation.value
        library.keepCloud(remote, expectedAccountId = "alice", catalog = listOf(app("cloud_app", "云端应用")))

        assertEquals(listOf("cloud_app"), library.snapshot.value.installedIds)
        assertFalse(library.snapshot.value.hasPendingChanges)
        assertTrue(library.generation.value > generationBefore)

        val repo = HomeBackupRepository(dir)
        val backups = repo.list(library.currentFileName)
        assertEquals(1, backups.size)
        assertEquals(HomeBackupKind.CONFLICT, backups[0].kind)

        val preview = repo.preview(backups[0].id, library.currentFileName)
        assertEquals(listOf("local_app"), preview.snapshot.installedIds)
        assertEquals(64, preview.sha256Digest.length)
    }

    @Test
    fun `repository isolates accounts and rejects symlinks or corrupt files`() {
        val dir = File(tempFolder.root, "HomeIso")
        dir.mkdirs()
        val guestOwner = "guest.json"
        val aliceName = Base64.getUrlEncoder().withoutPadding().encodeToString("alice".toByteArray(Charsets.UTF_8)) + ".json"

        val lib = HomeLibrary(dir)
        lib.add(app("guest_one"))
        val guestBackupId = "guest.conflict-${UUID.randomUUID()}.json"
        File(dir, guestOwner).copyTo(File(dir, guestBackupId))

        val aliceBackupId = "${aliceName.removeSuffix(".json")}.conflict-${UUID.randomUUID()}.json"
        File(dir, guestOwner).copyTo(File(dir, aliceBackupId))

        val corruptId = "guest.before-restore-${UUID.randomUUID()}.json"
        File(dir, corruptId).writeText("{not-json")

        val externalTarget = File(tempFolder.root, "outside.json").apply { writeText("{}") }
        val symlinkId = "guest.conflict-${UUID.randomUUID()}.json"
        val symlinkCreated = runCatching {
            Files.createSymbolicLink(File(dir, symlinkId).toPath(), externalTarget.toPath())
        }.isSuccess

        val repo = HomeBackupRepository(dir)
        val aliceList = repo.list(aliceName)
        assertEquals(listOf(aliceBackupId), aliceList.map { it.id })

        val guestIds = repo.list(guestOwner).map { it.id }
        assertTrue(guestIds.contains(guestBackupId))
        assertFalse(guestIds.contains(aliceBackupId))
        if (symlinkCreated) assertFalse(guestIds.contains(symlinkId))

        val thrown = runCatching { repo.preview(corruptId, guestOwner) }.exceptionOrNull()
        assertTrue(thrown is HomeBackupException)
        assertEquals(HomeBackupError.UNREADABLE, (thrown as HomeBackupException).error)
    }

    @Test
    fun `restoreBackup enforces boundaries is idempotent and recovers corrupted primary file`() {
        val dir = File(tempFolder.root, "HomeRestore")
        val library = HomeLibrary(dir)
        library.add(app("app_old", "旧应用"))
        library.setSyncEnabled(false)
        val savedSnap = library.snapshot.value

        val backupId = "guest.before-restore-${UUID.randomUUID()}.json"
        File(dir, "guest.json").copyTo(File(dir, backupId))
        val preview = HomeBackupRepository(dir).preview(backupId, "guest.json")

        // Mutate state & corrupt primary file on disk, then re-open library to simulate recovery state
        library.add(app("app_new"))
        File(dir, "guest.json").writeText("{corrupt")
        val corruptedLibrary = HomeLibrary(dir)
        assertTrue(corruptedLibrary.needsRecovery)

        // Wrong account or stale generation must fail cleanly
        assertFalse(
            corruptedLibrary.restoreBackup(
                restored = preview.snapshot,
                restoreSettings = true,
                restoreId = "restore-1",
                expectedAccountId = "wrong-user",
                expectedGeneration = corruptedLibrary.generation.value,
            ),
        )
        assertFalse(
            corruptedLibrary.restoreBackup(
                restored = preview.snapshot,
                restoreSettings = true,
                restoreId = "restore-1",
                expectedAccountId = null,
                expectedGeneration = corruptedLibrary.generation.value + 99,
            ),
        )

        // Valid restore preserves corrupt primary in before-restore backup and restores state
        val gen = corruptedLibrary.generation.value
        assertTrue(
            corruptedLibrary.restoreBackup(
                restored = savedSnap,
                restoreSettings = false,
                restoreId = "restore-1",
                expectedAccountId = null,
                expectedGeneration = gen,
            ),
        )
        assertFalse(corruptedLibrary.needsRecovery)
        assertEquals(listOf("app_old"), corruptedLibrary.snapshot.value.installedIds)
        assertTrue(corruptedLibrary.snapshot.value.syncEnabled) // restoreSettings = false kept current default
        assertEquals("restore-1", corruptedLibrary.snapshot.value.lastRestoreId)

        // Idempotent repeat call for same restoreId succeeds without overwriting or adding duplicate backups
        val countAfterFirst = HomeBackupRepository(dir).list("guest.json").size
        assertTrue(
            corruptedLibrary.restoreBackup(
                restored = savedSnap,
                restoreSettings = true,
                restoreId = "restore-1",
                expectedAccountId = null,
                expectedGeneration = corruptedLibrary.generation.value,
            ),
        )
        assertEquals(countAfterFirst, HomeBackupRepository(dir).list("guest.json").size)
        assertTrue(
            HomeBackupRepository(dir).list("guest.json").any { it.kind == HomeBackupKind.RESTORE },
        )
    }
}
