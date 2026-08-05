package `fun`.yunle.apps

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HostNavigationPolicyTest {
    @Test
    fun `release navigation accepts https and rejects cleartext`() {
        assertTrue(HostNavigationPolicy.isSupportedUrl("https://cms.yunle.fun/", false))
        assertFalse(HostNavigationPolicy.isSupportedUrl("http://cms.yunle.fun/", false))
        assertFalse(HostNavigationPolicy.isSupportedUrl("https:///missing-host", false))
    }

    @Test
    fun `message channel is registered only for the exact page origin`() {
        assertEquals(
            setOf("https://cms.yunle.fun"),
            HostNavigationPolicy.allowedOriginRules("https://cms.yunle.fun/editor?id=1", false),
        )
        assertFalse(
            HostNavigationPolicy.allowedOriginRules("https://cms.yunle.fun/", false).contains("*"),
        )
    }

    @Test
    fun `a WebView session is reusable only within its registered origin`() {
        assertTrue(
            HostNavigationPolicy.hasSameOrigin(
                "https://cms.yunle.fun/",
                "https://cms.yunle.fun/editor",
                false,
            ),
        )
        assertFalse(
            HostNavigationPolicy.hasSameOrigin(
                "https://cms.yunle.fun/",
                "https://play.yunle.fun/",
                false,
            ),
        )
    }
}
