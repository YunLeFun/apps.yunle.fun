package `fun`.yunle.apps.webruntime

import `fun`.yunle.apps.CatalogApp
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WebProfileRepositoryTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private val cookApp = CatalogApp(
        id = "app_cook",
        key = "cook",
        name = "今天来做菜",
        description = "",
        author = "云乐坊",
        ownerLogin = "yunle",
        category = "生活",
        emoji = "🍳",
        launchUrl = "https://cook.yunle.fun/",
        logo = null,
        themeColor = null,
        trustedHosts = emptyList(),
        immersive = false,
    )

    @Test
    fun `isolates profiles across guest, accounts, and runtime scopes`() {
        val repo = WebProfileRepository(File(tempFolder.root, "ownership-v1.json"))

        val guestCook = repo.select(WebProfileRepository.Principal.Guest, cookApp)
        val aliceCook = repo.select(WebProfileRepository.Principal.Account("alice"), cookApp)
        val aliceCookWorkshop = repo.select(
            WebProfileRepository.Principal.Account("alice"),
            cookApp,
            runtimeScope = "workshop:w1",
        )

        assertNotEquals(guestCook.profileName, aliceCook.profileName)
        assertNotEquals(aliceCook.profileName, aliceCookWorkshop.profileName)
        assertEquals(guestCook.profileName, repo.select(WebProfileRepository.Principal.Guest, cookApp).profileName)
    }

    @Test
    fun `guest continuation adopts into empty account or retains when existing store exists`() {
        val repo = WebProfileRepository(File(tempFolder.root, "ownership-v1.json"))

        val guest1 = repo.select(WebProfileRepository.Principal.Guest, cookApp)
        val adopted = repo.bindGuestContinuation(guest1, accountID = "alice")
        assertTrue(adopted is WebProfileRepository.ContinuationDisposition.Adopted)
        assertEquals(
            guest1.identifier,
            repo.select(WebProfileRepository.Principal.Account("alice"), cookApp).identifier,
        )

        // Subsequent guest receives a brand-new profile
        val guest2 = repo.select(WebProfileRepository.Principal.Guest, cookApp)
        assertNotEquals(guest1.identifier, guest2.identifier)

        // Binding guest2 into Alice retains guest2 separately without overwriting Alice's active store
        val retained = repo.bindGuestContinuation(guest2, accountID = "alice")
        assertTrue(retained is WebProfileRepository.ContinuationDisposition.Retained)
        assertEquals(listOf(guest2.identifier), repo.retained(WebProfileRepository.Principal.Account("alice"), cookApp).map { it.identifier })

        // Retiring Alice moves active store to retained so re-login gets a clean store unless recovered
        repo.retire("alice")
        assertNull(repo.snapshot(WebProfileRepository.Principal.Account("alice"), cookApp).active)
        assertEquals(2, repo.retained(WebProfileRepository.Principal.Account("alice"), cookApp).size)
    }

    @Test
    fun `parses SSO request, policy, and code contracts`() {
        val rawRequest = JSONObject()
            .put("clientId", "cook-web")
            .put("redirectUri", "https://cook.yunle.fun/callback")
            .put("nonce", "n".repeat(48))
            .put("codeChallenge", "c".repeat(43))
            .put("codeChallengeMethod", "S256")
            .put("scope", JSONArray().put("identity:bootstrap"))

        val parsed = HostSsoRequest.parse("https://cook.yunle.fun", rawRequest)
        assertEquals("cook-web", parsed.clientID)

        val policyResponse = JSONObject()
            .put("ok", true)
            .put("issuer", HostSsoPolicy.ISSUER)
            .put("policyVersion", "v1")
            .put("registrationFingerprint", "a".repeat(64))
            .put("request", parsed.protocolFields())
            .put(
                "presentation",
                JSONObject()
                    .put("appId", "app-cook")
                    .put("applicationName", "今天来做菜")
                    .put("applicationOrigin", "https://cook.yunle.fun")
                    .put("permissionDescription", "账号标识、昵称和头像")
                    .put("consent", "explicit")
                    .put("prompt", "consent"),
            )

        val policy = HostSsoPolicy.parse(policyResponse, parsed)
        assertEquals("今天来做菜", policy.applicationName)

        val code = HostSsoCode.parse(JSONObject().put("ok", true).put("code", "x".repeat(43)).put("expiresAt", 123456))
        assertEquals("x".repeat(43), code.code)
        assertEquals(123456L, code.expiresAt)
    }
}
