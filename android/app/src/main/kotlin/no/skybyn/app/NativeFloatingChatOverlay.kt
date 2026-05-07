package no.skybyn.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.*
import android.view.inputmethod.EditorInfo
import android.widget.*
import no.skybyn.app.R
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class NativeFloatingChatOverlay(
    private val context: Context,
    private val windowManager: WindowManager,
    private val friendId: String,
    private val friendName: String,
    private val avatarUrl: String,
    private val sessionToken: String,
    private val userId: String,
    private val onClose: () -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var rootView: View? = null
    private var messagesContainer: LinearLayout? = null
    private var scrollView: ScrollView? = null
    private var friendAvatarBitmap: Bitmap? = null
    private var lastMessageTimestamp: Long = 0

    private val pollHandler = Handler(Looper.getMainLooper())
    private val pollRunnable = object : Runnable {
        override fun run() {
            Thread { fetchNewMessages() }.start()
            pollHandler.postDelayed(this, 5000)
        }
    }

    // Same colours as Flutter's BackgroundGradient widget
    private val isDark get() = (context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    private val bgTop    get() = if (isDark) 0xFF243B55.toInt() else 0xFF76D4FF.toInt()
    private val bgBottom get() = if (isDark) 0xFF141E30.toInt() else 0xFF0090FF.toInt()

    // Flutter: sent = Colors.blue.withOpacity(0.8), received = Colors.white.withOpacity(0.15)
    private val sentBubbleColor     = 0xCC2196F3.toInt()
    private val receivedBubbleColor = 0x26FFFFFF

    private val density get() = context.resources.displayMetrics.density
    private fun dp(v: Int) = (v * density + 0.5f).toInt()

    // Load MaterialIcons from res/raw — raw resources are never compressed so
    // createFromFile() always succeeds after copying to the cache dir.
    private val materialIcons: Typeface by lazy {
        try {
            val cache = File(context.cacheDir, "material_icons.otf")
            if (!cache.exists() || cache.length() == 0L) {
                context.resources.openRawResource(R.raw.material_icons)
                    .use { src -> cache.outputStream().use { dst -> src.copyTo(dst) } }
            }
            val tf = Typeface.createFromFile(cache)
            android.util.Log.d("NativeOverlay", "MaterialIcons OK size=${cache.length()}")
            tf
        } catch (e: Exception) {
            android.util.Log.e("NativeOverlay", "MaterialIcons FAILED: ${e.message}")
            Typeface.DEFAULT
        }
    }

    // Exact codepoints from Flutter's Icons constants
    private val IC_CHAT_BUBBLE = ""   // U+E0CA
    private val IC_MIC_NONE   = ""   // U+E3A8
    private val IC_SEND       = ""   // U+E163
    private val IC_CLOSE      = ""   // U+E5CD
    private val IC_MORE       = ""   // U+E5D4 (more_vert)

    @SuppressLint("ClickableViewAccessibility")
    fun show() {
        val screenW = context.resources.displayMetrics.widthPixels
        val screenH = context.resources.displayMetrics.heightPixels

        val params = WindowManager.LayoutParams(
            (screenW * 0.94f).toInt(),
            (screenH * 0.88f).toInt(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(16)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }

        // Root — gradient background, rounded corners (outer: 24dp, card: 20dp)
        val outerR = dp(24).toFloat()
        val r      = dp(20).toFloat()
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(bgTop, bgBottom)
            ).apply { cornerRadii = floatArrayOf(outerR, outerR, outerR, outerR, outerR, outerR, outerR, outerR) }
            clipToOutline = true
            outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
        }

        // ── Header ──────────────────────────────────────────────────────────
        // Flutter: padding LTRB(16, 8, 16, 16), avatar radius 24,
        //          name 18sp bold, status dot + text, call(44) + more(44)
        root.addView(buildHeader())

        // ── Messages card ────────────────────────────────────────────────────
        // Flutter: Expanded > padding(l:16, r:16, b:12) > ClipRRect(r:20) >
        //   BackdropFilter(blur:10) > Container(white.10, border:white.30 1dp, r:20)
        //
        // Native approximation: white 15% over the dark gradient reads as a clearly
        // lighter blue-slate surface (≈ what the blurred gradient + white.10 produces).
        // The 1dp white.30 border gives the glass-edge feel.
        val msgsCard = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f
            ).apply { setMargins(dp(16), 0, dp(16), dp(12)) }
            background = GradientDrawable().apply {
                setColor(0x26FFFFFF)              // white 15% — matches frosted-glass visually
                setStroke(dp(1), 0x4DFFFFFF)     // white 30% border
                cornerRadius = r
            }
            clipToOutline = true
            outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
        }

        val sv = ScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            clipToPadding = false
            setPadding(dp(16), dp(16), dp(12), dp(12))
        }

        val msgContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        sv.addView(msgContainer)
        msgsCard.addView(sv)
        root.addView(msgsCard)

        scrollView = sv
        messagesContainer = msgContainer

        // ── Input bar ────────────────────────────────────────────────────────
        root.addView(buildInputRow())

        val loadingView = TextView(context).apply {
            text = "Loading…"
            setTextColor(0x99FFFFFF.toInt())
            textSize = 13f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(48)
            )
        }
        msgContainer.addView(loadingView)

        rootView = root
        try { windowManager.addView(root, params) } catch (_: Exception) { return }

        // Load avatar + messages in background
        Thread {
            friendAvatarBitmap = loadCircularBitmap(avatarUrl, friendName, dp(32))
            fetchMessages(initial = true, loadingView = loadingView)
        }.start()
        pollHandler.postDelayed(pollRunnable, 5000)

        root.setOnTouchListener { _, e ->
            if (e.action == MotionEvent.ACTION_OUTSIDE) { dismiss(); true } else false
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────

    private fun buildHeader(): LinearLayout {
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            // Flutter: EdgeInsets.fromLTRB(16, 8, 16, 16)
            setPadding(dp(16), dp(8), dp(16), dp(16))
        }

        // Avatar — CircleAvatar radius 24 (48dp)
        val avSize = dp(48)
        val avatarFrame = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(avSize, avSize)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x33FFFFFF)   // white 20%
            }
        }
        val avatarView = ImageView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        avatarFrame.addView(avatarView)
        header.addView(avatarFrame)

        // Name + status (Expanded)
        val nameCol = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
            ).apply { setMargins(dp(12), 0, dp(8), 0) }
        }
        nameCol.addView(TextView(context).apply {
            text = friendName
            setTextColor(Color.WHITE)
            textSize = 18f
            setTypeface(null, Typeface.BOLD)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        // Status row: dot + text (matches Flutter's _getLastActiveStatus())
        val statusRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        statusRow.addView(View(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(8), dp(8)).apply {
                setMargins(0, 0, dp(6), 0)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF888888.toInt())   // gray = offline
            }
        })
        statusRow.addView(TextView(context).apply {
            text = "Skybyn"
            setTextColor(0xFF888888.toInt())
            textSize = 11f
        })
        nameCol.addView(statusRow)
        header.addView(nameCol)

        // Right buttons — Flutter: call(44) + SizedBox(12) + more_vert(44)
        // In overlay: close replaces more_vert; omit call (can't initiate calls from overlay)
        val btnRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        // Close button styled as Flutter's more_vert button (44×44, white 15%, border white 30%)
        val closeBtn = headerCircleBtn(IC_CLOSE)
        closeBtn.setOnClickListener { dismiss() }
        btnRow.addView(closeBtn)

        header.addView(btnRow)

        // Load avatar in background
        Thread {
            val bmp = loadCircularBitmap(avatarUrl, friendName, avSize)
            mainHandler.post { try { avatarView.setImageBitmap(bmp) } catch (_: Exception) {} }
        }.start()

        return header
    }

    // 44×44 circle button — same style as Flutter's call/more_vert header buttons
    // white 15% bg + white 30% 1dp border
    private fun headerCircleBtn(codepoint: String): FrameLayout =
        FrameLayout(context).apply {
            val size = dp(44)
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x26FFFFFF)
                setStroke(dp(1), 0x4DFFFFFF)
            }
            addView(iconText(codepoint, 20f))
        }

    // ── Input bar ─────────────────────────────────────────────────────────────
    // Flutter: padding(left:16, right:16, bottom:16)
    //   ClipRRect(r25) > BackdropFilter(blur10) >
    //   Container(white.15, border:white.30 1.5dp, r:25) > Row [
    //     Padding(left:4) > Container(40×40 circle white.20) > chat_bubble 20
    //     SizedBox(8)
    //     Expanded > TextField(white 16sp, hint white.70)
    //     SizedBox(8)
    //     Container(40×40 circle white.15) > mic_none 20   ← white.15
    //     SizedBox(8)
    //     Padding(right:4) > Container(40×40 circle white.20) > attach_file 20
    //   ]

    private fun buildInputRow(): FrameLayout {
        var etRef: EditText? = null

        val wrapper = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(16), dp(4), dp(16), dp(16))
        }

        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            background = GradientDrawable().apply {
                setColor(0x26FFFFFF)             // white 15%
                setStroke(dp(2), 0x4DFFFFFF)    // white 30%
                cornerRadius = dp(25).toFloat()
            }
            setPadding(0, dp(4), 0, dp(4))
        }

        val btnSize = dp(40)

        // chat_bubble — white 20%, left padding 4dp
        val chatBtn = iconCircleBtn(IC_CHAT_BUBBLE, 20f, btnSize, 0x33FFFFFF)
        (chatBtn.layoutParams as LinearLayout.LayoutParams).setMargins(dp(4), 0, 0, 0)
        row.addView(chatBtn)

        row.addView(hSpace(8))

        // Text field
        val et = EditText(context).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            hint = "Type your message…"
            setHintTextColor(0xB3FFFFFF.toInt())   // white 70%
            setTextColor(Color.WHITE)
            textSize = 16f
            background = null
            maxLines = 4
            isSingleLine = false
            setPadding(0, 0, 0, 0)
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, id, _ ->
                if (id == EditorInfo.IME_ACTION_SEND) { sendFrom(this); true } else false
            }
        }
        etRef = et
        row.addView(et)

        row.addView(hSpace(8))

        // mic_none — white 15%
        row.addView(iconCircleBtn(IC_MIC_NONE, 20f, btnSize, 0x26FFFFFF))

        row.addView(hSpace(8))

        // send/attach — white 20%, right padding 4dp
        val sendBtn = iconCircleBtn(IC_SEND, 20f, btnSize, 0x33FFFFFF)
        (sendBtn.layoutParams as LinearLayout.LayoutParams).setMargins(0, 0, dp(4), 0)
        sendBtn.setOnClickListener { etRef?.let { sendFrom(it) } }
        row.addView(sendBtn)

        wrapper.addView(row)
        return wrapper
    }

    private fun sendFrom(et: EditText) {
        val text = et.text?.toString()?.trim() ?: ""
        if (text.isNotEmpty()) {
            et.setText("")
            addOptimisticMessage(text)
            Thread { sendMessage(text) }.start()
        }
    }

    // ── Message bubbles ───────────────────────────────────────────────────────

    private fun addOptimisticMessage(content: String) {
        addMessageBubble(content, fromMe = true, timestamp = System.currentTimeMillis() / 1000)
    }

    @SuppressLint("SetTextI18n")
    private fun addMessageBubble(content: String, fromMe: Boolean, timestamp: Long) {
        val container = messagesContainer ?: return
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = if (fromMe) Gravity.END else Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, 0, 0, dp(12)) }
        }

        if (!fromMe) {
            val avSize = dp(32)
            row.addView(ImageView(context).apply {
                layoutParams = LinearLayout.LayoutParams(avSize, avSize).apply {
                    setMargins(0, 0, dp(8), 0); gravity = Gravity.BOTTOM
                }
                scaleType = ImageView.ScaleType.CENTER_CROP
                setImageBitmap(friendAvatarBitmap ?: makeInitials(friendName, avSize))
            })
        }

        val maxBubW = (context.resources.displayMetrics.widthPixels * 0.72f).toInt()

        // Corner radii — Flutter: tl:18, tr:18, bl: me→18/other→4, br: me→4/other→18
        val s = dp(18).toFloat()
        val c = dp(4).toFloat()
        val tl = s; val tr = s
        val bl = if (fromMe) s else c
        val br = if (fromMe) c else s

        val bubble = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            background = GradientDrawable().apply {
                setColor(if (fromMe) sentBubbleColor else receivedBubbleColor)
                cornerRadii = floatArrayOf(tl, tl, tr, tr, br, br, bl, bl)
            }
            setPadding(dp(16), dp(10), dp(16), dp(10))
        }

        bubble.addView(TextView(context).apply {
            text = content
            setTextColor(Color.WHITE)
            textSize = 15f
            maxWidth = maxBubW
        })

        // Time row — Flutter: timeAgo + check icon
        val timeRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4) }
        }
        timeRow.addView(TextView(context).apply {
            text = timeAgo(timestamp)
            setTextColor(0x99FFFFFF.toInt())   // white 60%
            textSize = 11f
        })
        if (fromMe) {
            timeRow.addView(hSpace(4))
            timeRow.addView(TextView(context).apply {
                text = "✓"; setTextColor(0x99FFFFFF.toInt()); textSize = 11f
            })
        }
        bubble.addView(timeRow)

        row.addView(bubble)
        mainHandler.post { container.addView(row); scrollToBottom() }
    }

    private fun scrollToBottom() {
        scrollView?.post { scrollView?.fullScroll(View.FOCUS_DOWN) }
    }

    // ── Network ───────────────────────────────────────────────────────────────

    private fun fetchMessages(initial: Boolean, loadingView: View? = null) {
        android.util.Log.d("NativeOverlay", "fetchMessages userId=$userId friendId=$friendId token=${sessionToken.take(8)}")
        try {
            val conn = apiConn("https://api.skybyn.no/chat/get.php")
            val body = "userID=${enc(userId)}&friendID=${enc(friendId)}&limit=40&offset=0"
            conn.outputStream.use { OutputStreamWriter(it).use { w -> w.write(body) } }
            val code = conn.responseCode
            android.util.Log.d("NativeOverlay", "fetchMessages responseCode=$code")
            if (code == 200) {
                val json = conn.inputStream.bufferedReader().readText()
                android.util.Log.d("NativeOverlay", "fetchMessages json=${json.take(200)}")
                mainHandler.post { loadingView?.let { v -> (v.parent as? ViewGroup)?.removeView(v) } }
                renderMessages(json, clearFirst = initial)
            } else {
                mainHandler.post { loadingView?.let { v -> (v.parent as? ViewGroup)?.removeView(v) } }
            }
        } catch (e: Exception) {
            android.util.Log.e("NativeOverlay", "fetchMessages error: ${e.message}")
            mainHandler.post { loadingView?.let { v -> (v.parent as? ViewGroup)?.removeView(v) } }
        }
    }

    private fun fetchNewMessages() {
        if (lastMessageTimestamp == 0L) return
        try {
            val conn = apiConn("https://api.skybyn.no/chat/get.php")
            val body = "userID=${enc(userId)}&friendID=${enc(friendId)}&limit=40&offset=0&since=$lastMessageTimestamp"
            conn.outputStream.use { OutputStreamWriter(it).use { w -> w.write(body) } }
            if (conn.responseCode == 200)
                renderMessages(conn.inputStream.bufferedReader().readText(), clearFirst = false)
        } catch (_: Exception) {}
    }

    private fun renderMessages(json: String, clearFirst: Boolean) {
        try {
            val arr = JSONArray(json)
            android.util.Log.d("NativeOverlay", "renderMessages count=${arr.length()} clearFirst=$clearFirst")
            if (clearFirst) mainHandler.post { messagesContainer?.removeAllViews() }
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val content = obj.optString("content")
                val ts = obj.optLong("date", 0L)
                val fromMe = obj.optString("from") == userId
                if (content.isNotEmpty()) {
                    if (ts > lastMessageTimestamp) lastMessageTimestamp = ts
                    addMessageBubble(content, fromMe, ts)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("NativeOverlay", "renderMessages error: ${e.message}")
        }
    }

    private fun sendMessage(content: String) {
        try {
            val conn = apiConn("https://api.skybyn.no/chat/send.php")
            val cid = "bubble_${System.currentTimeMillis()}"
            val body = "userID=${enc(userId)}&from=${enc(userId)}&to=${enc(friendId)}&message=${enc(content)}&clientMsgId=${enc(cid)}"
            conn.outputStream.use { OutputStreamWriter(it).use { w -> w.write(body) } }
            conn.responseCode
        } catch (_: Exception) {}
    }

    private fun apiConn(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"; doOutput = true
            connectTimeout = 6000; readTimeout = 6000
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Requested-With", "XMLHttpRequest")
            if (sessionToken.isNotEmpty()) setRequestProperty("Authorization", "Bearer $sessionToken")
        }

    // ── Dismiss ───────────────────────────────────────────────────────────────

    fun dismiss() {
        pollHandler.removeCallbacks(pollRunnable)
        rootView?.let { try { windowManager.removeView(it) } catch (_: Exception) {} }
        rootView = null; messagesContainer = null; scrollView = null
        onClose()
    }

    // ── UI helpers ────────────────────────────────────────────────────────────

    // Full-match Material Icon text view centered in a FrameLayout
    private fun iconText(codepoint: String, sizeSp: Float): TextView =
        TextView(context).apply {
            text = codepoint
            textSize = sizeSp
            setTextColor(Color.WHITE)
            typeface = materialIcons
            gravity = Gravity.CENTER
            includeFontPadding = false
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

    // Oval FrameLayout + icon — used in input bar
    private fun iconCircleBtn(codepoint: String, iconSp: Float, sizePx: Int, bgColor: Int): FrameLayout =
        FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(sizePx, sizePx)
            background = GradientDrawable().apply {
                setColor(bgColor); shape = GradientDrawable.OVAL
            }
            addView(iconText(codepoint, iconSp))
        }

    // Horizontal spacer
    private fun hSpace(dp: Int) = View(context).apply {
        layoutParams = LinearLayout.LayoutParams(dp(dp), ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    // ── Time formatting ───────────────────────────────────────────────────────

    private fun timeAgo(unixSeconds: Long): String {
        val diff = System.currentTimeMillis() / 1000 - unixSeconds
        return when {
            diff < 60      -> "now"
            diff < 3600    -> "${diff / 60}m"
            diff < 7200    -> "~1h"
            diff < 86400   -> "${diff / 3600}h"
            diff < 172800  -> "~1d"
            else           -> "${diff / 86400}d"
        }
    }

    // ── Bitmap helpers ────────────────────────────────────────────────────────

    private fun loadCircularBitmap(url: String, fallback: String, sizePx: Int): Bitmap {
        val src = if (url.isNotEmpty()) {
            try {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 4000; c.readTimeout = 4000; c.connect()
                BitmapFactory.decodeStream(c.inputStream)
            } catch (_: Exception) { null }
        } else null
        return if (src != null) makeCircular(src, sizePx) else makeInitials(fallback, sizePx)
    }

    private fun makeCircular(src: Bitmap, size: Int): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(Bitmap.createScaledBitmap(src, size, size, true), 0f, 0f, paint)
        return out
    }

    private fun makeInitials(name: String, size: Int): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, size.toFloat(), size.toFloat(),
            intArrayOf(0xFF1565C0.toInt(), 0xFF42A5F5.toInt()), null, Shader.TileMode.CLAMP)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.shader = null; paint.color = Color.WHITE
        paint.textSize = size * 0.38f; paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.DEFAULT_BOLD
        val letter = if (name.isNotEmpty()) name[0].uppercaseChar().toString() else "?"
        val m = paint.fontMetrics
        canvas.drawText(letter, size / 2f, size / 2f - (m.ascent + m.descent) / 2f, paint)
        return out
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
