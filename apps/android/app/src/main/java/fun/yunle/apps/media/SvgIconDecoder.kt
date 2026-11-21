package `fun`.yunle.apps.media

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RectF
import androidx.core.graphics.createBitmap
import com.caverock.androidsvg.SVG
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.SAXNotRecognizedException
import org.xml.sax.SAXNotSupportedException
import org.xml.sax.SAXParseException
import org.xml.sax.ext.DefaultHandler2
import java.io.ByteArrayInputStream
import javax.xml.parsers.SAXParserFactory
import kotlin.math.roundToInt

/** Validates the XML and bounds reference expansion before AndroidSVG sees the bytes. */
internal object SvgResourcePolicy {
    const val MAXIMUM_BYTES = 2 * 1024 * 1024
    private const val SVG_NAMESPACE = "http://www.w3.org/2000/svg"
    private const val MAXIMUM_ELEMENT_DEPTH = 32
    private const val MAXIMUM_NODE_COUNT = 5_000
    private const val MAXIMUM_ATTRIBUTE_LENGTH = 300_000
    private const val MAXIMUM_EXPANSION_DEPTH = 64
    private const val MAXIMUM_EXPANSION_COST = 50_000
    private val disallowedElements = setOf(
        "script", "foreignobject", "animate", "animatetransform", "animatemotion", "set", "image",
    )
    private val xmlEncoding = Regex("""\bencoding\s*=\s*(['"])([^'"]+)\1""")
    private val urlStart = Regex("""url\s*\(""", RegexOption.IGNORE_CASE)
    private val urlValue = Regex("""\s*+(['"]?)(#[^\s()'"#\\]++)\1\s*+\)""")
    private val localFragment = Regex("""#[^\s()'"#\\]+""")

    fun accepts(bytes: ByteArray): Boolean = inspect(bytes) != null

    internal data class Document(val usesViewBoxOnly: Boolean)

    fun inspect(bytes: ByteArray): Document? {
        if (bytes.isEmpty() || bytes.size > MAXIMUM_BYTES) return null
        return try {
            val xml = bytes.decodeToString(throwOnInvalidSequence = true)
            if ('\u0000' in xml || xml.contains("<!DOCTYPE", ignoreCase = true) ||
                xml.contains("<!ENTITY", ignoreCase = true)
            ) {
                return null
            }
            val prolog = xml.removePrefix("\uFEFF")
            if (prolog.startsWith("<?xml") && prolog.getOrNull(5)?.isWhitespace() == true) {
                val encoding = xmlEncoding.find(prolog.substringBefore("?>"))?.groupValues?.get(2)
                if (encoding != null && !encoding.equals("UTF-8", ignoreCase = true)) return null
            }

            val handler = PolicyHandler()
            val factory = SAXParserFactory.newInstance().apply {
                isNamespaceAware = true
                isValidating = false
                setFeature("http://xml.org/sax/features/external-general-entities", false)
                setFeature("http://xml.org/sax/features/external-parameter-entities", false)
            }
            factory.newSAXParser().xmlReader.apply {
                try {
                    setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
                } catch (_: SAXNotRecognizedException) {
                    // Android's Expat reader rejects DTDs through the required lexical handler.
                } catch (_: SAXNotSupportedException) {
                    // The lexical handler also covers parsers without this feature.
                }
                setProperty("http://xml.org/sax/properties/lexical-handler", handler)
                contentHandler = handler
                entityResolver = handler
                errorHandler = handler
                parse(InputSource(ByteArrayInputStream(bytes)).apply { encoding = "UTF-8" })
            }
            if (handler.acceptsGraph()) Document(handler.usesViewBoxOnly) else null
        } catch (_: Exception) {
            null
        }
    }

    private class Node(val index: Int, val isStyle: Boolean) {
        val text = StringBuilder()
    }

    private data class Expansion(val cost: Int, val height: Int)

    private class PolicyHandler : DefaultHandler2() {
        private val stack = ArrayDeque<Node>()
        private val edges = mutableListOf<MutableList<Int>>()
        private val ids = mutableMapOf<String, Int>()
        private val references = mutableListOf<Pair<Int, String>>()
        private val namespaceDeclarations = mutableListOf<String>()
        var usesViewBoxOnly = false
            private set

        override fun startDTD(name: String?, publicId: String?, systemId: String?) = reject()

        override fun resolveEntity(publicId: String?, systemId: String?): InputSource = reject()

        override fun resolveEntity(name: String?, publicId: String?, baseURI: String?, systemId: String?): InputSource =
            reject()

        override fun error(e: SAXParseException) { throw e }

        override fun fatalError(e: SAXParseException) { throw e }

        override fun processingInstruction(target: String, data: String?) {
            if (target.equals("xml-stylesheet", ignoreCase = true)) reject()
        }

        override fun startPrefixMapping(prefix: String, uri: String) {
            if (uri.length > MAXIMUM_ATTRIBUTE_LENGTH) reject()
            namespaceDeclarations.add(uri)
        }

