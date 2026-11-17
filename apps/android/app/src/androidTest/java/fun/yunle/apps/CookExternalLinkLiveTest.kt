package `fun`.yunle.apps

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.URL
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real production controls and touchscreen input; no URL/intent interception. */
@RunWith(AndroidJUnit4::class)
class CookExternalLinkLiveTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test
    fun bilibiliAnchorAndWindowOpenUseRealCustomTabs() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("Explicit isolated live validation only", args.getString("cookExternalLive") == "1")
        check(Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish")
        val run = UUID.fromString(args.getString("cookExternalRunId")).toString()
        val context = instrumentation.targetContext
        val record = URL("https://apps.yunle.fun/api/apps/public/cook").openConnection().run {
            connectTimeout = 15_000; readTimeout = 15_000
            getInputStream().bufferedReader().use { JSONObject(it.readText()).getJSONObject("app") }
        }
        check(record.getString("websiteUrl") == "https://cook.yunle.fun/home")
        val options = JSONObject().put("url", record.getString("websiteUrl")).put("title", record.getString("name"))
            .put("app", JSONObject().put("id", "cook").put("slug", "cook").put("name", record.getString("name")))
            .put("trustedHosts", record.getJSONArray("trustedHosts"))
        val activity = instrumentation.startActivitySync(Intent(context, HostWebViewActivity::class.java)
            .putExtra(HostWebViewActivity.EXTRA_OPTIONS, options.toString()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as HostWebViewActivity
        val web = onMain { findWeb(activity.window.decorView) ?: error("Real host WebView missing") }
        val routes = JSONArray()
        var phase = "initial-cook"
        var failure = ""
        try {
            waitFor(45) { js(web, "document.title==='食用手册' && !!document.querySelector('ion-tab-button')") == true }
            phase = "anchor"
            onMain { web.loadUrl("https://cook.yunle.fun/about/me") }
            val anchor = "[...document.querySelectorAll('ion-item,a')].find(e=>String(e.href||'').includes('bilibili.com'))"
            waitFor(30) { js(web, "!!($anchor)") == true }
            routes.put(openAndReturn(web, anchor, phase, context.getExternalFilesDir(null)!!))
            phase = "window-open"
            onMain { web.loadUrl("https://cook.yunle.fun/library") }
            val row = "document.querySelector('ion-item-sliding ion-item ion-label')"
            waitFor(35) { js(web, "!!($row)") == true }
            routes.put(openAndReturn(web, row, phase, context.getExternalFilesDir(null)!!))
        } catch (error: Throwable) {
            failure = "$phase: ${error.javaClass.simpleName}"
            screenshot(File(context.getExternalFilesDir(null), "android-external-failure-$phase.png"))
        } finally {
            onMain { activity.finish() }
            File(context.getExternalFilesDir(null), "cook-external-report.json").writeText(JSONObject()
                .put("runID", run).put("failure", failure).put("routes", routes)
                .put("scope", "Isolated Android API 35 emulator; real production Cook and native touchscreen input; default Custom Tabs")
                .put("videoPlaybackTested", false).put("bilibiliAppHandoffTested", false).toString(2))
        }
        check(failure.isEmpty()) { "Safe failure phase: $failure" }
        check(routes.length() == 2)
    }

    private fun openAndReturn(web: WebView, selector: String, kind: String, directory: File): JSONObject {
        js(web, "($selector).scrollIntoView({block:'center'});true")
        SystemClock.sleep(250)
        val candidate = js(web, "(()=>{const e=$selector,r=e.getBoundingClientRect();return {label:e.textContent.trim(),href:e.href||'',x:r.x+r.width/2,y:r.y+r.height/2,viewport:innerWidth};})()") as JSONObject
        val before = onMain { web.url }
        val position = onMain { val location = IntArray(2); web.getLocationOnScreen(location); Triple(location[0], location[1], web.width) }
        val scale = position.third / candidate.getDouble("viewport")
        val x = (position.first + candidate.getDouble("x") * scale).toFloat()
        val y = (position.second + candidate.getDouble("y") * scale).toFloat()
        val downTime = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
            event.source = InputDevice.SOURCE_TOUCHSCREEN
            instrumentation.sendPointerSync(event); event.recycle()
            SystemClock.sleep(50)
        }
        waitFor(30) { instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() == "com.android.chrome" }
        val top = topActivity()
        check(top.startsWith("com.android.chrome/") && top.contains("CustomTab")) { "Expected real Custom Tabs activity" }
        waitFor(25) { browserAddress()?.contains("bilibili.com") == true }
        val address = browserAddress() ?: error("Browser address missing")
        screenshot(File(directory, "android-bilibili-$kind-custom-tab.png"))
        check(onMain { web.url } == before && before?.startsWith("https://cook.yunle.fun/") == true)
        check(instrumentation.uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK))
        waitFor(15) { instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() == "fun.yunle.apps" }
        check(onMain { web.url } == before)
        return JSONObject().put("kind", kind).put("sourceLabel", candidate.getString("label"))
            .put("sourceHref", candidate.getString("href")).put("actualTopActivity", top)
            .put("browserAddress", address).put("cookDocumentPreserved", true).put("returnedToCook", true)
    }
    private fun browserAddress(): String? {
        fun find(node: AccessibilityNodeInfo?): String? {
            if (node == null) return null
            if (node.viewIdResourceName?.endsWith("/url_bar") == true) return node.text?.toString()
            for (index in 0 until node.childCount) find(node.getChild(index))?.let { return it }
            return null
        }
        return find(instrumentation.uiAutomation.rootInActiveWindow)
    }
    private fun topActivity(): String {
        val descriptor = instrumentation.uiAutomation.executeShellCommand("dumpsys activity activities")
        val dump = android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
        return Regex("topResumedActivity=ActivityRecord\\{[^\\n]*? ([A-Za-z0-9_.]+/[A-Za-z0-9_.$]+) ").find(dump)?.groupValues?.get(1) ?: ""
    }
    private fun screenshot(file: File) {
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
    }
    private fun js(web: WebView, script: String): Any? {
        val latch = CountDownLatch(1); var result: String? = null
        instrumentation.runOnMainSync { web.evaluateJavascript(script) { result = it; latch.countDown() } }
        check(latch.await(8, TimeUnit.SECONDS))
        return JSONArray("[${result ?: "null"}]").get(0).takeUnless { it == JSONObject.NULL }
    }
    private fun <T> onMain(body: () -> T): T {
        var value: T? = null; instrumentation.runOnMainSync { value = body() }
        @Suppress("UNCHECKED_CAST") return value as T
    }
    private fun waitFor(seconds: Int, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds.toLong())
        while (System.nanoTime() < deadline) { if (condition()) return; SystemClock.sleep(100) }
        error("Bounded runtime observation timed out")
    }
    private fun findWeb(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) findWeb(view.getChildAt(index))?.let { return it }
        return null
    }
}
