package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class HomeLibraryTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun sampleApp(id: String) = CatalogApp(
        id = id,
        key = id,
        name = "应用 $id",
        description = "测试应用",
        author = "云乐坊",
        ownerLogin = "yunle",
        category = "效率",
        emoji = "✨",
        launchUrl = "https://$id.yunle.fun/",
        logo = null,
        themeColor = null,
        trustedHosts = emptyList(),
        immersive = false,
    )

    @Test
    fun `adds pins records usage and isolates libraries by account`() {
        val dir = File(tempFolder.root, "HomeLibrary")
        val library = HomeLibrary(dir)

        val app1 = sampleApp("one")
        val app2 = sampleApp("two")
        library.add(app1)
        library.setPinned(app2, true)
        library.recordUse(app1)

        assertTrue(library.contains("one"))
        assertTrue(library.contains("two"))
        assertEquals(listOf("two"), library.snapshot.value.dockIds)
        assertEquals("one", library.snapshot.value.recentEntries.first().appId)

        // Switching to user account gives a clean isolated home library
        library.activateAccount("alice@123")
        assertFalse(library.contains("one"))
        library.add(app2)

        // Switching back to guest restores guest items from disk
        library.activateAccount(null)
        assertTrue(library.contains("one"))
        assertTrue(library.contains("two"))
    }
}
