package `fun`.yunle.apps

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewFeature
import `fun`.yunle.apps.account.AccountAuthenticating
import `fun`.yunle.apps.account.AccountSession
import `fun`.yunle.apps.account.AccountUser
import `fun`.yunle.apps.account.AuthTokenResponse
import `fun`.yunle.apps.account.CloudbaseAuthService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

@RunWith(AndroidJUnit4::class)
class WebProfileIsolationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test
    fun accountSwitchPreservesLegacyAndIsolatedData() {
        val run = UUID.randomUUID().toString()
        val legacyToken = InstrumentationRegistry.getArguments().getString("legacyUpgradeFixture")
        val legacyOrigin = if (legacyToken == null) "https://legacy-fixture.invalid/" else "https://localhost/"
        val legacyValue = legacyToken ?: run
        val defaultWebView = openLegacyOrigin(legacyOrigin)
        try {
            if (legacyToken == null) {
                eval(defaultWebView, "localStorage.setItem('ylf-upgrade-fixture', '$legacyValue')")
                onMain {
                    CookieManager.getInstance().setCookie(legacyOrigin, "ylfUpgrade=$legacyValue; Path=/; Secure")
                    CookieManager.getInstance().flush()
                }
            }
            assertLegacyData(defaultWebView, legacyOrigin, legacyValue, legacyToken != null)
            val alice = "alice-$run"
            val bob = "bob-$run"
            onMain {
                YunleContainer.ensureInitialized(context, AccountSession(api = FixtureAccounts))
                check(YunleContainer.accounts.overview.value.users.isEmpty()) { "Use an isolated test installation" }
                // Keep the fixture local even though sync defaults to enabled for real accounts.
                for (id in listOf(alice, bob, null)) {
                    YunleContainer.homeLibrary.activateAccount(id)
                    if (id != null) YunleContainer.homeLibrary.setSyncEnabled(false)
                }
            }

            val supportsProfiles = onMain { WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) }
            val expectUnsupported = InstrumentationRegistry.getArguments().getString("expectNoMultiProfile") == "1"
            assertEquals("Verify the selected device's real WebView mode", !expectUnsupported, supportsProfiles)
            withLocalPage { url ->
                val app = fixtureApp(run, url)
                signIn(alice)
                onMain { YunleContainer.homeLibrary.add(app) }
                if (supportsProfiles) {
                    val host = openHost(app)
                    val view = requireWeb(host)
                    writeAppData(view, alice)
                    signIn(bob)
                    assertTrue(onMain { host.isFinishing || host.isDestroyed })
                    assertFalse(onMain { YunleContainer.homeLibrary.contains(app) })
                    withHost(app) { second ->
                        assertAppData(requireWeb(second), null)
                        writeAppData(requireWeb(second), bob)
                    }
                    select(alice)
                    assertTrue(onMain { YunleContainer.homeLibrary.contains(app) })
                    withHost(app) { assertAppData(requireWeb(it), alice) }
                    select(bob)
                    withHost(app) { assertAppData(requireWeb(it), bob) }
                    assertBrokenProfileIndexDoesNotLoad(app)
                } else {
                    signIn(bob)
                    assertFalse(onMain { YunleContainer.homeLibrary.contains(app) })
                    select(alice)
                    assertTrue(onMain { YunleContainer.homeLibrary.contains(app) })
                    withHost(app) { assertBlocked(it, "当前 WebView 版本无法打开云应用") }
                }
                assertLegacyData(defaultWebView, legacyOrigin, legacyValue, legacyToken != null)
            }
        } finally {
            onMain {
                defaultWebView.destroy()
                HostSession.closeAll()
            }
        }
    }

    private fun assertBrokenProfileIndexDoesNotLoad(app: CatalogApp) {
        val index = File(context.noBackupFilesDir, "WebProfiles/ownership-v1.json")
        val data = index.readBytes()
        val invalid = """{"version":1,"active":[],"retained":{}}"""
        try {
            index.writeText(invalid)
            withHost(app) { assertBlocked(it, "暂时无法打开云应用") }
            assertEquals(invalid, index.readText())
        } finally {
            index.writeBytes(data)
        }
    }

    private fun assertBlocked(host: HostWebViewActivity, title: String) = onMain {
        val views = descendants(host.window.decorView).toList()
        assertNull(views.filterIsInstance<WebView>().firstOrNull())
        assertNull(HostSession.current())
        assertTrue(views.filterIsInstance<TextView>().any { it.text.toString() == title && it.isShown })
    }

    private fun assertLegacyData(view: WebView, origin: String, token: String, checkDatabase: Boolean) {
        assertEquals(token, eval(view, "localStorage.getItem('ylf-upgrade-fixture')"))
        assertTrue(onMain { CookieManager.getInstance().getCookie(origin).orEmpty().split("; ").contains("ylfUpgrade=$token") })
        if (checkDatabase) {
            eval(view, """
                window.legacyDatabaseValue = null;
                const request = indexedDB.open('ylf-upgrade-fixture');
                request.onupgradeneeded = () => request.transaction.abort();
                request.onsuccess = () => {
                    const db = request.result;
                    const get = db.transaction('values').objectStore('values').get('legacy');
                    get.onsuccess = () => { window.legacyDatabaseValue = get.result; db.close(); };
                };
            """.trimIndent())
            await { eval(view, "window.legacyDatabaseValue") == token }
        }
    }

    private fun assertAppData(view: WebView, expected: String?) {
        await { eval(view, "document.getElementById('fixture') !== null") == true }
        assertEquals(expected, eval(view, "localStorage.getItem('owner')"))
        assertEquals(expected?.let { "owner=$it" }.orEmpty(), eval(view, "document.cookie"))
    }

    private fun writeAppData(view: WebView, value: String) {
        await { eval(view, "document.getElementById('fixture') !== null") == true }
        eval(view, "localStorage.setItem('owner', '$value'); document.cookie='owner=$value; Max-Age=3600; Path=/';")
        assertAppData(view, value)
    }

    private fun openLegacyOrigin(origin: String): WebView {
        val ready = CountDownLatch(1)
        val view = onMain {
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String) { ready.countDown() }
                }
                loadDataWithBaseURL(origin, "<!doctype html><title>Legacy storage fixture</title>", "text/html", "UTF-8", null)
            }
        }
        assertTrue("Legacy origin loaded", ready.await(10, TimeUnit.SECONDS))
        return view
    }

    private fun openHost(app: CatalogApp): HostWebViewActivity = instrumentation.startActivitySync(
        Intent(context, HostWebViewActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(HostWebViewActivity.EXTRA_OPTIONS, app.launchOptions().toString()),
    ) as HostWebViewActivity

    private fun withHost(app: CatalogApp, block: (HostWebViewActivity) -> Unit) {
        val host = openHost(app)
        try { block(host) } finally { onMain { host.finish() } }
    }

    private fun requireWeb(host: HostWebViewActivity): WebView = onMain {
        val view = descendants(host.window.decorView).filterIsInstance<WebView>().firstOrNull()
        assertNotNull("Expected an isolated WebView", view)
        view!!
    }

    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) yieldAll(descendants(view.getChildAt(index)))
    }

    private fun eval(view: WebView, script: String): Any? {
        val ready = CountDownLatch(1)
        val output = AtomicReference<String>()
        onMain { view.evaluateJavascript(script) { output.set(it); ready.countDown() } }
        assertTrue("WebView script completed", ready.await(5, TimeUnit.SECONDS))
        return output.get()?.let { JSONTokener(it).nextValue() }?.takeUnless { it == JSONObject.NULL }
    }

    private fun await(condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (!condition()) {
            check(System.nanoTime() < deadline) { "Timed out waiting for the storage fixture" }
            Thread.sleep(50)
        }
    }

    private fun <T> onMain(block: () -> T): T = runBlocking(Dispatchers.Main) { block() }

    private fun signIn(id: String) = runBlocking(Dispatchers.Main) {
        YunleContainer.accounts.passwordSignIn(identifier = id, password = "fixture")
        assertEquals(id, YunleContainer.accounts.user?.id)
    }

    private fun select(id: String) = runBlocking(Dispatchers.Main) {
        YunleContainer.accounts.select(id)
        assertEquals(id, YunleContainer.accounts.user?.id)
    }

    private fun fixtureApp(id: String, url: String) = CatalogApp(
        id = id, key = id, name = "Storage fixture", description = "", author = "Fixture",
        ownerLogin = null, category = "", emoji = "☁️", launchUrl = url, logo = null,
        themeColor = null, trustedHosts = emptyList(), immersive = false,
    )

    private fun withLocalPage(block: (String) -> Unit) {
        val server = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        val worker = thread(isDaemon = true) {
            while (!server.isClosed) {
                val client = runCatching { server.accept() }.getOrNull() ?: break
                runCatching {
                    client.use {
                        val reader = it.getInputStream().bufferedReader()
                        while (!reader.readLine().isNullOrEmpty()) { /* consume headers */ }
                        val html = "<!doctype html><title>Storage fixture</title><main id=fixture>ready</main>"
                        it.getOutputStream().write(
                            ("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ${html.length}\r\n" +
                                "Connection: close\r\n\r\n" + html).toByteArray(),
                        )
                    }
                }
            }
        }
        try { block("http://127.0.0.1:${server.localPort}/app") } finally {
            server.close()
            worker.join(1_000)
        }
    }

    private object FixtureAccounts : AccountAuthenticating by CloudbaseAuthService(origin = "http://127.0.0.1:1") {
        override suspend fun passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) =
            AuthTokenResponse(accessToken = identifier, refreshToken = "fixture", expiresIn = 3600, subject = identifier)

        override suspend fun user(accessToken: String, deviceID: String) =
            AccountUser(id = accessToken, name = accessToken)
    }
}
