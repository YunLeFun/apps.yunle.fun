package `fun`.yunle.apps

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogTest {
    private fun record() = JSONObject("""
        {"_id":"app_1","marketShortName":"cook","slug":"local-slug","name":"今天来做菜",
        "isPublic":true,"status":"approved","publicationStatus":"published","audience":"public",
        "accessMode":"public","websiteUrl":"https://cook.yunle.fun/home"}
    """.trimIndent())

    @Test
    fun approvedPublicApplicationCanOpenWithItsStableIdentity() {
        val app = requireNotNull(CatalogApp.read(record()))
        assertTrue(app.matches(" 做菜 "))
        assertEquals("cook", app.key)
        assertEquals("app_1", app.launchOptions()?.getJSONObject("app")?.getString("id"))
    }

    @Test
    fun privateAndUnpublishedRecordsNeverEnterTheCatalog() {
        assertNull(CatalogApp.read(record().put("audience", "workshop")))
        assertNull(CatalogApp.read(record().put("publicationStatus", "draft")))
    }

    @Test
    fun protectedOrInvalidLaunchTargetsCanOnlyOpenDetails() {
        val restricted = listOf(
            record().put("accessMode", "invite_only"),
            record().put("coinCost", 1),
            record().put("requiresMembership", true),
            record().put("isUnavailable", true),
            record().put("websiteUrl", "https://user:password@cook.yunle.fun"),
            record().put("websiteUrl", "http://cook.yunle.fun"),
            record().apply { remove("accessMode") },
        )
        for (item in restricted) assertNull(requireNotNull(CatalogApp.read(item)).launchOptions())
    }

    @Test
    fun canonicalAppDomainsNormalizeMigratedUrls() {
        val migrated = record()
            .put("_id", "gmm_id")
            .put("marketShortName", "give-me-money")
            .put("websiteUrl", "https://gmm.yunyoujun.cn")
        val app = requireNotNull(CatalogApp.read(migrated))
        assertEquals("https://gmm.yunle.fun/", app.launchUrl)
        assertEquals("https://gmm.yunle.fun/", app.launchOptions()?.getString("url"))

        val restrictedMigrated = migrated.put("requiresMembership", true)
        assertNull(requireNotNull(CatalogApp.read(restrictedMigrated)).launchUrl)
    }

    @Test
    fun parsesStoreMetadataRatingOfficialAndTags() {
        val enriched = record()
            .put("rating", 4.8)
            .put("isOfficial", true)
            .put("releaseStage", "stable")
            .put("tags", org.json.JSONArray(listOf("菜谱", "家常")))
        val app = requireNotNull(CatalogApp.read(enriched))
        assertEquals(4.8, app.rating ?: 0.0, 0.001)
        assertTrue(app.isOfficial)
        assertEquals("stable", app.releaseStage)
        assertEquals(listOf("菜谱", "家常"), app.tags)
        assertTrue(app.matches("家常"))
    }
}
