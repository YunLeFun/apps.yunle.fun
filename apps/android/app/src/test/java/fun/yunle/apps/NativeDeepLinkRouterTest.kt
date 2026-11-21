package `fun`.yunle.apps

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class NativeDeepLinkRouterTest {
    private val validChallenge = "A".repeat(43)
    private val validNonce = "N".repeat(32)
    private val validRedirect = "https://client.yunle.fun/auth/callback"

    private fun buildAuthUrl(extra: String = ""): String = buildString {
        append("https://www.yunle.fun/auth/app")
        append("?client_id=partner-app")
        append("&redirect_uri=").append(java.net.URLEncoder.encode(validRedirect, "UTF-8"))
        append("&scope=identity:bootstrap")
        append("&nonce=").append(validNonce)
        append("&code_challenge=").append(validChallenge)
        append("&code_challenge_method=S256")
        if (extra.isNotEmpty()) append("&").append(extra)
    }

    @Test
    fun workshopLinkNormalizesAndRejectsDisallowedCharacters() {
        assertEquals("2345AB", WorkshopLink.normalize(" 2345ab "))
        assertNull(WorkshopLink.normalize("2345IO"))
        assertNull(WorkshopLink.normalize("2345L0"))
        assertNull(WorkshopLink.normalize("23451A"))
        assertNull(WorkshopLink.normalize("2345A"))

        assertEquals("2345AB", WorkshopLink.parse("https://apps.yunle.fun/w/2345ab/"))
        assertNull(WorkshopLink.parse("https://apps.yunle.fun/w/2345AB?from=qr"))
        assertNull(WorkshopLink.parse("https://user@apps.yunle.fun/w/2345AB"))
        assertNull(WorkshopLink.parse("https://evil.example.com/w/2345AB"))
    }

    @Test
    fun parsesUniversalAndCustomSchemeDestinationsAndRejectsMalformed() {
        assertEquals(
            NativeDestination.Application("cook"),
            NativeDeepLinkRouter.parse("https://apps.yunle.fun/app/cook"),
        )
        assertEquals(
            NativeDestination.Workshop("2345AB"),
            NativeDeepLinkRouter.parse("https://apps.yunle.fun/w/2345ab/"),
        )
        assertEquals(
            NativeDestination.Developer("YunYouJun"),
            NativeDeepLinkRouter.parse("https://apps.yunle.fun/developer/YunYouJun"),
        )
        assertEquals(
            NativeDestination.Application("cook"),
            NativeDeepLinkRouter.parse("yunlefun://app/cook"),
        )
        assertEquals(
            NativeDestination.Workshop("2345AB"),
            NativeDeepLinkRouter.parse("yunlefun://workshop/2345ab"),
        )
        assertEquals(
            NativeDestination.Developer("YunYouJun"),
            NativeDeepLinkRouter.parse("yunlefun://developer/YunYouJun"),
        )

        assertNull(NativeDeepLinkRouter.parse(null))
        assertNull(NativeDeepLinkRouter.parse("https://apps.yunle.fun/app/cook?foo=bar"))
        assertNull(NativeDeepLinkRouter.parse("https://apps.yunle.fun/app/cook#frag"))
        assertNull(NativeDeepLinkRouter.parse("https://user@apps.yunle.fun/app/cook"))
        assertNull(NativeDeepLinkRouter.parse("https://apps.yunle.fun/app/../etc"))
        assertNull(NativeDeepLinkRouter.parse("http://apps.yunle.fun/app/cook"))
    }

    @Test
    fun validatesCrossAppAuthorizationRequestsStrictly() {
        val parsed = CrossAppAuthorizationLink.parse(buildAuthUrl())
        assertEquals(
            CrossAppAuthorizationRequest(
                clientId = "partner-app",
                redirectUri = validRedirect,
                nonce = validNonce,
                codeChallenge = validChallenge,
            ),
            parsed,
        )
        assertEquals("https://client.yunle.fun", parsed!!.sourceOrigin)
        val ssoRequest = parsed.toHostSsoRequest()
        assertNull(ssoRequest.prompt)
        assertEquals("partner-app", ssoRequest.clientID)

        // Optional allowed prompts succeed
        assertEquals(parsed, CrossAppAuthorizationLink.parse(buildAuthUrl("prompt=consent")))
        assertEquals(parsed, CrossAppAuthorizationLink.parse(buildAuthUrl("prompt=select_account")))
        assertTrue(NativeDeepLinkRouter.parse(buildAuthUrl()) is NativeDestination.CrossAppAuth)

        // Malformed entry routes must map to InvalidCrossAppAuth, never null or app browse
        val invalidUrls = listOf(
            buildAuthUrl("client_id=other"), // duplicate key
            buildAuthUrl("extra=1"), // unknown parameter
            buildAuthUrl("prompt=none"), // prompt=none forbidden
            buildAuthUrl("native_callback_uri=yunlefun://x"), // disallowed parameter
            "${buildAuthUrl()}#frag", // fragment forbidden
            "https://www.yunle.fun:8443/auth/app?client_id=partner-app", // explicit port
            buildAuthUrl().replace("nonce=$validNonce", "nonce=short"), // short nonce
            buildAuthUrl().replace("code_challenge=$validChallenge", "code_challenge=bad"), // bad challenge
            buildAuthUrl().replace("code_challenge_method=S256", "code_challenge_method=plain"), // non-S256
        )
        for (url in invalidUrls) {
            assertNull("Expected null for $url", CrossAppAuthorizationLink.parse(url))
            assertEquals(NativeDestination.InvalidCrossAppAuth, NativeDeepLinkRouter.parse(url))
        }
    }

    @Test
    fun encodesExactCrossAppRedirectPayloads() {
        val request = CrossAppAuthorizationRequest(
            clientId = "partner-app",
            redirectUri = validRedirect,
            nonce = validNonce,
            codeChallenge = validChallenge,
        )
        val validCode = "B".repeat(43)
        val approvedUrl = CrossAppRedirect.Approved(validCode).callbackUrl(request)!!
        assertTrue(approvedUrl.startsWith("$validRedirect#ylf_sso="))
        val approvedEncoded = approvedUrl.substringAfter("#ylf_sso=")
        assertFalse(approvedEncoded.contains('='))
        assertEquals(
            """{"nonce":"$validNonce","iss":"https://www.yunle.fun","ok":true,"code":"$validCode"}""",
            String(Base64.getUrlDecoder().decode(approvedEncoded), Charsets.UTF_8),
        )
        assertNull(CrossAppRedirect.Approved("too-short").callbackUrl(request))

        val deniedEncoded = CrossAppRedirect.Denied.callbackUrl(request)!!.substringAfter("#ylf_sso=")
        assertEquals(
            """{"nonce":"$validNonce","iss":"https://www.yunle.fun","ok":false,"reason":"access_denied"}""",
            String(Base64.getUrlDecoder().decode(deniedEncoded), Charsets.UTF_8),
        )

        val accountEncoded = CrossAppRedirect.AccountSelectionRequired.callbackUrl(request)!!
            .substringAfter("#ylf_sso=")
        assertEquals(
            """{"nonce":"$validNonce","iss":"https://www.yunle.fun","ok":false,"reason":"account_selection_required"}""",
            String(Base64.getUrlDecoder().decode(accountEncoded), Charsets.UTF_8),
        )
    }
}
