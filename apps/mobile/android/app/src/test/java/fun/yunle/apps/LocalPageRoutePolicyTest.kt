package `fun`.yunle.apps

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalPageRoutePolicyTest {
    @Test
    fun `app details accepts only the reviews target`() {
        assertEquals(
            LocalPageRequest("/app/give-me-money", "app-detail-sheet", "reviews"),
            LocalPageRoutePolicy.resolve("app-detail-sheet", "give-me-money", "reviews"),
        )
        assertNull(LocalPageRoutePolicy.resolve("app-detail-sheet", "cook", "overview"))
    }

    @Test
    fun `developer route encodes one safe path segment`() {
        assertEquals(
            LocalPageRequest("/developer/%E4%BA%91%E6%B8%B8%E5%90%9B", "developer-sheet", null),
            LocalPageRoutePolicy.resolve("developer-sheet", "云游君", null),
        )
    }

    @Test
    fun `route policy rejects traversal delimiters and unsupported kinds`() {
        listOf("", " ", ".", "..", "foo/bar", "foo\\bar", "foo?x", "foo#x", "foo%2Fbar")
            .forEach { value ->
                assertNull(LocalPageRoutePolicy.resolve("app-detail-sheet", value, null))
            }
        assertNull(LocalPageRoutePolicy.resolve("settings-sheet", "profile", null))
        assertNull(LocalPageRoutePolicy.resolve("developer-sheet", "yunyoujun", "reviews"))
    }

    @Test
    fun `context contains only the versioned allowlisted fields`() {
        assertEquals(
            "{\"version\":1,\"kind\":\"app-detail-sheet\",\"target\":\"reviews\"}",
            LocalPageRoutePolicy.resolve("app-detail-sheet", "cook", "reviews")?.contextJson(),
        )
    }
}
