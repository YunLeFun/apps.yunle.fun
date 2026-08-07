package `fun`.yunle.apps

import android.app.Activity
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.drawable.DrawableCompat
import androidx.core.widget.NestedScrollView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlin.math.roundToInt

internal data class AuthorizationSheetContent(
    val applicationName: String,
    val applicationOrigin: String,
    val applicationIconUrl: String?,
    val accountName: String,
    val accountAvatarUrl: String?,
    val permissionDescription: String,
    val authorizationNotice: String?,
)

internal enum class AuthorizationSheetChoice(val wireValue: String) {
    CURRENT("current"),
    OTHER("other"),
    CANCEL("cancel"),
}

/** Trusted native authorization surface shared semantically with the iOS Sheet. */
internal class AuthorizationConsentSheet(
    private val activity: Activity,
    private val content: AuthorizationSheetContent,
    private val onChoice: (AuthorizationSheetChoice) -> Unit,
) {
    private val isDark = activity.resources.configuration.uiMode and
        Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private val brandColor = Color.parseColor("#B3261E")
    private val accentColor = Color.parseColor(if (isDark) "#FFB4AB" else "#B3261E")
    private val surfaceColor = Color.parseColor(if (isDark) "#201A18" else "#FFF8F6")
    private val primaryTextColor = Color.parseColor(if (isDark) "#F5EEEB" else "#1D1B20")
    private val secondaryTextColor = Color.parseColor(if (isDark) "#D2C4C0" else "#625B71")
    private val dividerColor = Color.parseColor(if (isDark) "#514441" else "#E7E0DC")
    private val permissionColor = Color.parseColor(if (isDark) "#3A211F" else "#FBE9E7")
    private val noticeColor = Color.parseColor(if (isDark) "#3A2A16" else "#FFF3D6")
    private val dialog = BottomSheetDialog(activity, R.style.AppAuthorizationBottomSheetDialog)
    private var completed = false

    fun show() {
        dialog.setContentView(buildLayout())
        dialog.setCanceledOnTouchOutside(true)
        dialog.setOnCancelListener { complete(AuthorizationSheetChoice.CANCEL, dismiss = false) }
        dialog.setOnDismissListener { complete(AuthorizationSheetChoice.CANCEL, dismiss = false) }
        dialog.show()
        dialog.behavior.apply {
            state = BottomSheetBehavior.STATE_EXPANDED
            skipCollapsed = true
            isDraggable = true
        }
    }

    private fun buildLayout(): View {
        val screenHeight = activity.resources.displayMetrics.heightPixels
        val sheetHeight = minOf((screenHeight * 0.88).roundToInt(), dp(720))
        val root = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBackground(surfaceColor, 28f, topOnly = true)
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, sheetHeight)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        root.addView(View(dialog.context).apply {
            background = roundedBackground(dividerColor, 3f)
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(5)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(10)
                bottomMargin = dp(8)
            }
            contentDescription = "拖动以关闭授权面板"
        })

        val scroll = NestedScrollView(dialog.context).apply {
            isFillViewport = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
        }
        val contentStack = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(10), dp(20), dp(24))
        }
        contentStack.addView(makeIdentityConnection())
        contentStack.addView(makeText(
            "登录到 ${content.applicationName}",
            24f,
            primaryTextColor,
            Typeface.BOLD,
            Gravity.CENTER,
        ).apply {
            setPadding(0, dp(18), 0, dp(4))
        })
        contentStack.addView(makeOriginRow())
        contentStack.addView(makeInformationPanel(
            title = "将向 ${content.applicationName} 提供",
            body = content.permissionDescription,
            backgroundColor = permissionColor,
            accent = accentColor,
        ).withTopMargin(20))
        content.authorizationNotice?.let { notice ->
            contentStack.addView(makeInformationPanel(
                title = "费用说明",
                body = notice,
                backgroundColor = noticeColor,
                accent = Color.parseColor(if (isDark) "#FFB95C" else "#A85C00"),
            ).withTopMargin(12))
        }
        contentStack.addView(makeSecurityRow().withTopMargin(18))
        scroll.addView(contentStack)
        root.addView(scroll)

        root.addView(View(dialog.context).apply {
            setBackgroundColor(dividerColor)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1))
        })
        root.addView(makeActionContainer())
        return root
    }

    private fun makeIdentityConnection(): View {
        val row = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
        }
        row.addView(makeIdentityEndpoint(
            imageUrl = content.applicationIconUrl,
            fallback = content.applicationName.take(1),
            title = content.applicationName,
            subtitle = "申请登录",
            circular = false,
        ), weightedParams())

        val verifiedIcon = ImageView(dialog.context).apply {
            setImageResource(android.R.drawable.ic_lock_lock)
            imageTintList = ColorStateList.valueOf(accentColor)
            contentDescription = "云乐坊认证连接"
            layoutParams = LinearLayout.LayoutParams(dp(28), dp(28)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        val verified = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(verifiedIcon)
            addView(makeText("云乐坊认证", 12f, accentColor, Typeface.BOLD, Gravity.CENTER).apply {
                setPadding(0, dp(5), 0, 0)
            })
        }
        row.addView(verified, weightedParams())
        row.addView(makeIdentityEndpoint(
            imageUrl = content.accountAvatarUrl,
            fallback = content.accountName.take(1),
            title = content.accountName,
            subtitle = "当前账号",
            circular = true,
        ), weightedParams())
        return row
    }

    private fun makeIdentityEndpoint(
        imageUrl: String?,
        fallback: String,
        title: String,
        subtitle: String,
        circular: Boolean,
    ): View {
        val size = dp(56)
        val radius = if (circular) 28f else 14f
        val fallbackView = makeText(
            fallback,
            22f,
            accentColor,
            Typeface.BOLD,
            Gravity.CENTER,
        )
        val imageView = ImageView(dialog.context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
            contentDescription = "$title 图标"
        }
        val imageContainer = FrameLayout(dialog.context).apply {
            background = roundedBackground(
                if (isDark) Color.parseColor("#442522") else Color.parseColor("#F9DEDC"),
                radius,
            )
            clipToOutline = true
            addView(fallbackView, FrameLayout.LayoutParams(size, size))
            addView(imageView, FrameLayout.LayoutParams(size, size))
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        loadHttpsImage(imageUrl, imageView, fallbackView)

        return LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            contentDescription = "$subtitle，$title"
            addView(imageContainer)
            addView(makeText(title, 13f, primaryTextColor, Typeface.BOLD, Gravity.CENTER).apply {
                maxLines = 2
                setPadding(0, dp(5), 0, 0)
            })
            addView(makeText(subtitle, 12f, secondaryTextColor, Typeface.NORMAL, Gravity.CENTER))
        }
    }

    private fun makeOriginRow(): View {
        val lock = DrawableCompat.wrap(
            activity.getDrawable(android.R.drawable.ic_lock_lock)!!.mutate(),
        )
        DrawableCompat.setTint(lock, secondaryTextColor)
        return makeText(
            content.applicationOrigin,
            13f,
            secondaryTextColor,
            Typeface.NORMAL,
            Gravity.CENTER,
        ).apply {
            setCompoundDrawablesWithIntrinsicBounds(lock, null, null, null)
            compoundDrawablePadding = dp(6)
            contentDescription = "已验证应用域名 ${content.applicationOrigin}"
        }
    }

    private fun makeInformationPanel(
        title: String,
        body: String,
        backgroundColor: Int,
        accent: Int,
    ): View {
        val text = LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(14), dp(16), dp(14))
            addView(makeText(title, 14f, primaryTextColor, Typeface.BOLD, Gravity.START))
            addView(makeText(body, 16f, primaryTextColor, Typeface.NORMAL, Gravity.START).apply {
                setPadding(0, dp(5), 0, 0)
            })
        }
        return LinearLayout(dialog.context).apply {
            orientation = LinearLayout.HORIZONTAL
            background = roundedBackground(backgroundColor, 16f)
            addView(View(dialog.context).apply {
                setBackgroundColor(accent)
            }, LinearLayout.LayoutParams(dp(4), ViewGroup.LayoutParams.MATCH_PARENT))
            addView(text, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
    }

    private fun makeSecurityRow(): View {
        val lock = ImageView(dialog.context).apply {
            setImageResource(android.R.drawable.ic_lock_lock)
            imageTintList = ColorStateList.valueOf(secondaryTextColor)
            contentDescription = null
        }
        return LinearLayout(dialog.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            addView(lock, LinearLayout.LayoutParams(dp(20), dp(20)).apply {
                marginEnd = dp(10)
            })
            addView(makeText(
                "不会共享你的密码或云乐坊长期登录凭证。",
                13f,
                secondaryTextColor,
                Typeface.NORMAL,
                Gravity.START,
            ), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
    }

    private fun makeActionContainer(): View {
        val primary = makeButton("以「${shortAccountName()}」登录").apply {
            backgroundTintList = ColorStateList.valueOf(brandColor)
            setTextColor(Color.WHITE)
            contentDescription = "以 ${content.accountName} 登录"
            id = View.generateViewId()
            tag = "authorization-current-account"
            setOnClickListener { complete(AuthorizationSheetChoice.CURRENT) }
        }
        val other = makeButton("使用其他账号").apply {
            backgroundTintList = ColorStateList.valueOf(surfaceColor)
            setTextColor(accentColor)
            strokeColor = ColorStateList.valueOf(accentColor)
            strokeWidth = dp(1)
            tag = "authorization-other-account"
            setOnClickListener { complete(AuthorizationSheetChoice.OTHER) }
        }
        val cancel = makeButton("取消").apply {
            backgroundTintList = ColorStateList.valueOf(Color.TRANSPARENT)
            setTextColor(secondaryTextColor)
            tag = "authorization-cancel"
            setOnClickListener { complete(AuthorizationSheetChoice.CANCEL) }
        }
        return LinearLayout(dialog.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(8))
            addView(primary, actionParams())
            addView(other, actionParams(topMargin = 8))
            addView(cancel, actionParams(topMargin = 4))
        }
    }

    private fun makeButton(title: String): MaterialButton = MaterialButton(
        dialog.context,
        null,
        com.google.android.material.R.attr.materialButtonOutlinedStyle,
    ).apply {
        text = title
        isAllCaps = false
        textSize = 16f
        typeface = Typeface.DEFAULT_BOLD
        cornerRadius = dp(14)
        insetTop = 0
        insetBottom = 0
        minimumHeight = 0
    }

    private fun makeText(
        value: String,
        sizeSp: Float,
        color: Int,
        style: Int,
        gravityValue: Int,
    ): TextView = TextView(dialog.context).apply {
        text = value
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextColor(color)
        setTypeface(Typeface.DEFAULT, style)
        gravity = gravityValue
    }

    private fun loadHttpsImage(source: String?, imageView: ImageView, fallback: View) {
        val safeSource = source ?: return
        val uri = Uri.parse(safeSource)
        if (uri.scheme?.lowercase() != "https" || uri.host.isNullOrBlank()) return
        Thread {
            val bitmap = runCatching {
                val connection = URL(safeSource).openConnection() as HttpsURLConnection
                try {
                    connection.connectTimeout = 4_000
                    connection.readTimeout = 4_000
                    connection.instanceFollowRedirects = false
                    connection.connect()
                    if (connection.responseCode !in 200..299) return@runCatching null
                    if (!connection.contentType.orEmpty().startsWith("image/")) return@runCatching null
                    val bytes = connection.inputStream.use {
                        readBounded(it, MAXIMUM_IMAGE_BYTES)
                    } ?: return@runCatching null
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                } finally {
                    connection.disconnect()
                }
            }.getOrNull() ?: return@Thread
            activity.runOnUiThread {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    imageView.setImageBitmap(bitmap)
                    imageView.visibility = View.VISIBLE
                    fallback.visibility = View.GONE
                }
            }
        }.start()
    }

    private fun readBounded(stream: InputStream, maximumBytes: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            if (total > maximumBytes) return null
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun complete(choice: AuthorizationSheetChoice, dismiss: Boolean = true) {
        if (completed) return
        completed = true
        onChoice(choice)
        if (dismiss) dialog.dismiss()
    }

    private fun shortAccountName(): String = if (content.accountName.length > 20) {
        content.accountName.take(19) + "…"
    } else {
        content.accountName
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

    private fun View.withTopMargin(valueDp: Int): View = apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(valueDp) }
    }

    private fun weightedParams() = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

    private fun actionParams(topMargin: Int = 0) = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        dp(52),
    ).apply { this.topMargin = dp(topMargin) }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).roundToInt()

    private fun dp(value: Float): Int = (value * activity.resources.displayMetrics.density).roundToInt()

    private companion object {
        const val MAXIMUM_IMAGE_BYTES = 2_000_000
    }
}
