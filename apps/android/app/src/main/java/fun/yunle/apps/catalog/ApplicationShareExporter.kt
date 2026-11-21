package `fun`.yunle.apps.catalog

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withClip
import androidx.core.graphics.withTranslation
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.ReaderException
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.Decoder
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.google.zxing.qrcode.detector.Detector
import `fun`.yunle.apps.BoundedHttpsImageLoader
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.NativeDeepLinkRouter
import `fun`.yunle.apps.NativeDestination
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal enum class ApplicationShareAppearance(val key: String, val label: String) {
    LIGHT("light", "浅色"),
    DARK("dark", "深色"),
}

@Serializable
internal data class ApplicationShareExportManifest(
    val schemaVersion: Int = 1,
    @SerialName("generatedAt") val generatedAtIso: String,
    val pixelWidth: Int = ApplicationShareCardRenderer.PIXEL_WIDTH,
    val pixelHeight: Int = ApplicationShareCardRenderer.PIXEL_HEIGHT,
    val cards: List<Card>,
    val failures: List<Failure>,
) {
    @Serializable
    data class Card(
        val applicationID: String,
        val slug: String,
        val name: String,
        val websiteUrl: String,
        val appearance: String,
        val filename: String,
        val usedFallbackIcon: Boolean,
    )

    @Serializable
    data class Failure(val slug: String, val message: String)

    fun toJsonString(): String = json.encodeToString(this)

    private companion object {
        val json = Json {
            encodeDefaults = true
            prettyPrint = true
        }
    }
}

internal object ApplicationShareCardRenderer {
    const val PIXEL_WIDTH = 1080
    const val PIXEL_HEIGHT = 1620
    private const val QR_SIZE = 460
    private const val TEXT_WIDTH = 792

    private data class Palette(val background: Int, val card: Int, val text: Int, val muted: Int, val badge: Int)

    private val light = Palette(
        0xFFE9EEF9.toInt(), 0xFFFFFEFB.toInt(), 0xFF19223B.toInt(), 0xFF4F5C74.toInt(), 0xFFEAF0FC.toInt(),
    )
    private val dark = Palette(
        0xFF101525.toInt(), 0xFF202940.toInt(), 0xFFF6F8FF.toInt(), 0xFFC5CFE6.toInt(), 0xFF354361.toInt(),
    )

    fun render(app: CatalogApp, appearance: ApplicationShareAppearance, icon: Bitmap?): Bitmap {
        val url = ApplicationShareExporter.requirePosterUrl(app)
        val palette = if (appearance == ApplicationShareAppearance.DARK) dark else light
        val poster = createBitmap(PIXEL_WIDTH, PIXEL_HEIGHT, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(poster)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            canvas.drawColor(palette.background)
            paint.color = palette.card
            canvas.drawRoundRect(56f, 56f, 1024f, 1564f, 64f, 64f, paint)

            val badge = RectF(450f, 130f, 630f, 310f)
            paint.color = palette.badge
            canvas.drawRoundRect(badge, 44f, 44f, paint)
            if (icon == null) {
                val name = app.name.trim()
                val glyph = app.emoji.ifBlank {
                    if (name.isEmpty()) "云" else String(Character.toChars(name.codePointAt(0)))
                }
                drawText(canvas, glyph, 165f, 84f, palette.text, maxLines = 1, bold = true, width = 166)
            } else {
                val scale = minOf(badge.width() / icon.width, badge.height() / icon.height)
                val halfWidth = icon.width * scale / 2
                val halfHeight = icon.height * scale / 2
                val destination = RectF(
                    badge.centerX() - halfWidth, badge.centerY() - halfHeight,
                    badge.centerX() + halfWidth, badge.centerY() + halfHeight,
                )
                val clip = Path().apply { addRoundRect(badge, 44f, 44f, Path.Direction.CW) }
                canvas.withClip(clip) { drawBitmap(icon, null, destination, paint) }
            }

            drawText(canvas, app.name, 350f, 72f, palette.text, maxLines = 2, bold = true)
            drawText(canvas, "${app.author} · ${app.browseCategory}", 522f, 32f, palette.muted, maxLines = 2)
            drawText(
                canvas, app.description.ifBlank { "在云乐坊工坊发现并使用这个轻量云应用。" },
                620f, 36f, palette.text, maxLines = 4,
            )

            paint.color = Color.WHITE
            canvas.drawRoundRect(282f, 822f, 798f, 1338f, 32f, 32f, paint)
            val matrix = qrCode(url)
            val pixels = IntArray(QR_SIZE * QR_SIZE) { position ->
                if (matrix[position % QR_SIZE, position / QR_SIZE]) Color.BLACK else Color.WHITE
            }
            val qr = Bitmap.createBitmap(pixels, QR_SIZE, QR_SIZE, Bitmap.Config.ARGB_8888)
            try {
                canvas.drawBitmap(qr, null, RectF(310f, 850f, 770f, 1310f), null)
            } finally {
                qr.recycle()
            }
            drawText(canvas, "长按识别或使用云乐坊扫码打开", 1380f, 34f, palette.text, maxLines = 1, bold = true)
            val urlTextSize = if (url.length > 100) 20f else 28f
            drawText(canvas, url, 1438f, urlTextSize, palette.muted, maxLines = 4, width = 864)
            return poster
        } catch (error: Throwable) {
            poster.recycle()
            throw error
        }
    }

