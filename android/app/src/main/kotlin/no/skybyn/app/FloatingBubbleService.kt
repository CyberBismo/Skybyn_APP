package no.skybyn.app

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import android.util.Log
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.net.URL
import kotlinx.coroutines.*
import android.content.Context

class FloatingBubbleService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingBubbleView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    
    private var friendId: String? = null
    private var friendName: String? = null
    private var avatarUrl: String? = null
    private var unreadCount: Int = 0
    private var message: String? = null
    
    companion object {
        private const val TAG = "FloatingBubbleService"
        private const val BUBBLE_SIZE = 80
        private const val BADGE_SIZE = 24
    }
    
    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        Log.d(TAG, "FloatingBubbleService created")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "SHOW_BUBBLE" -> {
                friendId = intent.getStringExtra("friendId")
                friendName = intent.getStringExtra("friendName")
                avatarUrl = intent.getStringExtra("avatarUrl")
                unreadCount = intent.getIntExtra("unreadCount", 0)
                message = intent.getStringExtra("message")
                showBubble()
            }
            "UPDATE_BUBBLE" -> {
                friendId = intent.getStringExtra("friendId")
                friendName = intent.getStringExtra("friendName")
                avatarUrl = intent.getStringExtra("avatarUrl")
                unreadCount = intent.getIntExtra("unreadCount", 0)
                message = intent.getStringExtra("message")
                updateBubble()
            }
            "HIDE_BUBBLE" -> {
                hideBubble()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    private fun showBubble() {
        if (floatingBubbleView != null) {
            // Already showing, just update
            updateBubble()
            return
        }
        
        try {
            // Create bubble view
            floatingBubbleView = createBubbleView()
            
            // Set up window parameters
            bubbleParams = WindowManager.LayoutParams().apply {
                width = BUBBLE_SIZE
                height = BUBBLE_SIZE
                type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }
                format = PixelFormat.TRANSLUCENT
                flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                gravity = Gravity.TOP or Gravity.START
                x = 20
                y = 200
            }
            
            // Add view to window manager
            windowManager?.addView(floatingBubbleView, bubbleParams)
            Log.d(TAG, "Bubble shown successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing bubble: ${e.message}", e)
        }
    }
    
    private fun updateBubble() {
        if (floatingBubbleView == null) {
            showBubble()
            return
        }
        
        // Update the view with new data
        floatingBubbleView?.let { view ->
            val avatarImageView = view.findViewById<ImageView>(R.id.bubble_avatar)
            val badgeTextView = view.findViewById<TextView>(R.id.bubble_badge)
            val nameTextView = view.findViewById<TextView>(R.id.bubble_name)
            val messageTextView = view.findViewById<TextView>(R.id.bubble_message)
            
            // Update avatar
            avatarUrl?.let { url ->
                if (url.isNotEmpty()) {
                    loadAvatarImage(avatarImageView, url)
                } else {
                    avatarImageView.setImageResource(R.drawable.ic_launcher_foreground)
                }
            } ?: run {
                avatarImageView.setImageResource(R.drawable.ic_launcher_foreground)
            }
            
            // Update badge
            if (unreadCount > 0) {
                badgeTextView.visibility = View.VISIBLE
                badgeTextView.text = if (unreadCount > 99) "99+" else unreadCount.toString()
            } else {
                badgeTextView.visibility = View.GONE
            }
            
            // Update name and message (for tooltip)
            nameTextView.text = friendName ?: "Friend"
            messageTextView.text = message ?: ""
        }
    }
    
    private fun createBubbleView(): View {
        // Create a simple circular view programmatically
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.floating_bubble, null)
        
        val avatarImageView = view.findViewById<ImageView>(R.id.bubble_avatar)
        val badgeTextView = view.findViewById<TextView>(R.id.bubble_badge)
        val nameTextView = view.findViewById<TextView>(R.id.bubble_name)
        val messageTextView = view.findViewById<TextView>(R.id.bubble_message)
        
        // Set up avatar
        avatarUrl?.let { url ->
            if (url.isNotEmpty()) {
                loadAvatarImage(avatarImageView, url)
            } else {
                avatarImageView.setImageResource(R.drawable.ic_launcher_foreground)
            }
        } ?: run {
            avatarImageView.setImageResource(R.drawable.ic_launcher_foreground)
        }
        
        // Set up badge
        if (unreadCount > 0) {
            badgeTextView.visibility = View.VISIBLE
            badgeTextView.text = if (unreadCount > 99) "99+" else unreadCount.toString()
        } else {
            badgeTextView.visibility = View.GONE
        }
        
        // Set up name and message
        nameTextView.text = friendName ?: "Friend"
        messageTextView.text = message ?: ""
        
        // Set up click listener
        view.setOnClickListener {
            // Open chat screen via MainActivity
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("open_chat", true)
                putExtra("friendId", friendId)
            }
            startActivity(intent)
            hideBubble()
            stopSelf()
        }
        
        // Set up drag listener
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isDragging = false
                    initialX = bubbleParams?.x ?: 0
                    initialY = bubbleParams?.y ?: 0
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - initialTouchX
                    val deltaY = event.rawY - initialTouchY
                    
                    if (Math.abs(deltaX) > 10 || Math.abs(deltaY) > 10) {
                        isDragging = true
                    }
                    
                    if (isDragging) {
                        bubbleParams?.let { params ->
                            params.x = (initialX + deltaX).toInt()
                            params.y = (initialY + deltaY).toInt()
                            
                            // Keep within screen bounds
                            val displayMetrics = resources.displayMetrics
                            params.x = params.x.coerceIn(0, displayMetrics.widthPixels - BUBBLE_SIZE)
                            params.y = params.y.coerceIn(0, displayMetrics.heightPixels - BUBBLE_SIZE)
                            
                            windowManager?.updateViewLayout(floatingBubbleView, params)
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        // Snap to nearest edge
                        bubbleParams?.let { params ->
                            val displayMetrics = resources.displayMetrics
                            val centerX = displayMetrics.widthPixels / 2
                            
                            params.x = if (params.x < centerX) {
                                10
                            } else {
                                displayMetrics.widthPixels - BUBBLE_SIZE - 10
                            }
                            
                            windowManager?.updateViewLayout(floatingBubbleView, params)
                        }
                    }
                    isDragging = false
                    !isDragging // Return false if not dragging to allow click
                }
                else -> false
            }
        }
        
        return view
    }
    
    private fun hideBubble() {
        floatingBubbleView?.let { view ->
            try {
                windowManager?.removeView(view)
                floatingBubbleView = null
                bubbleParams = null
                Log.d(TAG, "Bubble hidden successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error hiding bubble: ${e.message}", e)
            }
        }
    }
    
    private fun loadAvatarImage(imageView: ImageView, url: String) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val bitmap = BitmapFactory.decodeStream(URL(url).openConnection().getInputStream())
                withContext(Dispatchers.Main) {
                    imageView.setImageBitmap(bitmap)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error loading avatar: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    imageView.setImageResource(R.drawable.ic_launcher_foreground)
                }
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        hideBubble()
        Log.d(TAG, "FloatingBubbleService destroyed")
    }
}

