package `fun`.yunle.apps

import com.getcapacitor.JSObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExternalAuthProtocolTest {
    private val state = "native_${"s".repeat(43)}"
    private val authorizationUrl = "https://github.com/login/oauth/authorize" +
        "?client_id=client&state=$state" +
        "&redirect_uri=https%3A%2F%2Fcms.yunle.fun%2Fapi%2Fgithub%2Fcallback"

    @Test
    fun `accepts only the bound GitHub authorization request`() {
        val request = ExternalAuthProtocol.readRequest(
            JSObject().put("url", authorizationUrl).put("state", state),
        )

        assertEquals(state, request?.state)
        assertEquals(authorizationUrl, request?.url)
        assertNull(
            ExternalAuthProtocol.readRequest(
                JSObject()
                    .put("url", authorizationUrl.replace("github.com", "evil.example"))
                    .put("state", state),
            ),
        )
        assertNull(
            ExternalAuthProtocol.readRequest(
                JSObject().put("url", authorizationUrl).put("state", "native_${"x".repeat(43)}"),
            ),
        )
        assertNull(
            ExternalAuthProtocol.readRequest(
                JSObject()
                    .put("url", authorizationUrl.replace("cms.yunle.fun", "evil.example"))
                    .put("state", state),
            ),
        )
    }

    @Test
    fun `accepts only the fixed state-bound native callback`() {
        assertEquals(
            ExternalAuthProtocol.Status.SUCCESS,
            ExternalAuthProtocol.readCallback(
                "yunlefun://auth/external?state=$state&status=success",
                state,
            ),
        )
        assertEquals(
            ExternalAuthProtocol.Status.DENIED,
            ExternalAuthProtocol.readCallback(
                "yunlefun://auth/external?state=$state&status=denied",
                state,
            ),
        )
        assertNull(
            ExternalAuthProtocol.readCallback(
                "yunlefun://auth/external?state=${"native_${"x".repeat(43)}"}&status=success",
                state,
            ),
        )
        assertNull(
            ExternalAuthProtocol.readCallback(
                "yunlefun://auth/sso?state=$state&status=success",
                state,
            ),
        )
    }
}