    fun png(app: CatalogApp, appearance: ApplicationShareAppearance, icon: Bitmap?): ByteArray {
        val poster = render(app, appearance, icon)
        try {
            return pngBytes(poster)
        } finally {
            poster.recycle()
        }
    }

    fun pngBytes(poster: Bitmap): ByteArray = ByteArrayOutputStream().use { output ->
        check(poster.compress(Bitmap.CompressFormat.PNG, 100, output)) { "无法编码 PNG 海报。" }
        output.toByteArray()
    }

    fun qrCode(url: String): BitMatrix {
        val writer = QRCodeWriter()
        val hints = mutableMapOf<EncodeHintType, Any>(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 4,
        )
        // Some payloads produce an accidental finder pattern in the automatic mask.
        // Try the other masks if a scanner cannot locate and decode the generated matrix.
        for (mask in -1..7) {
            if (mask >= 0) hints[EncodeHintType.QR_MASK_PATTERN] = mask
            val matrix = writer.encode(url, BarcodeFormat.QR_CODE, QR_SIZE, QR_SIZE, hints)
            val decoded = try {
                Decoder().decode(Detector(matrix).detect().bits).text
            } catch (_: ReaderException) {
                continue
            }
            if (decoded == url) return matrix
        }
        error("无法生成可识别的二维码。")
    }

