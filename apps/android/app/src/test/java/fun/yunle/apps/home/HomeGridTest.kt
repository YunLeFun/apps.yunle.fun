package `fun`.yunle.apps.home

import `fun`.yunle.apps.CatalogApp
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class HomeGridTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun app(id: String, category: String = "工具") = CatalogApp(
        id = id,
        key = id,
        name = "应用 $id",
        description = "测试应用",
        author = "云乐坊",
        ownerLogin = "yunle",
        category = category,
        emoji = "✨",
        launchUrl = "https://$id.yunle.fun/",
        logo = null,
        themeColor = null,
        trustedHosts = emptyList(),
        immersive = false,
    )

    @Test
    fun `HomeEditOrder moves single items and lands stacked items after primary`() {
        assertEquals(listOf("b", "c", "a", "d"), HomeEditOrder.moving("a", listOf("a", "b", "c", "d"), 2))
        assertEquals(listOf("d", "a", "b", "c"), HomeEditOrder.moving("d", listOf("a", "b", "c", "d"), 0))

        assertEquals(
            listOf("b", "a", "c", "d"),
            HomeEditOrder.landing(stack = listOf("c", "d"), afterPrimary = "a", inOrder = listOf("b", "a")),
        )
        assertEquals(
            listOf("a", "c", "d", "b"),
            HomeEditOrder.landing(stack = listOf("c", "d"), afterPrimary = "a", inOrder = listOf("a", "b", "c", "d")),
        )
    }

    @Test
    fun `HomeGridItem collapses folder members at first member slot and suggests category`() {
        val a = app("a", category = "效率")
        val b = app("b", category = "效率")
        val c = app("c", category = "生活")
        val folder = HomeFolder(id = "f1", name = "我的效率", appIds = listOf("b", "a"))

        val items = HomeGridItem.items(listOf(a, c, b), listOf(folder))
        assertEquals(2, items.size)
        assertTrue(items[0] is HomeGridItem.Folder)
        assertEquals(listOf("b", "a"), (items[0] as HomeGridItem.Folder).apps.map { it.id })
        assertEquals("c", items[1].id)

        assertEquals("效率", HomeGridItem.suggestedFolderName(listOf(a, b)))
        assertEquals("文件夹", HomeGridItem.suggestedFolderName(listOf(a, c)))
    }

    @Test
    fun `HomeLibrary creates renames reorders adds removes and dissolves folders and pins batch`() {
        val dir = File(tempFolder.root, "HomeFolders")
        val library = HomeLibrary(dir)
        val a = app("a")
        val b = app("b")
        val c = app("c")
        val d = app("d")
        val e = app("e")

        library.add(a)
        library.add(b)
        library.add(c)
        library.add(d)

        val folderId = library.createFolder("工作效率", listOf("a", "b"), anchor = "b")
        assertNotNull(folderId)
        assertEquals(1, library.snapshot.value.configuration.folders.size)
        assertEquals(listOf("a", "b"), library.snapshot.value.configuration.folders.first().appIds)

        library.renameFolder(folderId!!, "  日常工具  ")
        assertEquals("日常工具", library.snapshot.value.configuration.folders.first().name)

        library.addToFolder(folderId, listOf("c"))
        assertEquals(listOf("a", "b", "c"), library.snapshot.value.configuration.folders.first().appIds)

        library.reorderFolder(folderId, listOf("c", "a", "b"))
        assertEquals(listOf("c", "a", "b"), library.snapshot.value.configuration.folders.first().appIds)

        // Reorder items treats folder key atomically
        library.reorderItems(listOf("d", HomeGridItem.folderKey(folderId)))
        assertEquals(listOf("d", "c", "a", "b"), library.snapshot.value.installedIds)

        library.removeFromFolder("a")
        assertEquals(listOf("c", "b"), library.snapshot.value.configuration.folders.first().appIds)

        // Batch pin capacity check (4 max)
        assertTrue(library.setPinned(listOf(a, d), true))
        assertEquals(listOf("a", "d"), library.snapshot.value.dockIds)
        assertFalse(library.setPinned(listOf(b, c, e), true)) // 2 + 3 > 4 -> atomic reject
        assertEquals(listOf("a", "d"), library.snapshot.value.dockIds)

        library.dissolveFolder(folderId)
        assertTrue(library.snapshot.value.configuration.folders.isEmpty())
    }
}
