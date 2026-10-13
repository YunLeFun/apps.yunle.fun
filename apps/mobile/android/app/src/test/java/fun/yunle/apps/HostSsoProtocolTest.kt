package `fun`.yunle.apps

import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostSsoProtocolTest {
    private val request = HostSsoProtocol.Request(
        clientId = "cms-web",
        codeChallenge = "c".repeat(43),
        nonce = "n".repeat(43),
        redirectUri = "https://cms.yunle.fun/",
        scope = "identity:bootstrap",
    )
    private val state = "s".repeat(43)

    @Test
    fun `system authorization URL preserves the registered PKCE binding`() {
        val url = URI(HostSsoProtocol.buildAuthorizationUrl(request, state))
        val query = query(url.rawQuery)

        assertEquals("https", url.scheme)
        assertEquals("www.yunle.fun", url.host)
        assertEquals("/auth/sso", url.path)
        assertEquals("cms-web", query["client_id"])
        assertEquals(request.redirectUri, query["redirect_uri"])
        assertEquals(request.codeChallenge, query["code_challenge"])
        assertEquals(request.nonce, query["nonce"])
        assertEquals("select_account", query["prompt"])
        assertEquals(
            "yunlefun://auth/sso?state=$state",
            query["native_callback_uri"],
        )
    }

    @Test
    fun `native callback accepts only the pending state nonce and redirect`() {
        val payload = Base64.getUrlEncoder().withoutPadding().encodeToString(
            "{\"nonce\":\"${request.nonce}\",\"iss\":\"https://www.yunle.fun\",\"ok\":true,\"code\":\"${"a".repeat(43)}\"}"
                .toByteArray(StandardCharsets.UTF_8),
        )
        val resultUrl = "${request.redirectUri}#ylf_sso=$payload"
        val callback = "yunlefun://auth/sso?state=$state&result=${encode(resultUrl)}"

        assertEquals(
            HostSsoProtocol.Result.Success("a".repeat(43), "https://www.yunle.fun"),
            HostSsoProtocol.readCallback(callback, state, request),
        )
        assertNull(HostSsoProtocol.readCallback(callback, "x".repeat(43), request))
        assertNull(
            HostSsoProtocol.readCallback(
                callback.replace("cms.yunle.fun", "evil.example"),
                state,
                request,
            ),
        )
    }

    private fun query(raw: String): Map<String, String> = raw.split('&').associate { pair ->
        val parts = pair.split('=', limit = 2)
        java.net.URLDecoder.decode(parts[0], StandardCharsets.UTF_8) to
            java.net.URLDecoder.decode(parts.getOrElse(1) { "" }, StandardCharsets.UTF_8)
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8)
}
