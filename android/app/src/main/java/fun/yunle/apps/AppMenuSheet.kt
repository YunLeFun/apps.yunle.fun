package `fun`.yunle.apps

import android.app.Activity
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.widget.NestedScrollView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import kotlin.math.roundToInt

internal data class AppMenuContent(
    val applicationName: String,
    val applicationOrigin: String,
    val applicationIconUrl: String?,
    val themeColor: String?,
    val description: String?,
    val detailsAvailable: Boolean,
)

/** Stable cross-platform action identifiers; labels remain platform-native. */
internal enum class AppMenuAction(
    val wireValue: String,
    val label: String,
    val iconResource: Int,
    val destructive: Boolean = false,
) {
    DETAILS("details", "查看详情与评价", R.drawable.ic_app_menu_details),
    SHARE("share", "分享", R.drawable.ic_app_menu_share),
    COPY_LINK("copy_link", "复制链接", R.drawable.ic_app_menu_link),
    OPEN_BROWSER("open_browser", "在浏览器中打开", R.drawable.ic_app_menu_open_browser),
    RELOAD("reload", "刷新", R.drawable.ic_app_menu_refresh),
    END("end", "结束", R.drawable.ic_app_menu_end, destructive = true),
}

/** Platform-native app actions shown from the title-bar overflow button. */
internal class AppMenuSheet(
    private val activity: Activity,
    private val content: AppMenuContent,
    private val onAction: (AppMenuAction) -> Unit,
) {
    private val isDark = activity.resources.configuration.uiMode and
        Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private val palette = AppMenuPalette(
        surface = Color.parseColor(if (isDark) "#211C1D" else "#FFFBFA"),
        primary = Color.parseColor(if (isDark) "#FFF8F6" else "#221E1E"),
        secondary = Color.parseColor(if (isDark) "#CFC3C5" else "#695F62"),
        divider = Color.parseColor(if (isDark) "#4D4244" else "#E2DCDC"),
        iconBackground = Color.parseColor(if (isDark) "#382E30" else "#F5ECEB"),
        destructive = Color.parseColor(if (isDark) "#FFB4AB" else "#C4251F"),
    )

    fun show() {
        val dialog = BottomSheetDialog(activity, R.style.AppAuthorizationBottomSheetDialog)
        val surface = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(10), dp(20), dp(20))
            background = roundedBackground(palette.surface, 24f, topOnly = true)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        surface.addView(View(dialog.context).apply {
            background = roundedBackground(palette.divider, 3f)
            contentDescription = "拖动以关闭应用菜单"
        }, LinearLayout.LayoutParams(dp(36), dp(5)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            bottomMargin = dp(18)
        })

        surface.addView(makeHeader(dialog))
        content.description?.takeIf { it.isNotBlank() }?.let { description ->
            surface.addView(makeText(description, 14f, palette.secondary).apply {
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }, layout(top = dp(12), bottom = dp(14)))
        }

        surface.addView(divider(dialog))
        if (content.detailsAvailable) {
            surface.addView(action(dialog, AppMenuAction.DETAILS))
        }
        surface.addView(action(dialog, AppMenuAction.SHARE))
        surface.addView(action(dialog, AppMenuAction.COPY_LINK))
        surface.addView(action(dialog, AppMenuAction.OPEN_BROWSER))
        surface.addView(action(dialog, AppMenuAction.RELOAD))
        surface.addView(divider(dialog))
        surface.addView(action(dialog, AppMenuAction.END))

        val scroll = NestedScrollView(dialog.context).apply {
            isFillViewport = false
            addView(surface, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }
        dialog.setContentView(scroll)
        dialog.show()
        dialog.behavior.apply {
            state = BottomSheetBehavior.STATE_EXPANDED
            skipCollapsed = true
        }
    }

    private fun makeHeader(dialog: BottomSheetDialog): View {
        val iconSize = dp(52)
        val fallback = makeText(
            content.applicationName.trim().take(1).ifBlank { "Y" },
            22f,
            readableOn(themeColor()),
            Typeface.BOLD,
            Gravity.CENTER,
        )
        val image = ImageView(dialog.context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
            contentDescription = "${content.applicationName} 图标"
        }
        val icon = FrameLayout(dialog.context).apply {
            background = roundedBackground(themeColor(), 13f)
            clipToOutline = true
            addView(fallback, FrameLayout.LayoutParams(iconSize, iconSize))
            addView(image, FrameLayout.LayoutParams(iconSize, iconSize))
        }
        BoundedHttpsImageLoader.load(activity, content.applicationIconUrl, image, fallback)

        val text = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            addView(makeText(content.applicationName, 18f, palette.primary, Typeface.BOLD).apply {
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
            addView(LinearLayout(dialog.context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                contentDescription = "已验证应用域名 ${content.applicationOrigin}"
                addView(ImageView(dialog.context).apply {
                    setImageResource(R.drawable.ic_app_menu_lock)
                    imageTintList = ColorStateList.valueOf(palette.secondary)
                    scaleType = ImageView.ScaleType.CENTER_INSIDE
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(dp(16), dp(16)).apply {
                    marginEnd = dp(5)
                })
                addView(makeText(content.applicationOrigin, 13f, palette.secondary).apply {
                    includeFontPadding = false
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    gravity = Gravity.CENTER_VERTICAL
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }, layout(top = dp(4)))
        }

        return LinearLayout(dialog.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(icon, LinearLayout.LayoutParams(iconSize, iconSize))
            addView(text, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(12)
            })
        }
    }

    private fun action(dialog: BottomSheetDialog, item: AppMenuAction): View {
        val color = if (item.destructive) palette.destructive else palette.primary
        val row = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(8), 0)
            background = AppCompatResources.getDrawable(
                dialog.context,
                android.R.drawable.list_selector_background,
            )
            isClickable = true
            isFocusable = true
            contentDescription = item.label
            tag = item.wireValue
            minimumHeight = dp(52)
        }
        row.addView(ImageView(dialog.context).apply {
            setImageResource(item.iconResource)
            imageTintList = ColorStateList.valueOf(color)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(24), dp(24)))
        row.addView(makeText(item.label, 16f, color).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(14), 0, dp(14))
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = dp(12)
        })
        row.setOnClickListener {
            dialog.dismiss()
            onAction(item)
        }
        return row.apply { layoutParams = layout() }
    }

    private fun divider(dialog: BottomSheetDialog): View = View(dialog.context).apply {
        setBackgroundColor(palette.divider)
        layoutParams = layout(height = dp(1), top = dp(4), bottom = dp(4))
    }

    private fun makeText(
        value: String,
        sizeSp: Float,
        color: Int,
        style: Int = Typeface.NORMAL,
        gravityValue: Int = Gravity.START,
    ): TextView = TextView(activity).apply {
        text = value
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextColor(color)
        setTypeface(Typeface.DEFAULT, style)
        gravity = gravityValue
    }

    private fun themeColor(): Int = runCatching {
        Color.parseColor(content.themeColor)
    }.getOrDefault(palette.iconBackground)

    private fun readableOn(background: Int): Int {
        val red = Color.red(background) / 255.0
        val green = Color.green(background) / 255.0
        val blue = Color.blue(background) / 255.0
        return if (0.299 * red + 0.587 * green + 0.114 * blue > 0.6) {
            Color.BLACK
        } else {
            Color.WHITE
        }
    }

    private fun roundedBackground(color: Int, radiusDp: Float, topOnly: Boolean = false) =
        GradientDrawable().apply {
            setColor(color)
            val radius = dp(radiusDp).toFloat()
            if (topOnly) {
                cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
            } else {
                cornerRadius = radius
            }
        }

    private fun layout(
        height: Int = LinearLayout.LayoutParams.WRAP_CONTENT,
        top: Int = 0,
        bottom: Int = 0,
    ) = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height).apply {
        topMargin = top
        bottomMargin = bottom
    }

    private fun dp(value: Int): Int =
        (value * activity.resources.displayMetrics.density).roundToInt()

    private fun dp(value: Float): Int =
        (value * activity.resources.displayMetrics.density).roundToInt()
}

private data class AppMenuPalette(
    val surface: Int,
    val primary: Int,
    val secondary: Int,
    val divider: Int,
    val iconBackground: Int,
    val destructive: Int,
)