    private fun drawText(
        canvas: Canvas,
        value: String,
        top: Float,
        size: Float,
        color: Int,
        maxLines: Int,
        bold: Boolean = false,
        width: Int = TEXT_WIDTH,
    ) {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
        val layout = StaticLayout.Builder.obtain(value, 0, value.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setIncludePad(false)
            .build()
        canvas.withTranslation((PIXEL_WIDTH - width) / 2f, top) { layout.draw(this) }
    }
}

internal class ApplicationShareExportDirectory(
    val directory: File,
    val zipFile: File,
    val manifest: ApplicationShareExportManifest,
) {
    fun discard() {
        directory.deleteRecursively()
    }
}

internal class ApplicationShareExporter(
    private val cacheDir: File,
    private val encodeCard: (CatalogApp, ApplicationShareAppearance, Bitmap?) -> ByteArray = ApplicationShareCardRenderer::png,
) {
    suspend fun exportDirectory(
        apps: List<CatalogApp>,
        appearances: List<ApplicationShareAppearance>,
        progress: (Int, Int, String) -> Unit,
        iconLoader: suspend (CatalogApp) -> Bitmap?,
    ): ApplicationShareExportDirectory {
        val unique = apps.distinctBy(CatalogApp::key)
        val selected = ApplicationShareAppearance.entries.filter { it in appearances }
        require(unique.isNotEmpty() && selected.isNotEmpty()) { "请选择公开应用和海报样式。" }
        return createExport("YunLeFun-Share-") { directory ->
            val cards = mutableListOf<ApplicationShareExportManifest.Card>()
            val failures = mutableListOf<ApplicationShareExportManifest.Failure>()
            val generatedAt = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()
            unique.forEachIndexed { index, app ->
                currentCoroutineContext().ensureActive()
                progress(index, unique.size, app.name)
                val messages = mutableListOf<String>()
                try {
                    val url = requirePosterUrl(app)
                    val icon = loadIcon(app, iconLoader)
                    for (appearance in selected) {
                        currentCoroutineContext().ensureActive()
                        val filename = posterFilename(app, appearance)
                        val file = File(directory, filename)
                        try {
                            file.writeBytes(encodeCard(app, appearance, icon))
                            cards += ApplicationShareExportManifest.Card(
                                applicationID = app.id,
                                slug = app.key,
                                name = app.name,
                                websiteUrl = url,
                                appearance = appearance.key,
                                filename = filename,
                                usedFallbackIcon = icon == null,
                            )
                        } catch (error: CancellationException) {
                            throw error
                        } catch (error: Exception) {
                            file.delete()
                            currentCoroutineContext().ensureActive()
                            messages += "${appearance.label}海报：${error.localizedMessage ?: "生成失败"}"
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    currentCoroutineContext().ensureActive()
                    messages += error.localizedMessage ?: "无法导出此应用。"
                }
                if (messages.isNotEmpty()) {
                    failures += ApplicationShareExportManifest.Failure(app.key, messages.joinToString("；"))
                }
                progress(index + 1, unique.size, app.name)
            }
            currentCoroutineContext().ensureActive()
            val manifest = ApplicationShareExportManifest(generatedAtIso = generatedAt, cards = cards, failures = failures)
            val manifestFile = File(directory, "manifest.json").apply { writeText(manifest.toJsonString()) }
            val zip = File(directory, ZIP_FILENAME)
            ZipOutputStream(zip.outputStream().buffered()).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                for (file in listOf(manifestFile) + cards.map { File(directory, it.filename) }) {
                    currentCoroutineContext().ensureActive()
                    output.putNextEntry(ZipEntry(file.name))
                    file.inputStream().use { input ->
                        while (true) {
                            currentCoroutineContext().ensureActive()
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                    }
                    output.closeEntry()
                }
            }
            ApplicationShareExportDirectory(directory, zip, manifest)
        }
    }

    private suspend fun <T> createExport(prefix: String, write: suspend (File) -> T): T {
        var pendingDirectory: File? = null
        var complete = false
        try {
            val result = withContext(Dispatchers.IO) {
                val root = File(cacheDir, SHARE_EXPORTS)
                check(root.isDirectory || root.mkdirs() || root.isDirectory) { "无法创建导出目录。" }
                val directory = File(root, prefix + UUID.randomUUID())
                check(directory.mkdir()) { "无法创建导出目录。" }
                pendingDirectory = directory
                write(directory).also { currentCoroutineContext().ensureActive() }
            }
            currentCoroutineContext().ensureActive()
            complete = true
            return result
        } finally {
            val directory = pendingDirectory
            if (!complete && directory != null) {
                withContext(NonCancellable + Dispatchers.IO) { directory.deleteRecursively() }
            }
        }
    }

    companion object {
        const val ZIP_FILENAME = "yunlefun-catalog-share.zip"
        private const val SHARE_EXPORTS = "ShareExports"

        fun publicUrlOrNull(app: CatalogApp): String? {
            if (!app.isPublic || app.isUnavailable || (app.audience != null && app.audience != "public") ||
                app.accessWorkshopId != null || app.accessOwnerId != null || app.personalMarketOwnerLogin != null ||
                !CatalogApp.validKey(app.key)
            ) {
                return null
            }
            val url = "https://apps.yunle.fun/app/${app.key}"
            return url.takeIf { NativeDeepLinkRouter.parse(url) == NativeDestination.Application(app.key) }
        }

        fun requirePosterUrl(app: CatalogApp): String {
            val url = requireNotNull(publicUrlOrNull(app)) { "仅支持分享可访问的公开应用。" }
            require(app.launchUrl?.let { CatalogApp.isHttps(it) } == true) { "应用暂无可分享的启动网址。" }
            return url
        }

        fun posterFilename(app: CatalogApp, appearance: ApplicationShareAppearance): String =
            "${app.key}-${appearance.key}.png"

        suspend fun loadIcon(app: CatalogApp, loader: suspend (CatalogApp) -> Bitmap?): Bitmap? = try {
            loader(app)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            currentCoroutineContext().ensureActive()
            null
        }

        suspend fun exportSinglePng(context: Context, app: CatalogApp, appearance: ApplicationShareAppearance): File {
            requirePosterUrl(app)
            val exporter = ApplicationShareExporter(context.cacheDir)
            return exporter.createExport("YunLeFun-Poster-") { directory ->
                val expiry = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
                directory.parentFile?.listFiles()?.forEach { previous ->
                    if (previous.name.startsWith("YunLeFun-Poster-") && previous.lastModified() < expiry) {
                        previous.deleteRecursively()
                    }
                }
                val icon = loadIcon(app) { BoundedHttpsImageLoader.loadBitmap(it.logo) }
                currentCoroutineContext().ensureActive()
                File(directory, posterFilename(app, appearance)).apply {
                    writeBytes(exporter.encodeCard(app, appearance, icon))
                }
            }
        }

        fun uriFor(context: Context, file: File): Uri =
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

        @RequiresApi(Build.VERSION_CODES.Q)
        suspend fun savePngToGallery(context: Context, pngBytes: ByteArray, displayName: String): Uri =
            withContext(Dispatchers.IO) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/云乐坊")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = checkNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)) {
                    "无法创建相册图片。"
                }
                try {
                    checkNotNull(resolver.openOutputStream(uri)) { "无法写入相册图片。" }.use { it.write(pngBytes) }
                    currentCoroutineContext().ensureActive()
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    check(resolver.update(uri, values, null, null) == 1) { "无法保存相册图片。" }
                    uri
                } catch (error: Exception) {
                    runCatching { resolver.delete(uri, null, null) }
                    throw error
                }
            }
    }
}
