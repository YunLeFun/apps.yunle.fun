package `fun`.yunle.apps

import android.content.ComponentCallbacks2
import `fun`.yunle.apps.account.AccountRequestBoundary
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HostSessionPoolTest {
    private class FakeWebHandle : RuntimeWebHandle {
        var paused = 0
        var resumed = 0
        var detached = 0
        var destroyed = 0

        override fun pause() {
            paused++
        }

        override fun resume() {
            resumed++
        }

        override fun detachFromParent() {
            detached++
        }

        override fun destroy() {
            destroyed++
        }
    }

    @After
    fun tearDown() {
        HostSession.closeAll()
        HostSession.setMaxPoolSizeForTesting(null)
    }

    private fun makeSession(
        key: String,
        url: String = "https://$key.yunle.fun/",
        boundary: AccountRequestBoundary = AccountRequestBoundary("u1", UUID(1L, 1L)),
        handle: FakeWebHandle = FakeWebHandle(),
    ): Pair<PooledWebSession, FakeWebHandle> {
        val session = PooledWebSession(
            sessionKey = key,
            appId = key,
            appName = "App $key",
            launchUrl = url,
            optionsJson = """{"url":"$url","title":"App $key","app":{"id":"$key"}}""",
            accountBoundary = boundary,
            handle = handle,
            lastUsedAtMillis = System.currentTimeMillis(),
        )
        return session to handle
    }

    @Test
    fun lruEvictionDestroysOldestPooledSessionOverCap() {
        HostSession.setMaxPoolSizeForTesting(3) // 1 foreground + max 2 pooled
        val (s1, h1) = makeSession("a1")
        val (s2, h2) = makeSession("a2")
        val (s3, h3) = makeSession("a3")

        HostSession.parkWebView(s1, maxSessions = 3)
        assertEquals(1, h1.paused)
        assertEquals(1, h1.detached)
        assertEquals(0, h1.destroyed)

        HostSession.parkWebView(s2, maxSessions = 3)
        assertEquals(listOf("a1", "a2"), HostSession.pooledKeysForTesting())
        assertEquals(0, h1.destroyed)
        assertEquals(0, h2.destroyed)

        HostSession.parkWebView(s3, maxSessions = 3)
        assertEquals(listOf("a2", "a3"), HostSession.pooledKeysForTesting())
        assertEquals(1, h1.destroyed)
        assertEquals(0, h2.destroyed)
        assertEquals(0, h3.destroyed)
        assertEquals(listOf("a3", "a2"), HostSession.runningSessions.value.map { it.sessionKey })
    }

    @Test
    fun capOfOneEvictsAndDestroysImmediately() {
        val (s1, h1) = makeSession("a1")
        HostSession.parkWebView(s1, maxSessions = 1)
        assertEquals(emptyList<String>(), HostSession.pooledKeysForTesting())
        assertEquals(1, h1.destroyed)
    }

    @Test
    fun takePooledResumesMatchingAndRejectsBoundaryMismatch() {
        val b1 = AccountRequestBoundary("u1", UUID(1L, 1L))
        val b2 = AccountRequestBoundary("u2", UUID(2L, 2L))
        val (s1, h1) = makeSession("a1", boundary = b1)
        val (s2, h2) = makeSession("a2", boundary = b1)
        HostSession.parkWebView(s1, maxSessions = 4)
        HostSession.parkWebView(s2, maxSessions = 4)

        val hit = HostSession.takePooledWebView("a1", "https://a1.yunle.fun/", b1)
        assertNotNull(hit)
        assertEquals(1, h1.resumed)
        assertEquals(0, h1.destroyed)

        val mismatched = HostSession.takePooledWebView("a2", "https://a2.yunle.fun/", b2)
        assertNull(mismatched)
        assertEquals(1, h2.destroyed)
        assertFalse(HostSession.pooledKeysForTesting().contains("a2"))
    }

    @Test
    fun trimMemoryAndCloseSessionAndCloseAllDestroyHandles() {
        val (s1, h1) = makeSession("a1")
        val (s2, h2) = makeSession("a2")
        HostSession.parkWebView(s1, maxSessions = 4)
        HostSession.parkWebView(s2, maxSessions = 4)

        HostSession.closeSession("a1")
        assertEquals(1, h1.destroyed)
        assertEquals(listOf("a2"), HostSession.pooledKeysForTesting())

        HostSession.trimMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
        assertEquals(1, h2.destroyed)
        assertTrue(HostSession.pooledKeysForTesting().isEmpty())
    }
}
