package no.skybyn.app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import java.net.HttpURLConnection
import java.net.URL

class NativeOverlayManager(private val context: Context) {

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: ImageView? = null
    private var dismissZoneView: TextView? = null
    private var currentFriendId: String = ""
    private var currentFriendName: String = ""
    private var currentAvatarUrl: String = ""
    private var sessionToken: String = ""
    private var userId: String = ""
    private var floatingChat: NativeFloatingChatOverlay? = null

    fun isPermissionGranted(): Boolean = Settings.canDrawOverlays(context)

    @SuppressLint("ClickableViewAccessibility")
    fun show(friendId: String, friendName: String, avatarUrl: String, token: String = "", uid: String = "") {
        sessionToken = token
        userId = uid
        currentFriendName = friendName
        currentAvatarUrl = avatarUrl
        if (!isPermissionGranted()) return
        remove()

        currentFriendId = friendId
        val sizePx = dpToPx(72)

        val params = WindowManager.LayoutParams(
            sizePx, sizePx,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSPARENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dpToPx(16)
            y = dpToPx(200)
        }

        val imageView = ImageView(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }

        var downRawX = 0f
        var downRawY = 0f
        var initParamX = 0
        var initParamY = 0
        var dragged = false

        val screenW = context.resources.displayMetrics.widthPixels
        val screenH = context.resources.displayMetrics.heightPixels
        // Dismiss zone: bottom-center, last 20% of screen height
        val dismissZoneTop = (screenH * 0.80).toInt()
        val dismissZoneCenterX = screenW / 2
        val dismissZoneRadius = dpToPx(56)

        imageView.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    initParamX = params.x
                    initParamY = params.y
                    dragged = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!dragged && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                        dragged = true
                        showDismissZone()
                    }
                    if (dragged) {
                        params.x = (initParamX - dx).toInt().coerceAtLeast(0)
                        params.y = (initParamY + dy).toInt().coerceAtLeast(0)
                        try { windowManager.updateViewLayout(imageView, params) } catch (_: Exception) {}
                        // Highlight dismiss zone when bubble is near it
                        val nearDismiss = event.rawY > dismissZoneTop &&
                            Math.abs(event.rawX - dismissZoneCenterX) < dismissZoneRadius
                        dismissZoneView?.alpha = if (nearDismiss) 1f else 0.6f
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    hideDismissZone()
                    if (!dragged) {
                        openFloatingChat()
                    } else {
                        // Use bubble's actual screen-center position, not raw finger coords.
                        // With Gravity.TOP|END: bubbleCenterX = screenW - params.x - sizePx/2
                        //                       bubbleCenterY = params.y + sizePx/2
                        val bubbleCenterX = screenW - params.x - sizePx / 2
                        val bubbleCenterY = params.y + sizePx / 2
                        val nearDismiss = bubbleCenterY > dismissZoneTop &&
                            Math.abs(bubbleCenterX - dismissZoneCenterX) < dismissZoneRadius
                        if (nearDismiss) {
                            // Post to handler — removing a view from inside its own touch
                            // listener can be dropped on some OEMs if done synchronously
                            Handler(Looper.getMainLooper()).post { remove() }
                        }
                    }
                    true
                }
                else -> false
            }
        }

        overlayView = imageView
        try {
            windowManager.addView(imageView, params)
            android.util.Log.d("NativeOverlay", "addView success for $friendName")
        } catch (e: Exception) {
            android.util.Log.e("NativeOverlay", "addView FAILED: ${e.javaClass.simpleName}: ${e.message}")
            overlayView = null
            return
        }

        Thread {
            val bitmap = loadCircularBitmap(avatarUrl, friendName, sizePx)
            Handler(Looper.getMainLooper()).post {
                try { imageView.setImageBitmap(bitmap) } catch (_: Exception) {}
            }
        }.start()
    }

    private fun openFloatingChat() {
        floatingChat?.dismiss()
        floatingChat = NativeFloatingChatOverlay(
            context = context,
            windowManager = windowManager,
            friendId = currentFriendId,
            friendName = currentFriendName,
            avatarUrl = currentAvatarUrl,
            sessionToken = sessionToken,
            userId = userId,
            onClose = { floatingChat = null },
        )
        floatingChat?.show()
    }

    private fun showDismissZone() {
        if (dismissZoneView != null) return
        val zoneSizePx = dpToPx(72)
        val tv = TextView(context).apply {
            text = "✕"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = android.view.Gravity.CENTER
            alpha = 0.6f
            val bg = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(0xCC333333.toInt())
            }
            background = bg
        }
        val zoneParams = WindowManager.LayoutParams(
            zoneSizePx, zoneSizePx,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSPARENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dpToPx(40)
        }
        dismissZoneView = tv
        try { windowManager.addView(tv, zoneParams) } catch (_: Exception) { dismissZoneView = null }
    }

    private fun hideDismissZone() {
        dismissZoneView?.let { try { windowManager.removeView(it) } catch (_: Exception) {} }
        dismissZoneView = null
    }

    fun remove() {
        if (overlayView != null || floatingChat != null) {
            android.util.Log.d("NativeOverlay", "remove() called — bubble=${overlayView != null} chat=${floatingChat != null}")
        }
        hideDismissZone()
        floatingChat?.dismiss()
        floatingChat = null
        overlayView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
        }
        overlayView = null
    }

    fun isShowing(): Boolean = overlayView != null

    private fun loadCircularBitmap(url: String, fallbackName: String, sizePx: Int): Bitmap {
        val source = if (url.isNotEmpty()) {
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.connectTimeout = 4000
                conn.readTimeout = 4000
                conn.connect()
                BitmapFactory.decodeStream(conn.inputStream)
            } catch (_: Exception) { null }
        } else null

        return if (source != null) makeCircularFromBitmap(source, sizePx)
        else makeInitialsBitmap(fallbackName, sizePx)
    }

    private fun makeCircularFromBitmap(src: Bitmap, sizePx: Int): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val scaled = Bitmap.createScaledBitmap(src, sizePx, sizePx, true)
        canvas.drawBitmap(scaled, 0f, 0f, paint)
        paint.xfermode = null
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dpToPx(2).toFloat()
        paint.color = 0x401565C0.toInt()
        canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f - dpToPx(1), paint)
        return out
    }

    private fun makeInitialsBitmap(name: String, sizePx: Int): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(
            0f, 0f, sizePx.toFloat(), sizePx.toFloat(),
            intArrayOf(0xFF1565C0.toInt(), 0xFF42A5F5.toInt()),
            null, Shader.TileMode.CLAMP
        )
        canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f, paint)
        paint.shader = null
        paint.color = Color.WHITE
        paint.textSize = sizePx * 0.38f
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.DEFAULT_BOLD
        val letter = if (name.isNotEmpty()) name[0].uppercaseChar().toString() else "?"
        val metrics = paint.fontMetrics
        val y = sizePx / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(letter, sizePx / 2f, y, paint)
        return out
    }

    private fun dpToPx(dp: Int): Int =
        (dp * context.resources.displayMetrics.density + 0.5f).toInt()
}
