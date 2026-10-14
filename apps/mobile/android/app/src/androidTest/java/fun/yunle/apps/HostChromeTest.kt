package `fun`.yunle.apps

import android.content.Intent
import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HostChromeTest {
    @Test
    fun titleStaysCenteredAndActionsUseVectorIcons() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, HostWebViewActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(HostWebViewActivity.EXTRA_OPTIONS,
                    """{"url":"https://ac.yunyoujun.cn","title":"云空调","toolbarColor":"#12A6F5"}"""),
        )
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            fun descendants(view: View): List<View> = listOf(view) +
                if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
                else emptyList()
            val views = descendants(activity.window.decorView)
            val title = views.filterIsInstance<TextView>().single { it.text.toString() == "云空调" }
            val bar = title.parent as ViewGroup
            val density = activity.resources.displayMetrics.density
            val originalWidth = bar.width
            val height = bar.height
            for (widthDp in listOf(320, 412, 840)) {
                for (direction in listOf(View.LAYOUT_DIRECTION_LTR, View.LAYOUT_DIRECTION_RTL)) {
                    bar.layoutDirection = direction
                    title.text = "一个很长的应用标题用于验证标题始终居中且不会覆盖导航按钮"
                    val width = (widthDp * density).toInt()
                    bar.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                    bar.layout(0, 0, width, height)
                    assertEquals("Title must be centered in full toolbar", width / 2f,
                        (title.left + title.right) / 2f, 1f)
                    for (description in listOf("收起应用", "返回", "更多")) {
                        val action = descendants(bar).single { it.contentDescription == description }
                        assertTrue("Action must use an image, not a font glyph", action is ImageButton)
                        assertNotNull((action as ImageButton).drawable)
                        assertEquals((24 * density).toInt(), action.drawable.intrinsicWidth)
                        assertTrue(action.width >= 48 * density - 1)
                        assertTrue("Title cannot overlap actions", title.right <= action.left || title.left >= action.right)
                    }
                }
            }
            bar.layoutDirection = View.LAYOUT_DIRECTION_LTR
            title.text = "云空调"
            bar.measure(View.MeasureSpec.makeMeasureSpec(originalWidth, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
            bar.layout(0, 0, originalWidth, height)
        }
        instrumentation.waitForIdleSync()
        val screenshot = instrumentation.uiAutomation.takeScreenshot()
        val output = java.io.File(activity.getExternalFilesDir(null), "toolbar-verification.png")
        output.outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) }
        instrumentation.runOnMainSync { activity.finish() }
    }
}
