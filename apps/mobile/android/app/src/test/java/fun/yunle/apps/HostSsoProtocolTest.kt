package `fun`.yunle.apps

import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.json.JSONObject

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
    fun `optional acquisition is allowlisted and never changes PKCE fields`() {
        val touch = JSONObject().put("capturedAt", 1000).put("landingHost", "cook.yunle.fun")
            .put("landingPath", "/random?token=private#code").put("referrerHost", "www.baidu.com")
            .put("utmSource", "百度").put("utmMedium", "organic").put("utmCampaign", "")
        val context = JSONObject().put("version", 1).put("firstTouch", touch).put("registerTouch", touch)
            .put("privateKey", "private")
        val optional = HostSsoProtocol.readAcquisitionJson(context)
        val fields = query(URI(HostSsoProtocol.buildAuthorizationUrl(request.copy(acquisitionJSON = optional), state)).rawQuery)
        val returned = JSONObject(fields["acquisition"]!!)
        assertEquals("/random", returned.getJSONObject("firstTouch").getString("landingPath"))
        assertEquals(false, returned.has("privateKey"))
        assertEquals("百度", returned.getJSONObject("firstTouch").getString("utmSource"))
        assertEquals(request.codeChallenge, fields["code_challenge"])
        assertEquals(request.nonce, fields["nonce"])
        assertEquals(request.redirectUri, fields["redirect_uri"])
        assertNull(HostSsoProtocol.readAcquisitionJson(JSONObject().put("version", 2)))
        assertNull(HostSsoProtocol.readAcquisitionJson(context.put("extra", "x".repeat(4097))))
        val invalid = query(URI(HostSsoProtocol.buildAuthorizationUrl(request.copy(acquisitionJSON = "invalid"), state)).rawQuery)
        assertEquals(false, invalid.containsKey("acquisition"))
        assertEquals(request.nonce, invalid["nonce"])
    }

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
