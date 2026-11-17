package `fun`.yunle.apps.webruntime

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.color.MaterialColors
import `fun`.yunle.apps.BoundedHttpsImageLoader
import `fun`.yunle.apps.account.AccountUser

internal object NativeAuthorizationSheet {
    fun show(
        activity: Activity,
        policy: HostSsoPolicy,
        user: AccountUser,
        onConfirm: () -> Unit,
        onSwitchViaBrowser: () -> Unit,
        onCancel: () -> Unit,
    ) {
        if (activity.isFinishing || activity.isDestroyed) {
            onCancel()
            return
        }
        val dialog = BottomSheetDialog(activity)
        val density = activity.resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density).toInt()

        val surface = MaterialColors.getColor(activity, com.google.android.material.R.attr.colorSurface, Color.WHITE)
        val onSurface = MaterialColors.getColor(activity, com.google.android.material.R.attr.colorOnSurface, Color.BLACK)
        val onSurfaceVariant = MaterialColors.getColor(
            activity,
            com.google.android.material.R.attr.colorOnSurfaceVariant,
            Color.DKGRAY,
        )
        val surfaceVariant = MaterialColors.getColor(
            activity,
            com.google.android.material.R.attr.colorSurfaceVariant,
            Color.LTGRAY,
        )

        var resolved = false
        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(28))
            setBackgroundColor(surface)
        }

        val titleView = TextView(activity).apply {
            text = "${policy.applicationName} 申请使用你的云乐坊账号"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(onSurface)
        }
        val originView = TextView(activity).apply {
            text = "来源：${policy.applicationOrigin}"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(onSurfaceVariant)
            setPadding(0, dp(4), 0, dp(14))
        }
        val primaryContainer = MaterialColors.getColor(
            activity,
            com.google.android.material.R.attr.colorPrimaryContainer,
            surfaceVariant,
        )
        val onPrimaryContainer = MaterialColors.getColor(
            activity,
            com.google.android.material.R.attr.colorOnPrimaryContainer,
            onSurface,
        )
        val accountCard = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(surfaceVariant)
            }
        }
        val avatarSize = dp(44)
        val avatarContainer = FrameLayout(activity).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(primaryContainer)
            }
            outlineProvider = ViewOutlineProvider.BACKGROUND
            clipToOutline = true
        }
        val avatarFallback = TextView(activity).apply {
            text = user.displayName.take(1).ifEmpty { "云" }
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(onPrimaryContainer)
            gravity = Gravity.CENTER
        }
        val avatarImage = ImageView(activity).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
            contentDescription = "${user.displayName} 头像"
        }
        avatarContainer.addView(
            avatarFallback,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        avatarContainer.addView(
            avatarImage,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        BoundedHttpsImageLoader.load(activity, user.picture, avatarImage, avatarFallback)

        val accountDetails = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, 0, 0)
        }
        accountDetails.addView(TextView(activity).apply {
            text = "当前账号：${user.displayName}"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(onSurface)
        })
        accountDetails.addView(TextView(activity).apply {
            text = "${user.detail} · 授权内容：${policy.permissionDescription}"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(onSurfaceVariant)
            setPadding(0, dp(4), 0, 0)
        })
        accountCard.addView(avatarContainer, LinearLayout.LayoutParams(avatarSize, avatarSize))
        accountCard.addView(
            accountDetails,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )

        val confirmButton = MaterialButton(activity).apply {
            text = "以 ${user.displayName} 继续"
            minimumHeight = dp(48)
            setOnClickListener {
                if (resolved) return@setOnClickListener
                resolved = true
                dialog.dismiss()
                onConfirm()
            }
        }
        val switchButton = MaterialButton(
            activity,
            null,
            com.google.android.material.R.attr.materialButtonOutlinedStyle,
        ).apply {
            text = "使用其他账号"
            minimumHeight = dp(48)
            setOnClickListener {
                if (resolved) return@setOnClickListener
                resolved = true
                dialog.dismiss()
                onSwitchViaBrowser()
            }
        }
        val cancelButton = MaterialButton(
            activity,
            null,
            com.google.android.material.R.attr.borderlessButtonStyle,
        ).apply {
            text = "取消"
            minimumHeight = dp(48)
            setOnClickListener {
                if (resolved) return@setOnClickListener
                resolved = true
                dialog.dismiss()
                onCancel()
            }
        }

        container.addView(titleView)
        container.addView(originView)
        container.addView(
            accountCard,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(18) },
        )
        container.addView(
            confirmButton,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(8) },
        )
        container.addView(
            switchButton,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(4) },
        )
        container.addView(
            cancelButton,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER_HORIZONTAL },
        )

        dialog.setOnCancelListener {
            if (!resolved) {
                resolved = true
                onCancel()
            }
        }
        dialog.setContentView(container)
        dialog.show()
    }
}