        override fun startElement(uri: String?, localName: String, qName: String, attributes: Attributes) {
            val name = localName.lowercase()
            val parent = stack.lastOrNull()
            if ((!uri.isNullOrEmpty() && uri != SVG_NAMESPACE) || name in disallowedElements ||
                stack.size + 1 >= MAXIMUM_ELEMENT_DEPTH || edges.size + 1 >= MAXIMUM_NODE_COUNT ||
                parent?.isStyle == true || (parent == null && (edges.isNotEmpty() || name != "svg"))
            ) {
                reject()
            }

            val node = Node(edges.size, name == "style")
            edges.add(mutableListOf())
            if (parent == null) {
                usesViewBoxOnly = (0 until attributes.length).none {
                    attributes.getLocalName(it) in listOf("width", "height")
                }
            } else {
                edges[parent.index].add(node.index)
            }
            stack.addLast(node)
            namespaceDeclarations.forEach { scanUrls(it, node, stripComments = false) }
            namespaceDeclarations.clear()
            var hasId = false
            for (index in 0 until attributes.length) {
                val key = attributes.getLocalName(index).lowercase()
                val raw = attributes.getValue(index)
                if (raw.length > MAXIMUM_ATTRIBUTE_LENGTH || key.startsWith("on")) reject()
                val value = raw.trim()
                when (key) {
                    "id" -> {
                        if (hasId || ids.putIfAbsent(value, node.index) != null) reject()
                        hasId = true
                    }
                    "href" -> addReference(node.index, value)
                }
                scanUrls(value, node, stripComments = key == "style")
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) {
            stack.lastOrNull()?.text?.append(ch, start, length)
        }

        override fun endElement(uri: String?, localName: String?, qName: String?) {
            val node = stack.removeLast()
            // SAX may split a token across callbacks, including at a CDATA boundary.
            scanUrls(node.text.toString(), node, stripComments = node.isStyle)
        }

        private fun scanUrls(text: String, node: Node, stripComments: Boolean) {
            val raw = urlFragments(text, node.isStyle)
            val uncommented = if (stripComments) withoutCssComments(text) else text
            if (uncommented == text) {
                raw.forEach { addReference(node.index, it) }
                return
            }

            // The renderer strips CSS comments. Account for tokens in both forms without
            // counting an unchanged reference twice.
            val rawCounts = raw.groupingBy { it }.eachCount()
            val uncommentedCounts = urlFragments(uncommented, node.isStyle).groupingBy { it }.eachCount()
            for (fragment in rawCounts.keys + uncommentedCounts.keys) {
                repeat(maxOf(rawCounts[fragment] ?: 0, uncommentedCounts[fragment] ?: 0)) {
                    addReference(node.index, fragment)
                }
            }
        }

        private fun urlFragments(text: String, isStyle: Boolean): Sequence<String> {
            if (text.contains("@import", ignoreCase = true)) reject()
            return urlStart.findAll(text).map { match ->
                if (isStyle) reject()
                urlValue.matchAt(text, match.range.last + 1)?.groupValues?.get(2) ?: reject()
            }
        }

        private fun addReference(node: Int, value: String) {
            if (!localFragment.matches(value)) reject()
            references.add(node to value.substring(1))
        }

        fun acceptsGraph(): Boolean {
            if (edges.isEmpty() || stack.isNotEmpty()) return false
            for ((source, id) in references) {
                edges[source].add(ids[id] ?: return false)
            }
            val expansions = arrayOfNulls<Expansion>(edges.size)
            val visiting = BooleanArray(edges.size)
            fun expand(node: Int, depth: Int): Expansion? {
                if (depth >= MAXIMUM_EXPANSION_DEPTH || visiting[node]) return null
                expansions[node]?.let { return it.takeIf { depth + it.height <= MAXIMUM_EXPANSION_DEPTH } }
                visiting[node] = true
                var cost = 1
                var height = 1
                for (edge in edges[node]) {
                    val child = expand(edge, depth + 1) ?: return null
                    cost += child.cost
                    if (cost > MAXIMUM_EXPANSION_COST) return null
                    height = maxOf(height, child.height + 1)
                }
                visiting[node] = false
                return Expansion(cost, height).also { expansions[node] = it }
            }
            return expand(0, 0) != null
        }
    }

    private fun withoutCssComments(text: String): String {
        var comment = text.indexOf("/*")
        if (comment < 0) return text
        return buildString {
            var start = 0
            while (comment >= 0) {
                val end = text.indexOf("*/", comment + 2)
                if (end < 0) break
                append(text, start, comment)
                start = end + 2
                comment = text.indexOf("/*", start)
            }
            append(text, start, text.length)
        }
    }

    private fun reject(): Nothing = throw SAXException("SVG resource policy rejected the document")
}

internal object SvgIconDecoder {
    init {
        SVG.setInternalEntitiesEnabled(false)
    }

    fun decode(bytes: ByteArray, maximumPixelSize: Int): Bitmap? {
        val document = SvgResourcePolicy.inspect(bytes) ?: return null
        return runCatching {
            val svg = ByteArrayInputStream(bytes).use(SVG::getFromInputStream)
            val viewBox = if (document.usesViewBoxOnly) svg.documentViewBox else null
            val width = viewBox?.width() ?: svg.documentWidth
            val height = viewBox?.height() ?: svg.documentHeight
            if (!width.isFinite() || !height.isFinite() || width <= 0 || height <= 0 ||
                maxOf(width, height) > 100_000f
            ) {
                return null
            }
            val edge = maximumPixelSize.coerceIn(1, 2048)
            val scale = edge.toDouble() / maxOf(width, height)
            if (!scale.toFloat().isFinite()) return null
            val bitmap = createBitmap(
                (width * scale).roundToInt().coerceAtLeast(1),
                (height * scale).roundToInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            )
            val canvas = Canvas(bitmap)
            canvas.scale(scale.toFloat(), scale.toFloat())
            svg.renderToCanvas(canvas, RectF(0f, 0f, width, height))
            bitmap
        }.getOrNull()
    }
}
