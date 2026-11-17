package `fun`.yunle.apps

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

@RunWith(AndroidJUnit4::class)
class RenderProcessTerminationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var server: ServerSocket
    private var serverThread: Thread? = null
    private var baseUrl: String = ""

    @Before
    fun startLocalPageServer() {
        server = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        baseUrl = "http://127.0.0.1:${server.localPort}/app"
        serverThread = thread(isDaemon = true) {
            while (!server.isClosed) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                runCatching {
                    socket.use { client ->
                        val reader = BufferedReader(InputStreamReader(client.getInputStream()))
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                        }
                        val body = """
                            <!doctype html>
                            <html><head><meta charset="utf-8"><title>测试云应用</title></head>
                            <body><main id="app">ready</main></body></html>
                        """.trimIndent().toByteArray(Charsets.UTF_8)
                        val response = buildString {
                            append("HTTP/1.1 200 OK\r\n")
                            append("Content-Type: text/html; charset=utf-8\r\n")
                            append("Content-Length: ${body.size}\r\n")
                            append("Connection: close\r\n\r\n")
                        }.toByteArray(Charsets.UTF_8) + body
                        client.getOutputStream().write(response)
                        client.getOutputStream().flush()
                    }
                }
            }
        }
    }

    @After
    fun stopLocalPageServer() {
        runCatching { server.close() }
        serverThread?.join(1_000)
        instrumentation.runOnMainSync {
            HostSession.current()?.finish()
        }
    }

    @Test
    fun renderProcessTerminationClearsSessionAndAllowsReopen() {
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, HostWebViewActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(
                    HostWebViewActivity.EXTRA_OPTIONS,
                    """{"url":"$baseUrl","title":"渲染恢复测试","app":{"id":"render_test","slug":"render-test","name":"渲染恢复测试"}}""",
                ),
        ) as HostWebViewActivity

        try {
            waitFor(10) { onMain { HostSession.current() === activity && findWeb(activity.window.decorView) != null } }
            val originalWeb = onMain { findWeb(activity.window.decorView)!! }

            onMain { originalWeb.loadUrl("chrome://crash") }

            waitFor(15) {
                onMain {
                    HostSession.current() == null &&
                        HostSession.minimizedName() == null &&
                        findText(activity.window.decorView, "重新打开") != null
                }
            }
            assertNull(onMain { HostSession.current() })
            assertNull(onMain { HostSession.minimizedName() })
            assertNotNull(onMain { findText(activity.window.decorView, "返回目录") })

            onMain {
                findText(activity.window.decorView, "重新打开")!!.performClick()
            }

            waitFor(15) {
                onMain {
                    val currentWeb = findWeb(activity.window.decorView)
                    HostSession.current() === activity && currentWeb != null && currentWeb !== originalWeb
                }
            }
            val reopenedWeb = onMain { findWeb(activity.window.decorView)!! }
            assertNotSame(originalWeb, reopenedWeb)
        } finally {
            onMain { activity.finish() }
        }
    }

    @Test
    fun minimizedRenderProcessTerminationRemovesResumeEntry() {
        val context = instrumentation.targetContext
        val host = instrumentation.startActivitySync(
            Intent(context, HostWebViewActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(
                    HostWebViewActivity.EXTRA_OPTIONS,
                    """{"url":"$baseUrl","title":"后台退出测试","app":{"id":"bg_render_test","slug":"bg-render-test","name":"后台退出测试"}}""",
                ),
        ) as HostWebViewActivity

        try {
            waitFor(10) { onMain { HostSession.current() === host && findWeb(host.window.decorView) != null } }
            val web = onMain { findWeb(host.window.decorView)!! }

            onMain {
                HostSession.minimized(host)
            }
            assertTrue(onMain { HostSession.minimizedName() == "后台退出测试" })

            onMain { web.loadUrl("chrome://crash") }

            waitFor(15) {
                onMain {
                    HostSession.current() == null &&
                        HostSession.minimizedName() == null &&
                        host.isFinishing
                }
            }
        } finally {
            onMain { if (!host.isFinishing) host.finish() }
        }
    }

    private fun <T> onMain(block: () -> T): T {
        var result: T? = null
        instrumentation.runOnMainSync { result = block() }
        @Suppress("UNCHECKED_CAST")
        return result as T
    }

    private fun waitFor(seconds: Int, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds.toLong())
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(100)
        }
        error("Timed out waiting for condition")
    }

    private fun findWeb(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findWeb(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun findText(view: View, label: String): View? {
        if (view is TextView && view.visibility == View.VISIBLE && view.text?.toString() == label) {
            return view
        }
        if (view is ViewGroup && view.visibility == View.VISIBLE) {
            for (index in 0 until view.childCount) {
                findText(view.getChildAt(index), label)?.let { return it }
            }
        }
        return null
    }
}
