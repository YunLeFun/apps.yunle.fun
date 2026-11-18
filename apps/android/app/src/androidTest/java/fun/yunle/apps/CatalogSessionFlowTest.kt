package `fun`.yunle.apps

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.BufferedReader
import java.io.File
import java.io.IOException
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CatalogSessionFlowTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val uiAutomation get() = instrumentation.uiAutomation
    private lateinit var server: ServerSocket
    private var serverThread: Thread? = null
    private var baseUrl: String = ""

    @Before
    fun setUp() {
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
                            <html><head><meta charset="utf-8"><title>今天来做菜</title></head>
                            <body><main id="app">catalog-flow-ready</main></body></html>
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
    fun tearDown() {
        CatalogRepository.overrideForTesting = null
        runShell("wm size reset")
        runShell("cmd uimode night no")
        runShell("settings put system font_scale 1.0")
        instrumentation.runOnMainSync {
            HostSession.current()?.finish()
        }
        runCatching { server.close() }
        serverThread?.join(1_000)
    }

    private fun testCatalog(guestUrl: String = baseUrl): List<CatalogApp> = buildList {
        add(
            CatalogApp(
                id = "app_cook",
                key = "cook",
                name = "今天来做菜",
                description = "菜谱与下厨灵感",
                author = "云乐坊",
                ownerLogin = "yunle",
                category = "生活",
                emoji = "🍳",
                launchUrl = guestUrl,
                logo = null,
                themeColor = "#005DB3",
                trustedHosts = listOf("127.0.0.1"),
                immersive = false,
            ),
        )
        add(
            CatalogApp(
                id = "app_member",
                key = "member-notes",
                name = "会员专享笔记",
                description = "需要登录或会员权限",
                author = "云乐坊",
                ownerLogin = "yunle",
                category = "效率",
                emoji = "📝",
                launchUrl = null,
                logo = null,
                themeColor = null,
                trustedHosts = emptyList(),
                immersive = false,
            ),
        )
        for (i in 1..15) {
            add(
                CatalogApp(
                    id = "app_extra_$i",
                    key = "extra-$i",
                    name = "效率工具 $i",
                    description = "辅助工具集条目 $i",
                    author = "独立开发者",
                    ownerLogin = null,
                    category = "工具",
                    emoji = "☁️",
                    launchUrl = guestUrl,
                    logo = null,
                    themeColor = null,
                    trustedHosts = listOf("127.0.0.1"),
                    immersive = false,
                ),
            )
        }
    }

    @Test
    fun catalogSearchDetailTryMinimizeAndResumeKeepsSameSession() {
        val apps = testCatalog()
        CatalogRepository.overrideForTesting = CatalogDataSource { apps }

        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        ) as MainActivity
        try {
            val density = instrumentation.targetContext.resources.displayMetrics.density
            val minTargetPx = (48 * density * 0.95f).toInt()

            // Verify bottom Material 3 tabs on launch (starts on 云居) and switch to 工坊
            awaitNode { nodeText(it) == "云居" }
            awaitNode { nodeText(it) == "寻乐" }
            awaitNode { nodeText(it) == "工坊" }
            awaitNode { nodeText(it) == "我" }
            clickMatching { nodeText(it) == "工坊" }

            val catalogHeading = awaitNode { nodeText(it) == "探索应用" && it.isHeading }
            assertNotNull("Catalog heading must expose heading semantics", catalogHeading)
            assertNotNull("Top bar title must expose heading semantics", findNode { nodeText(it) == "云乐坊" && it.isHeading })

            val accountButton = awaitNode { it.contentDescription?.toString() == "账号" }
            val accountBounds = clickableBoundsOf(accountButton)
            assertTrue("Account button target must be >= 48dp", accountBounds.height() >= minTargetPx)

            awaitNode { nodeText(it) == "今天来做菜" }

            // Scroll down so top items leave viewport, then search & clear must reset list scroll to top
            repeat(3) {
                findNode { it.isScrollable && !it.isEditable }
                    ?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                Thread.sleep(150)
            }
            waitFor(5) { findNode { nodeText(it) == "今天来做菜" } == null }
            setNodeText(awaitNode { it.isEditable }, "做菜")
            awaitNode { nodeText(it) == "今天来做菜" }
            waitFor(5) { findNode { nodeText(it) == "会员专享笔记" } == null }

            setNodeText(findNode { it.isEditable }!!, "不存在的关键词xyz")
            awaitNode { nodeText(it) == "没有找到符合条件的应用。" }
            clickMatching { nodeText(it) == "清除搜索" || it.contentDescription?.toString() == "清除搜索" }
            awaitNode { nodeText(it) == "今天来做菜" }
            awaitNode { nodeText(it) == "会员专享笔记" }

            // Restricted app shows web details only (no try button)
            clickMatching { nodeText(it) == "会员专享笔记" }
            awaitNode { nodeText(it) == "应用详情" && it.isHeading }
            awaitNode { nodeText(it) == "网页详情" }
            assertNull(findNode { nodeText(it) == "试用" })

            // Back to catalog
            clickMatching { it.contentDescription?.toString() == "返回" }
            awaitNode { nodeText(it) == "探索应用" }

            // Open guest-accessible app detail and verify TalkBack semantics + touch targets
            clickMatching { nodeText(it) == "今天来做菜" }
            awaitNode { nodeText(it) == "应用详情" && it.isHeading }
            awaitNode { nodeText(it) == "今天来做菜" && it.isHeading }
            val tryButton = awaitNode { nodeText(it) == "试用" }
            val tryBounds = clickableBoundsOf(tryButton)
            assertTrue("Try button touch target must be >= 48dp", tryBounds.height() >= minTargetPx)

            // 目录 -> 详情 -> 试用 -> 收起 -> 恢复同一会话
            clickMatching { nodeText(it) == "试用" }
            waitFor(12) {
                onMain {
                    val host = HostSession.current()
                    host != null && findWeb(host.window.decorView) != null
                }
            }
            val firstHost = onMain { HostSession.current()!! }
            waitFor(10) { evalJs(firstHost, "document.getElementById('app') && document.getElementById('app').textContent") == "catalog-flow-ready" }
            evalJs(firstHost, "(function(){ window.__ylfSessionId = 'live-session-078'; return window.__ylfSessionId; })()")

            // Minimize app via toolbar button
            clickMatching { it.contentDescription?.toString() == "收起应用" }
            val resumeBanner = awaitNode { nodeText(it) == "继续使用：今天来做菜" }
            assertTrue("Resume banner must be >= 48dp", clickableBoundsOf(resumeBanner).height() >= minTargetPx)

            // Resume same session from banner
            clickMatching { nodeText(it) == "继续使用：今天来做菜" }
            waitFor(10) {
                onMain {
                    val current = HostSession.current()
                    current === firstHost && !HostSession.isMinimized(current)
                }
            }
            assertSame(firstHost, onMain { HostSession.current() })
            assertEquals(
                "live-session-078",
                evalJs(firstHost, "window.__ylfSessionId"),
            )

            // Open details from Host overflow menu and press Back to return to WebView
            clickMatching { it.contentDescription?.toString() == "更多" }
            clickMatching { nodeText(it) == "查看详情与评价" }
            awaitNode { nodeText(it) == "应用详情" && it.isHeading }
            awaitNode { nodeText(it) == "今天来做菜" }

            uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            waitFor(10) {
                onMain {
                    val current = HostSession.current()
                    current === firstHost && findWeb(current.window.decorView) != null
                }
            }
            assertEquals("live-session-078", evalJs(firstHost, "window.__ylfSessionId"))
        } finally {
            onMain {
                HostSession.current()?.finish()
                activity.finish()
            }
        }
    }

    @Test
    fun fourTabsHomeAdditionGamesAndNativeLoginSheetWorkEndToEnd() {
        CatalogRepository.overrideForTesting = CatalogDataSource { testCatalog() }
        ActivityScenario.launch(MainActivity::class.java).use {
            // Starts on 云居
            awaitNode { nodeText(it) == "我的云居" }

            // Go to 工坊, open detail, add app to 云居
            clickMatching { nodeText(it) == "工坊" }
            awaitNode { nodeText(it) == "探索应用" }
            clickMatching { nodeText(it) == "今天来做菜" }
            awaitNode { nodeText(it) == "加入云居" }
            clickMatching { nodeText(it) == "加入云居" }
            awaitNode { nodeText(it) == "已在云居 · 点击移出" }

            // Verify app now appears in 云居 desktop grid, supports long-press pin to Dock and edit-mode removal
            clickMatching { nodeText(it) == "云居" }
            awaitNode { nodeText(it) == "今天来做菜" }
            longClickMatching { nodeText(it) == "今天来做菜" }
            awaitNode { nodeText(it) == "编辑云居" }
            clickMatching { nodeText(it) == "设为常用" }
            awaitNode { nodeText(it) == "常用应用" }
            clickMatching { nodeText(it) == "编辑" }
            clickMatching { it.contentDescription?.toString() == "移出 今天来做菜" }
            awaitNode { nodeText(it) == "你的云居还没有应用" }

            // Switch to 寻乐
            clickMatching { nodeText(it) == "寻乐" }
            awaitNode { nodeText(it) == "云乐坊游戏大厅" }
            awaitNode { nodeText(it) == "进入游戏大厅" }

            // Switch to 我 and open native Login sheet
            clickMatching { nodeText(it) == "我" }
            awaitNode { nodeText(it) == "登录云乐坊" }
            clickMatching { nodeText(it) == "登录" }
            awaitNode { nodeText(it) == "手机号" }
            awaitNode { nodeText(it) == "邮箱" }
            awaitNode { nodeText(it) == "密码" }
        }
    }

    @Test
    fun catalogErrorRetriesAndRotationPreservesLoadedStateWithoutRefetch() {
        val calls = AtomicInteger(0)
        val apps = testCatalog()
        CatalogRepository.overrideForTesting = CatalogDataSource {
            if (calls.incrementAndGet() == 1) throw IOException("simulated offline")
            apps
        }

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            clickMatching { nodeText(it) == "工坊" }
            awaitNode { nodeText(it) == "暂时无法加载应用，请检查网络。" }
            val retryButton = awaitNode { nodeText(it) == "重试" }
            assertTrue(clickNode(retryButton))

            awaitNode { nodeText(it) == "今天来做菜" }
            assertEquals(2, calls.get())

            // Filter before rotation
            setNodeText(awaitNode { it.isEditable }, "做菜")
            awaitNode { nodeText(it) == "今天来做菜" }
            waitFor(5) { findNode { nodeText(it) == "会员专享笔记" } == null }

            // Rotate to landscape and back without re-fetching catalog
            scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
            awaitNode { nodeText(it) == "今天来做菜" }
            assertEquals(2, calls.get())

            scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
            awaitNode { nodeText(it) == "今天来做菜" }
            assertEquals(2, calls.get())

            // OS process death does not fabricate a minimized session
            assertNull(findNode { nodeText(it)?.startsWith("继续使用：") == true })
        }
    }

    @Test
    fun wideScreenTwoPaneAndDarkLargeFontAndKeyboardNavigationWork() {
        CatalogRepository.overrideForTesting = CatalogDataSource { testCatalog() }
        val initialDensity = instrumentation.targetContext.resources.displayMetrics.density
        val wideWidthPx = (960 * initialDensity).toInt().coerceAtLeast(2400)
        val wideHeightPx = (640 * initialDensity).toInt().coerceAtLeast(1500)
        runShell("wm size ${wideWidthPx}x${wideHeightPx}")
        instrumentation.waitForIdleSync()

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            clickMatching { nodeText(it) == "工坊" }
            val listHeading = awaitNode { nodeText(it) == "探索应用" }
            val placeholder = awaitNode { nodeText(it) == "选择一个应用查看详情" }
            val listRect = boundsOf(listHeading)
            val placeholderRect = boundsOf(placeholder)
            assertTrue(
                "Two-pane layout should render list left and detail placeholder right",
                placeholderRect.left > listRect.left,
            )

            // Keyboard Tab + Enter focus movement works cleanly in Compose catalog
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_TAB)

            // Select app: both panes visible side-by-side and card marked selected
            clickMatching { nodeText(it) == "今天来做菜" }
            val tryButton = awaitNode { nodeText(it) == "试用" }
            awaitNode { nodeText(it) == "探索应用" }
            val detailRect = boundsOf(tryButton)
            assertTrue("Detail action must be rendered to the right of list pane", detailRect.left > listRect.left)
            saveScreenshot(scenario, "catalog-twopane.png")
            awaitNode {
                (it.isSelected || it.collectionItemInfo?.isSelected == true || it.stateDescription?.toString() == "已选中") &&
                    hasDescendantText(it, "今天来做菜")
            }

            // Back pops detail back to empty two-pane placeholder
            uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            awaitNode { nodeText(it) == "选择一个应用查看详情" }
            awaitNode { nodeText(it) == "探索应用" }
        }

        // Verify dark mode + large font scale on phone width without clipped/collapsed controls
        runShell("wm size reset")
        runShell("cmd uimode night yes")
        runShell("settings put system font_scale 1.75")
        instrumentation.waitForIdleSync()

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val density = instrumentation.targetContext.resources.displayMetrics.density
            val minTargetPx = (48 * density * 0.95f).toInt()
            clickMatching { nodeText(it) == "工坊" }
            awaitNode { nodeText(it) == "探索应用" }
            val card = awaitNode { nodeText(it) == "今天来做菜" }
            assertTrue(clickableBoundsOf(card).height() >= minTargetPx)
            saveScreenshot(scenario, "catalog-dark-large.png")

            assertTrue(clickNode(card))
            val tryButton = awaitNode { nodeText(it) == "试用" }
            assertTrue(clickableBoundsOf(tryButton).height() >= minTargetPx)
        }
    }

    @Test
    fun publicCatalogOpensOneRealGuestAppReadOnly() {
        assumeTrue(
            "Explicit live catalog smoke validation only",
            InstrumentationRegistry.getArguments().getString("publicCatalogLive") == "1",
        )
        CatalogRepository.overrideForTesting = null

        val guestApp = CatalogRepository.load().firstOrNull { it.launchUrl != null }
            ?: error("No guest-accessible public app available in live catalog")

        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        ) as MainActivity
        try {
            clickMatching { nodeText(it) == "工坊" }
            awaitNode(20) { nodeText(it) == "探索应用" }
            setNodeText(awaitNode { it.isEditable }, guestApp.name)
            clickMatching(15) { nodeText(it) == guestApp.name }
            awaitNode { nodeText(it) == "应用详情" }
            clickMatching { nodeText(it) == "试用" }

            waitFor(20) {
                onMain {
                    val host = HostSession.current()
                    val web = host?.window?.decorView?.let(::findWeb)
                    host != null && web != null && (web.progress >= 30 || !web.url.isNullOrBlank())
                }
            }

            clickMatching { it.contentDescription?.toString() == "收起应用" }
            awaitNode { nodeText(it) == "继续使用：${guestApp.name}" }
        } finally {
            onMain {
                HostSession.current()?.finish()
                activity.finish()
            }
        }
    }

    private fun saveScreenshot(scenario: ActivityScenario<MainActivity>, fileName: String) {
        var dir: File? = null
        scenario.onActivity { dir = it.getExternalFilesDir(null) }
        val output = File(dir ?: return, fileName)
        val bitmap = uiAutomation.takeScreenshot()
        output.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun runShell(command: String) {
        uiAutomation.executeShellCommand(command).use { pfd: ParcelFileDescriptor ->
            ParcelFileDescriptor.AutoCloseInputStream(pfd).bufferedReader().use { it.readText() }
        }
    }

    private fun <T> onMain(block: () -> T): T {
        val result = AtomicReference<T>()
        instrumentation.runOnMainSync { result.set(block()) }
        return result.get()
    }

    private fun waitFor(timeoutSeconds: Long, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(timeoutSeconds)
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(100)
        }
        assertTrue(
            "Condition was not satisfied within ${timeoutSeconds}s.\nTree:\n${dumpAccessibilityTree()}",
            condition(),
        )
    }

    private fun dumpAccessibilityTree(): String = buildString {
        fun walk(node: AccessibilityNodeInfo, depth: Int) {
            append("  ".repeat(depth))
            append("cls=").append(node.className?.toString()?.substringAfterLast('.'))
            node.text?.let { append(" text=\"").append(it).append('"') }
            node.contentDescription?.let { append(" desc=\"").append(it).append('"') }
            if (node.isClickable) append(" [clickable]")
            if (node.isSelected) append(" [selected]")
            node.stateDescription?.let { append(" state=\"").append(it).append('"') }
            if (node.isHeading) append(" [heading]")
            if (node.isEditable) append(" [editable]")
            append(" bounds=").append(boundsOf(node).toShortString())
            append('\n')
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { walk(it, depth + 1) }
            }
        }
        uiAutomation.rootInActiveWindow?.let { walk(it, 0) }
    }

    private fun clickMatching(
        timeoutSeconds: Long = 10,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ) {
        waitFor(timeoutSeconds) {
            findNode(predicate)?.let(::clickNode) == true
        }
    }

    private fun longClickMatching(
        timeoutSeconds: Long = 10,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ) {
        waitFor(timeoutSeconds) {
            findNode(predicate)?.let(::longClickNode) == true
        }
    }

    private fun awaitNode(
        timeoutSeconds: Long = 10,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ): AccessibilityNodeInfo {
        var found: AccessibilityNodeInfo? = null
        waitFor(timeoutSeconds) {
            found = findNode(predicate)
            found != null
        }
        return requireNotNull(found)
    }

    private fun findNode(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        // Android 14+ caches unchanged bounds across Compose semantic property flips unless cleared.
        if (android.os.Build.VERSION.SDK_INT >= 34) {
            runCatching { uiAutomation.clearCache() }
        }
        val roots = buildList {
            uiAutomation.windows?.mapNotNullTo(this) { it.root }
            uiAutomation.rootInActiveWindow?.let { add(it) }
        }
        for (root in roots) {
            findInTree(root, predicate)?.let { return it }
        }
        return null
    }

    private fun findInTree(
        node: AccessibilityNodeInfo,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ): AccessibilityNodeInfo? {
        if (predicate(node)) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            findInTree(child, predicate)?.let { return it }
        }
        return null
    }

    private fun nodeText(node: AccessibilityNodeInfo): String? = node.text?.toString()

    private fun hasDescendantText(node: AccessibilityNodeInfo, expected: String): Boolean {
        if (nodeText(node)?.contains(expected) == true) return true
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (hasDescendantText(child, expected)) return true
        }
        return false
    }

    private fun clickNode(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        while (current != null) {
            if (current.isClickable) {
                return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            current = current.parent
        }
        return false
    }

    private fun longClickNode(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        while (current != null) {
            if (current.isLongClickable) {
                return current.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)
            }
            current = current.parent
        }
        return false
    }

    private fun setNodeText(node: AccessibilityNodeInfo, text: String) {
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        assertTrue(
            "Unable to set text on editable node",
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args),
        )
    }

    private fun boundsOf(node: AccessibilityNodeInfo): Rect = Rect().also { node.getBoundsInScreen(it) }

    private fun clickableBoundsOf(node: AccessibilityNodeInfo): Rect {
        var current: AccessibilityNodeInfo? = node
        while (current != null) {
            if (current.isClickable) return boundsOf(current)
            current = current.parent
        }
        return boundsOf(node)
    }

    private fun findWeb(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findWeb(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun evalJs(activity: HostWebViewActivity, script: String): String? {
        val latch = CountDownLatch(1)
        val value = AtomicReference<String?>(null)
        instrumentation.runOnMainSync {
            val webView = findWeb(activity.window.decorView)
            if (webView == null) {
                latch.countDown()
            } else {
                webView.evaluateJavascript(script) { raw ->
                    value.set(raw?.trim()?.removeSurrounding("\""))
                    latch.countDown()
                }
            }
        }
        latch.await(5, TimeUnit.SECONDS)
        return value.get()
    }
}
