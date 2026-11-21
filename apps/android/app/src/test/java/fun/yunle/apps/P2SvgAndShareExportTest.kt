package `fun`.yunle.apps

import com.google.zxing.BinaryBitmap
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import `fun`.yunle.apps.catalog.ApplicationShareAppearance
import `fun`.yunle.apps.catalog.ApplicationShareCardRenderer
import `fun`.yunle.apps.catalog.ApplicationShareExporter
import `fun`.yunle.apps.media.SvgResourcePolicy
import `fun`.yunle.apps.scanner.QrCodeDecoder
import `fun`.yunle.apps.scanner.ScanParser
import `fun`.yunle.apps.scanner.ScanPurpose
import `fun`.yunle.apps.scanner.ScanResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant
import java.util.Base64
import java.util.zip.ZipFile

class P2SvgAndShareExportTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun svgAllowsForwardLocalReferences() {
        val svg = """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24">
                <use xlink:href="#shape"/>
                <defs>
                    <path id="shape" d="M0 0h24v24z" fill="url(#gradient)"/>
                    <linearGradient id="gradient"><stop stop-color="#fff"/></linearGradient>
                </defs>
                <style>path { opacity: 0.5 }</style>
                <desc>url( '#gradient' )</desc>
            </svg>
        """.trimIndent()
        assertTrue(SvgResourcePolicy.accepts(svg.toByteArray()))
        assertTrue(SvgResourcePolicy.accepts("<svg><use href='#later'/><defs><g id='later'/></defs></svg>".toByteArray()))
    }

    @Test
    fun svgRejectsUnsafeXmlAndReferences() {
        val rejected = listOf(
            "",
            "<!DoCtYpE svg><svg/>",
            "<svg><!-- <!EnTiTy a 'b'> --></svg>",
            "<?xml-stylesheet href='https://example.org/style.css'?><svg/>",
            "<svg><SCRIPT/></svg>",
            "<svg><foreignObject/></svg>",
            "<svg><image/></svg>",
            "<svg><animate/></svg>",
            "<svg><animateMotion/></svg>",
            "<svg><animateTransform/></svg>",
            "<svg><set/></svg>",
            "<svg onclick='action()'/>",
            "<svg><use href='https://example.org/a.svg#x'/></svg>",
            "<svg><use href='#'/></svg>",
            "<svg><use href='#missing'/></svg>",
            "<svg><g id='x'/><g id='x'/></svg>",
            "<svg><g id='x'/><style>path { fill: url(#x) }</style></svg>",
            "<svg><g id='x'/><style>path { fill: u/**/rl(#x) }</style></svg>",
            "<svg><style> @ImPoRt 'style.css'; </style></svg>",
            "<svg><style>@im<![CDATA[port]]> 'style.css';</style></svg>",
            "<svg><text><![CDATA[url(https://example.org/a.svg)]]></text></svg>",
            "<svg><desc>u<![CDATA[rl(https://example.org/a.svg)]]></desc></svg>",
            "<svg><path fill='u&#114;l(https://example.org/a.svg)'/></svg>",
            "<svg><path style='fill: u/**/rl(https://example.org/a.svg)'/></svg>",
            "<svg><path style='fill: red; /* url(https://example.org/a.svg) */'/></svg>",
            "<svg><path fill='url(#unknown)'/></svg>",
            "<svg><path fill='url(#x'/><g id='x'/></svg>",
            "<svg><use id='a' href='#b'/><use id='b' href='#a'/></svg>",
            "<svg xmlns='https://example.org/svg'/>",
            "<svg><g xmlns='https://example.org/svg'/></svg>",
            "<g/>",
        )
        for (svg in rejected) assertFalse(svg, SvgResourcePolicy.accepts(svg.toByteArray()))
        assertFalse(SvgResourcePolicy.accepts("<svg/>".toByteArray(Charsets.UTF_16)))
        assertFalse(SvgResourcePolicy.accepts(ByteArray(2 * 1024 * 1024 + 1)))
    }

    @Test
    fun svgBoundsTreeAndExpandedReferences() {
        val treeAtLimit = "<svg>" + "<g>".repeat(31) + "</g>".repeat(31) + "</svg>"
        val nodesAtLimit = "<svg>" + "<g/>".repeat(4999) + "</svg>"
        val oversizedAttribute = "<svg data-name='" + "x".repeat(300_001) + "'/>"
        val deepReferences = buildString {
            append("<svg><defs><g id='g0'/>")
            for (i in 1..64) append("<g id='g$i'><use href='#g${i - 1}'/></g>")
            append("</defs><use href='#g64'/></svg>")
        }
        val largeExpansion = buildString {
            append("<svg><defs><g id='g0'/>")
            for (i in 1..16) append("<g id='g$i'><use href='#g${i - 1}'/><use href='#g${i - 1}'/></g>")
            append("</defs><use href='#g16'/></svg>")
        }
        for (svg in listOf(treeAtLimit, nodesAtLimit, oversizedAttribute, deepReferences, largeExpansion)) {
            assertFalse(SvgResourcePolicy.accepts(svg.toByteArray()))
        }
    }

    @Test
    fun generatedQrDecodesToThePublicApplicationRoute() {
        val url = ApplicationShareExporter.requirePosterUrl(publicApp("qr-demo"))
        val code = ApplicationShareCardRenderer.qrCode(url)
        val pixels = IntArray(code.width * code.height) { offset ->
            if (code[offset % code.width, offset / code.width]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
        }
        val luminance = RGBLuminanceSource(code.width, code.height, pixels)
        val decoded = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(luminance))).text
        assertEquals("https://apps.yunle.fun/app/qr-demo", decoded)
        assertEquals(listOf(url), QrCodeDecoder.decodeLuminancePixels(pixels, code.width, code.height))
        assertEquals(ScanResult.Destination(NativeDestination.Application("qr-demo")), ScanParser.parse(decoded, ScanPurpose.GENERAL))
    }

    @Test
    fun batchDeduplicatesKeysAndStylesAndArchivesValidCardsWithFailures() = runBlocking {
        val app = publicApp("demo")
        val progress = mutableListOf<Triple<Int, Int, String>>()
        val exporter = ApplicationShareExporter(temporary.root) { current, appearance, _ ->
            if (current.key == "partial" && appearance == ApplicationShareAppearance.LIGHT) error("无法渲染")
            png
        }
        val result = exporter.exportDirectory(
            apps = listOf(
                app,
                app.copy(id = "duplicate", name = "重复"),
                publicApp("private").copy(isPublic = false),
                publicApp("workshop").copy(accessWorkshopId = "workshop-id"),
                publicApp("owner").copy(accessOwnerId = "owner-id"),
                publicApp("url").copy(launchUrl = "http://example.org/"),
                publicApp("partial"),
            ),
            appearances = listOf(ApplicationShareAppearance.DARK, ApplicationShareAppearance.LIGHT, ApplicationShareAppearance.DARK),
            progress = { done, total, name -> progress += Triple(done, total, name) },
            iconLoader = { null },
        )
        try {
            val filenames = listOf("demo-light.png", "demo-dark.png", "partial-dark.png")
            assertEquals(filenames, result.manifest.cards.map { it.filename })
            assertTrue(result.manifest.cards.all { it.usedFallbackIcon })
            assertEquals(listOf("private", "workshop", "owner", "url", "partial"), result.manifest.failures.map { it.slug })
            assertEquals(Triple(0, 6, app.name), progress.first())
            assertEquals(Triple(6, 6, "partial"), progress.last())
            assertEquals("yunlefun-catalog-share.zip", result.zipFile.name)
            val manifest = File(result.directory, "manifest.json")
            ZipFile(result.zipFile).use { zip ->
                assertEquals((filenames + "manifest.json").toSet(), zip.entries().asSequence().map { it.name }.toSet())
                assertEquals(manifest.readText(), zip.getInputStream(zip.getEntry("manifest.json")).bufferedReader().use { it.readText() })
                for (filename in filenames) {
                    assertArrayEquals(png, zip.getInputStream(zip.getEntry(filename)).use { it.readBytes() })
                }
            }
            val json = JSONObject(manifest.readText())
            assertEquals(1, json.getInt("schemaVersion"))
            assertEquals(1080, json.getInt("pixelWidth"))
            assertEquals(1620, json.getInt("pixelHeight"))
            assertEquals(Instant.parse(result.manifest.generatedAtIso), Instant.parse(json.getString("generatedAt")))
            val first = json.getJSONArray("cards").getJSONObject(0)
            assertEquals(app.id, first.getString("applicationID"))
            assertEquals(app.key, first.getString("slug"))
            assertEquals("https://apps.yunle.fun/app/demo", first.getString("websiteUrl"))
            assertEquals("demo-light.png", first.getString("filename"))
            assertEquals(5, json.getJSONArray("failures").length())
        } finally {
            result.discard()
        }
        assertFalse(result.directory.exists())
    }

    @Test
    fun cancellingBatchDeletesCardsAlreadyWritten() = runBlocking {
        val exporter = ApplicationShareExporter(temporary.root) { _, _, _ -> png }
        val secondAppStarted = CompletableDeferred<Unit>()
        val job = launch {
            exporter.exportDirectory(
                apps = listOf(publicApp("first"), publicApp("second")),
                appearances = listOf(ApplicationShareAppearance.LIGHT),
                progress = { _, _, _ -> },
                iconLoader = { app ->
                    if (app.key == "second") {
                        secondAppStarted.complete(Unit)
                        awaitCancellation()
                    }
                    null
                },
            )
        }
        secondAppStarted.await()
        val root = File(temporary.root, "ShareExports")
        assertTrue(root.listFiles().orEmpty().single().resolve("first-light.png").isFile)
        job.cancelAndJoin()
        assertTrue(job.isCancelled)
        assertTrue(root.listFiles().orEmpty().isEmpty())
    }

    @Test
    fun cancellationFromIconLoaderPropagates() {
        val exporter = ApplicationShareExporter(temporary.root) { _, _, _ -> png }
        assertThrows(CancellationException::class.java) {
            runBlocking {
                exporter.exportDirectory(
                    apps = listOf(publicApp("cancelled")),
                    appearances = listOf(ApplicationShareAppearance.LIGHT),
                    progress = { _, _, _ -> },
                    iconLoader = { throw CancellationException("cancelled") },
                )
            }
        }
        assertTrue(File(temporary.root, "ShareExports").listFiles().orEmpty().isEmpty())
    }

    private fun publicApp(key: String) = CatalogApp(
        id = "id-$key",
        key = key,
        name = key,
        description = "示例应用",
        author = "云乐坊",
        ownerLogin = "yunlefun",
        category = "工具",
        emoji = "☁️",
        launchUrl = "https://example.org/$key",
        logo = null,
        themeColor = null,
        trustedHosts = emptyList(),
        immersive = false,
        audience = "public",
        isPublic = true,
    )

    private val png = Base64.getDecoder().decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aR2cAAAAASUVORK5CYII=",
    )
}
