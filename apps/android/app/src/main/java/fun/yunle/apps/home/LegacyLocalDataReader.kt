package `fun`.yunle.apps.home

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

internal fun interface LegacyLocalDataReading {
    suspend fun read(): Map<String, String>
}

internal class WebViewLegacyLocalDataReader(
    context: Context,
    private val timeoutMillis: Long = 20_000L,
) : LegacyLocalDataReading {
    private val appContext = context.applicationContext

    override suspend fun read(): Map<String, String> {
        val raw = withTimeoutOrNull(timeoutMillis) {
            withContext(Dispatchers.Main.immediate) { readWebView() }
        } ?: throw LegacyImportException(LegacyImportError.TIMED_OUT)
        return withContext(Dispatchers.Default) {
            val result = try {
                Json.parseToJsonElement(raw)
            } catch (_: IllegalArgumentException) {
                throw LegacyImportException(LegacyImportError.UNREADABLE)
            }
            when (result) {
                is JsonObject -> LegacyLocalData.fromJson(result).values
                JsonPrimitive("invalid") -> throw LegacyImportException(LegacyImportError.INVALID_DATA)
                else -> throw LegacyImportException(LegacyImportError.UNREADABLE)
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun readWebView(): String {
        // The Capacitor origin lives in the default WebView profile.
        val webView = try {
            WebView(appContext)
        } catch (e: Exception) {
            throw LegacyImportException(LegacyImportError.UNREADABLE, e)
        }
        try {
            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
            }
            return suspendCancellableCoroutine { continuation ->
                fun fail() {
                    if (continuation.isActive) {
                        continuation.resumeWithException(LegacyImportException(LegacyImportError.UNREADABLE))
                    }
                }
                webView.webViewClient = object : WebViewClient() {
                    private val servedDocument = AtomicBoolean(false)
                    private var didEvaluate = false

                    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                        if (request.isForMainFrame && request.method == "GET" && request.url.toString() == IMPORT_URL) {
                            servedDocument.set(true)
                            return WebResourceResponse(
                                "text/html", "UTF-8", 200, "OK",
                                mapOf("Content-Security-Policy" to CSP, "Cache-Control" to "no-store"),
                                ByteArrayInputStream(HTML),
                            )
                        }
                        return WebResourceResponse(
                            "text/plain", "UTF-8", 404, "Not Found", emptyMap(),
                            ByteArrayInputStream(byteArrayOf()),
                        )
                    }

                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                        !request.isForMainFrame || request.method != "GET" || request.url.toString() != IMPORT_URL

                    override fun onPageFinished(view: WebView, url: String) {
                        if (url != IMPORT_URL || view.url != IMPORT_URL || !continuation.isActive || didEvaluate) return
                        if (!servedDocument.get()) {
                            fail()
                            return
                        }
                        didEvaluate = true
                        try {
                            view.evaluateJavascript(READ_SCRIPT) { raw ->
                                if (raw == null) fail()
                                else if (continuation.isActive) continuation.resume(raw)
                            }
                        } catch (_: Exception) {
                            fail()
                        }
                    }

                    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                        if (request.isForMainFrame) fail()
                    }

                    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                        fail()
                        return true
                    }
                }
                webView.loadUrl(IMPORT_URL)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: LegacyImportException) {
            throw e
        } catch (e: Exception) {
            throw LegacyImportException(LegacyImportError.UNREADABLE, e)
        } finally {
            // Each cleanup step runs on Main, including after cancellation or renderer loss.
            runCatching { webView.stopLoading() }
            runCatching { webView.removeAllViews() }
            webView.destroy()
        }
    }

    private companion object {
        const val IMPORT_URL = "https://localhost/__native_data_import__/index.html"
        const val CSP = "default-src 'none'; base-uri 'none'; form-action 'none'"
        val HTML = "<!doctype html><html><head><meta charset='utf-8'></head><body></body></html>".toByteArray()
        val READ_SCRIPT = """
            (() => {
                const result = {};
                const encoder = new TextEncoder();
                let size = 0;
                for (const key of ${Json.encodeToString(LegacyLocalData.KEYS)}) {
                    let value;
                    try {
                        value = localStorage.getItem(key);
                    } catch (_) {
                        return 'unreadable';
                    }
                    if (value === null) continue;
                    size += encoder.encode(key).length + encoder.encode(value).length;
                    if (size > ${LegacyLocalData.MAXIMUM_BYTES}) return 'invalid';
                    if (key === '${LegacyLocalData.SAVED_ACCOUNTS}') {
                        let accounts;
                        try {
                            accounts = JSON.parse(value);
                        } catch (_) {
                            return 'invalid';
                        }
                        if (!Array.isArray(accounts) || accounts.length > ${LegacyLocalData.MAXIMUM_ACCOUNT_HINTS}) {
                            return 'invalid';
                        }
                        const hints = [];
                        for (const account of accounts) {
                            if (!account || typeof account.uid !== 'string' ||
                                (account.nickname != null && typeof account.nickname !== 'string')) {
                                return 'invalid';
                            }
                            hints.push({uid: account.uid, nickname: account.nickname});
                        }
                        value = JSON.stringify(hints);
                    }
                    result[key] = value;
                }
                return result;
            })()
        """.trimIndent()
    }
}
