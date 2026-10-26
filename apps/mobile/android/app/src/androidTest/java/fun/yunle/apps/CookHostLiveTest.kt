package `fun`.yunle.apps

import android.app.Activity
import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.system.Os
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.TextView
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.isDisplayed
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.hamcrest.Matchers.startsWith
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.URL
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Explicit, isolated production validation; it never runs in ordinary CI. */
@RunWith(AndroidJUnit4::class)
class CookHostLiveTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    @Volatile private var resumed: Activity? = null

    @Test
    fun managedCookLoginClipboardAndHaptics() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("Requires explicit managed live validation", args.getString("cookHostLive") == "1")
        check(Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish") { "Requires an isolated emulator" }
        val context = instrumentation.targetContext
        if (args.getString("cookHostCleanup") == "1") {
            val reportFile = File(context.getExternalFilesDir(null), "cook-host-runtime-report.json")
            val report = JSONObject(reportFile.readText())
            check(report.getString("runID") == args.getString("cookRunId"))
            check(report.getJSONObject("checks").getBoolean("hostPasswordFormAuthenticatedManagedAccount"))
            val host = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            try {
                signOutHost(host.bridge.webView)
                report.getJSONObject("checks").put("hostSignedOutAtCleanup", true)
                report.put("cleanupRetried", true)
                reportFile.writeText(report.toString(2))
            } finally { onMain { host.finish() } }
            return
        }
        val inputFile = File(context.filesDir, "cook-host-input.json")
        check(Os.stat(inputFile.path).st_mode and 0x3f == 0) { "One-use input must be private" }
        val input = JSONObject(inputFile.readText())
        check(inputFile.delete())
        val runId = input.getString("runID")
        check(runId == args.getString("cookRunId"))
        UUID.fromString(runId)
        val credentials = input.getJSONArray("accounts")
        check(credentials.length() == 1)
        val credential = credentials.getJSONObject(0)
        check(credential.getString("id") == "production-zero-balance")
        check(credential.getString("environment") == "production")
        check(credential.getString("username") == "ylf_prod_zero")
        check(credential.getString("password").isNotEmpty())
        val checks = JSONObject()
        var phase = "host-launch"
        var failure = ""
        var consumer: WebView? = null
        var main: MainActivity? = null
        val application = context.applicationContext as Application
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) { resumed = activity }
            override fun onActivityCreated(activity: Activity, state: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }
        application.registerActivityLifecycleCallbacks(callbacks)
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        try {
            val host = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            main = host
            val shell = host.bridge.webView
            waitFor(45) { js(shell, "location.origin === 'https://apps.yunle.fun' && !!window.Capacitor?.nativePromise && !!document.querySelector('ion-app')") == true }
            val record = URL("https://apps.yunle.fun/api/apps/public/cook").openConnection().run {
                connectTimeout = 15_000
                readTimeout = 15_000
                getInputStream().bufferedReader().use { JSONObject(it.readText()).getJSONObject("app") }
            }
            check(record.getString("websiteUrl") == "https://cook.yunle.fun/home")
            val options = JSONObject().put("url", record.getString("websiteUrl")).put("title", record.getString("name"))
                .put("app", JSONObject().put("id", "cook").put("slug", "cook").put("name", record.getString("name")))
                .put("trustedHosts", record.getJSONArray("trustedHosts"))
            js(shell, "window.Capacitor.nativePromise('HostRuntime', 'open', $options).catch(() => {}); true")
            waitFor(20) { resumed is HostWebViewActivity }
            val browser = resumed as HostWebViewActivity
            val web = onMain { webView(browser.window.decorView) ?: error("Host WebView missing") }
            consumer = web
            waitFor(35) { js(web, "document.title === '食用手册' && !!document.querySelector('ion-tab-button') && !!window.ylf") == true }
            phase = "capabilities"
            val capabilities = asyncJs(web, "const result={}; for(const name of ['authorize','haptic','setClipboard']) result[name]=await window.ylf.canIUse(name); return result;") as JSONObject
            check(listOf("authorize", "haptic", "setClipboard").all { capabilities.getBoolean(it) })
            val environment = asyncJs(web, "return await window.ylf.getEnv();") as JSONObject
            check(environment.getBoolean("trusted") && environment.getString("platform") == "android" && environment.getString("displayMode") == "titlebar")
            checks.put("nativeCapabilitiesAndTrustedTitlebar", true)
            asyncJs(web, "await window.ylf.haptic('light'); await window.ylf.haptic('success'); return true;")
            checks.put("realNativeHapticCallsAcknowledged", true)
            val previousClipboard = onMain { clipboard.primaryClip }
            try {
                val text = "Cook host acceptance $runId"
                asyncJs(web, "await window.ylf.setClipboard(${JSONObject.quote(text)}); return true;")
                check(onMain { clipboard.primaryClip?.getItemAt(0)?.text?.toString() } == text)
                checks.put("nativeClipboardReadbackMatches", true)
            } finally {
                onMain { if (previousClipboard == null) clipboard.clearPrimaryClip() else clipboard.setPrimaryClip(previousClipboard) }
            }
            check(js(web, "(() => { const tab=[...document.querySelectorAll('ion-tab-button')].find(x=>x.textContent.trim()==='我的'); if(!tab)return false;tab.click();return true;})()") == true)
            waitFor(20) { state(web).getBoolean("hasLogin") }
            phase = "host-password-form"
            clickItem(web, "使用云乐坊账号登录")
            waitFor(25) { resumed is MainActivity && js(shell, "location.origin==='https://apps.yunle.fun' && !!document.querySelector('.auth-segment-btn')") == true }
            check(js(shell, "(() => {const b=[...document.querySelectorAll('.auth-segment-btn')].find(x=>x.textContent.includes('密码'));if(!b)return false;b.click();return true;})()") == true)
            waitFor(10) { js(shell, "!!document.querySelector('input[autocomplete=\"current-password\"]')") == true }
            // Credentials enter only the real first-party host login controls.
            val filled = js(shell, """
                (() => {
                  if(location.origin!=='https://apps.yunle.fun')return false;
                  const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
                  for(const [selector,value] of [['input[autocomplete="username"]',${JSONObject.quote(credential.getString("username"))}],['input[autocomplete="current-password"]',${JSONObject.quote(credential.getString("password"))}]]) {
                    const field=document.querySelector(selector); if(!field)return false;
                    setter.call(field,value);field.dispatchEvent(new Event('input',{bubbles:true}));
                  }
                  return true;
                })()
            """.trimIndent())
            check(filled == true)
            waitFor(8) { js(shell, "document.querySelector('button[type=submit].auth-btn-primary')?.disabled === false") == true }
            js(shell, "document.querySelector('form.auth-form').requestSubmit();true")
            phase = "native-consent"
            waitFor(45) { resumed is HostWebViewActivity }
            val accountName = acceptConsent()
            checks.put("hostPasswordFormAuthenticatedManagedAccount", true)
            waitFor(35) { state(web).getString("name") == accountName }
            check(onMain { web.url?.startsWith("https://cook.yunle.fun/") } == true)
            checks.put("cookAdoptedHostIdentityWithoutNavigation", true)
            screenshot(context, "cook-host-signed-in.png")
            phase = "consumer-sign-out"
            signOutConsumer(web)
            checks.put("cookConsumerSignedOut", true)
            phase = "native-consent-cancel"
            clickItem(web, "使用云乐坊账号登录")
            waitForConsent()
            onView(withText("取消")).perform(click())
            waitFor(20) { state(web).getBoolean("hasLogin") }
            check(onMain { web.url?.startsWith("https://cook.yunle.fun/") } == true)
            checks.put("denialDidNotFallBackToWebRedirect", true)
            phase = "retry-after-cancel"
            clickItem(web, "使用云乐坊账号登录")
            val retryName = acceptConsent()
            check(retryName == accountName)
            waitFor(30) { state(web).getString("name") == accountName }
            checks.put("retryAfterCancellationSucceeded", true)
            signOutConsumer(web)
            checks.put("consumerSignedOutAtCleanup", true)
        } catch (error: Throwable) {
            failure = "$phase: ${error.javaClass.simpleName}"
            screenshot(context, "cook-host-failure-$phase.png")
        } finally {
            consumer?.let { web ->
                if (!checks.optBoolean("consumerSignedOutAtCleanup")) {
                    checks.put("consumerSignedOutAtCleanup", runCatching { signOutConsumer(web); true }.getOrDefault(false))
                }
                runCatching { js(web, "window.ylf.closeBrowser();true") }
            }
            main?.let { host ->
                checks.put("hostSignedOutAtCleanup", runCatching {
                    waitFor(15) { resumed is MainActivity }
                    signOutHost(host.bridge.webView)
                    true
                }.getOrDefault(false))
            }
            application.unregisterActivityLifecycleCallbacks(callbacks)
            val report = JSONObject().put("app", "cook").put("runID", runId).put("checks", checks).put("failure", failure)
                .put("scope", "Android emulator, real WebView, production host and managed synthetic account")
                .put("physicalHapticFeelingTested", false).put("hostCredentialsInjectedIntoConsumer", false)
            File(context.getExternalFilesDir(null), "cook-host-runtime-report.json").writeText(report.toString(2))
            onMain { resumed?.finish(); main?.finish() }
        }
        assertTrue("Cook live journey failed at $failure", failure.isEmpty())
        assertTrue("Not all ten runtime checks passed", checks.length() == 10 && checks.keys().asSequence().all { checks.getBoolean(it) })
    }

    private fun state(web: WebView): JSONObject = js(web, "({name:document.querySelector('.my-account h2')?.textContent.trim()||'',hasLogin:[...document.querySelectorAll('ion-item')].some(x=>x.textContent.includes('使用云乐坊账号登录'))})") as JSONObject
    private fun clickItem(web: WebView, text: String) {
        check(js(web, "(() => {const item=[...document.querySelectorAll('ion-item')].find(x=>x.textContent.includes(${JSONObject.quote(text)}));if(!item)return false;item.click();return true;})()") == true)
    }
    private fun signOutConsumer(web: WebView) {
        if (state(web).getBoolean("hasLogin")) return
        clickItem(web, "退出登录")
        waitFor(25) { val state = state(web); state.getBoolean("hasLogin") && state.getString("name").isEmpty() }
    }
    private fun signOutHost(shell: WebView) {
        onMain { shell.loadUrl("https://apps.yunle.fun/user/profile") }
        waitFor(30) { js(shell, "location.origin==='https://apps.yunle.fun' && !!document.querySelector('.k-list-item-destructive')") == true }
        js(shell, "document.querySelector('.k-list-item-destructive').click();true")
        waitFor(10) { js(shell, "[...document.querySelectorAll('ion-alert button')].some(x=>x.textContent.trim()==='确定')") == true }
        js(shell, "[...document.querySelectorAll('ion-alert button')].find(x=>x.textContent.trim()==='确定').click();true")
        waitFor(25) { js(shell, "document.body.textContent.includes('请先登录查看个人资料') && !document.querySelector('.k-list-item-destructive')") == true }
    }
    private fun waitForConsent() = waitFor(25) {
        runCatching { onView(withText(startsWith("以「"))).check(matches(isDisplayed())); true }.getOrDefault(false)
    }
    private fun acceptConsent(): String {
        waitForConsent()
        var account = ""
        onView(withText(startsWith("以「"))).check { view, error ->
            if (error != null) throw error
            account = (view as TextView).contentDescription.toString().removePrefix("以 ").removeSuffix(" 登录")
        }.perform(click())
        check(account.isNotEmpty())
        return account
    }
    private fun asyncJs(web: WebView, body: String): Any {
        val key = "__cookProbe" + UUID.randomUUID().toString().replace("-", "")
        js(web, "(async()=>{window.$key={done:false};try{const value=await(async()=>{$body})();window.$key={done:true,ok:true,value};}catch{window.$key={done:true,ok:false};}})();true")
        waitFor(25) { (js(web, "window.$key?.done === true") as? Boolean) == true }
        val result = js(web, "window.$key") as JSONObject
        js(web, "delete window.$key;true")
        check(result.getBoolean("ok"))
        return result.opt("value") ?: JSONObject.NULL
    }
    private fun js(web: WebView, script: String): Any? {
        val latch = CountDownLatch(1)
        var result: String? = null
        instrumentation.runOnMainSync { web.evaluateJavascript(script) { value -> result = value; latch.countDown() } }
        check(latch.await(8, TimeUnit.SECONDS)) { "WebView observation timed out" }
        return JSONArray("[${result ?: "null"}]").get(0).takeUnless { it == JSONObject.NULL }
    }
    private fun <T> onMain(body: () -> T): T {
        var result: T? = null
        instrumentation.runOnMainSync { result = body() }
        @Suppress("UNCHECKED_CAST")
        return result as T
    }
    private fun waitFor(seconds: Int, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds.toLong())
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(100)
        }
        error("Runtime observation timed out")
    }
    private fun webView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) webView(view.getChildAt(index))?.let { return it }
        return null
    }
    private fun screenshot(context: Context, name: String) {
        instrumentation.uiAutomation.takeScreenshot()?.let { image ->
            File(context.getExternalFilesDir(null), name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }
}
