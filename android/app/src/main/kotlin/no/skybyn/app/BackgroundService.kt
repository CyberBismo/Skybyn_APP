package no.skybyn.app

import android.app.*
import android.content.Intent
import android.content.SharedPreferences
import android.os.IBinder
import android.os.Build
import androidx.core.app.NotificationCompat
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.Context
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import android.os.Handler
import android.os.Looper
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import okhttp3.*
import org.json.JSONObject
import java.util.Random
import javax.net.ssl.*
import java.security.cert.X509Certificate
import java.security.SecureRandom
import javax.net.ssl.SSLException
import no.skybyn.app.BuildConfig

class BackgroundService : Service() {
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "skybyn_background_service"
    private val CHANNEL_NAME = "Skybyn Background Service"
    private val ADMIN_CHANNEL_ID = "admin_notifications"
    private val ADMIN_CHANNEL_NAME = "Admin Notifications"
    
    private var executor: ScheduledExecutorService? = null
    private var isRunning = false
    
    // WebSocket
    private var webSocket: WebSocket? = null
    private var okHttpClient: OkHttpClient? = null
    private var reconnectHandler: Handler? = null
    private var reconnectRunnable: Runnable? = null
    private var reconnectAttempts = 0
    private val maxReconnectAttempts = 10
    private var sessionId: String? = null
    // Use port 4432 for debug builds, 4433 for release builds
    private val wsUrl = if (BuildConfig.DEBUG) "wss://server.skybyn.no:4432" else "wss://server.skybyn.no:4433"
    
    // Connection state tracking
    private var isConnected = false
    private var hasShownDisconnectNotification = false
    private val CONNECTION_LOST_NOTIFICATION_ID = 1002

    override fun onCreate() {
        super.onCreate()
        Log.d("BackgroundService", "onCreate called")
        createNotificationChannel() // Create invisible channel for foreground service
        createAdminNotificationChannel() // Create admin channel for actual notifications
        executor = Executors.newScheduledThreadPool(2) // Increased for WebSocket thread
        reconnectHandler = Handler(Looper.getMainLooper())
        
        // Initialize OkHttp client for WebSocket with SSL certificate trust
        Log.d("BackgroundService", "Creating OkHttpClient before onCreate returns")
        okHttpClient = createUnsafeOkHttpClient()
        Log.d("BackgroundService", "OkHttpClient created: ${okHttpClient != null}")
    }
    
    // Create OkHttpClient that trusts all SSL certificates (matching Flutter behavior)
    private fun createUnsafeOkHttpClient(): OkHttpClient {
        try {
            Log.d("BackgroundService", "Creating OkHttpClient with SSL trust-all configuration")
            
            // Create a trust manager that accepts all certificates
            val trustAllCerts = arrayOf<TrustManager>(
                object : X509TrustManager {
                    override fun checkClientTrusted(
                        chain: Array<out X509Certificate>?,
                        authType: String?
                    ) {
                        Log.d("BackgroundService", "Trusting client certificate")
                        // Trust all client certificates
                    }
                    
                    override fun checkServerTrusted(
                        chain: Array<out X509Certificate>?,
                        authType: String?
                    ) {
                        Log.d("BackgroundService", "Trusting server certificate")
                        // Trust all server certificates
                    }
                    
                    override fun getAcceptedIssuers(): Array<X509Certificate> {
                        return emptyArray()
                    }
                }
            )
            
            // Install the all-trusting trust manager
            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, trustAllCerts, SecureRandom())
            
            // Create an ssl socket factory with our all-trusting manager
            val sslSocketFactory = sslContext.socketFactory
            val trustManager = trustAllCerts[0] as X509TrustManager
            
            Log.d("BackgroundService", "SSL context initialized, creating OkHttpClient")
            
            val client = OkHttpClient.Builder()
                .sslSocketFactory(sslSocketFactory, trustManager)
                .hostnameVerifier(HostnameVerifier { _, _ -> 
                    Log.d("BackgroundService", "Hostname verification: trusting all hostnames")
                    true 
                })
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS)
                .build()
            
            Log.d("BackgroundService", "OkHttpClient created successfully with SSL trust-all")
            return client
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error creating unsafe OkHttpClient: ${e.message}", e)
            e.printStackTrace()
            // Fallback to default client if SSL setup fails
            Log.w("BackgroundService", "Falling back to default OkHttpClient (SSL validation enabled)")
            return OkHttpClient.Builder()
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS)
                .build()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("BackgroundService", "Service started")
        
        if (!isRunning) {
            // Start as foreground service (required for long-running services on Android 8.0+)
            // Notification uses IMPORTANCE_NONE channel so it won't appear in notification tray
            val notification = createNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            
            // Keep service as foreground - notification uses IMPORTANCE_NONE so it should be invisible
            // Don't call stopForeground() as it removes foreground status and service gets killed
            
            startBackgroundTasks()
            isRunning = true
        }
        
        return START_STICKY // Restart service if killed
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("BackgroundService", "Service destroyed")
        stopBackgroundTasks()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Delete existing channel if it exists to ensure clean state
            try {
                notificationManager.deleteNotificationChannel(CHANNEL_ID)
            } catch (e: Exception) {
                // Channel doesn't exist, that's fine
            }
            
            // Create channel with IMPORTANCE_LOW to show in background activity list
            // IMPORTANCE_LOW allows the notification to appear in background activity
            // but doesn't make sound or vibrate
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Skybyn running in background for WebSocket communication"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(false)
            }
            
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create notification for foreground service
        // This notification will appear in background activity list
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon) // Use app notification icon
            .setContentTitle("Skybyn")
            .setContentText("")
            .setContentIntent(pendingIntent)
            .setSilent(true) // No sound
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setOngoing(false) // Auto-hide it
            .setAutoCancel(true) // Auto-cancel
            .setShowWhen(false) // Don't show timestamp
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun createAdminNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ADMIN_CHANNEL_ID,
                ADMIN_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Important system notifications from administrators"
                setShowBadge(true)
                enableVibration(true)
                enableLights(true)
                lightColor = android.graphics.Color.parseColor("#2196F3")
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun startBackgroundTasks() {
        Log.d("BackgroundService", "Starting background tasks")
        
        // Start WebSocket connection
        connectWebSocket()
        
        // Schedule periodic task to keep service alive and perform background checks
        executor?.scheduleAtFixedRate({
            try {
                // Check WebSocket connection health
                if (webSocket == null || reconnectAttempts >= maxReconnectAttempts) {
                    Log.d("BackgroundService", "WebSocket disconnected, attempting reconnect...")
                    connectWebSocket()
                }
                
                // Perform background checks
                performBackgroundChecks()
            } catch (e: Exception) {
                Log.e("BackgroundService", "Error in background task: ${e.message}")
            }
        }, 0, 60, TimeUnit.SECONDS) // Run every 60 seconds
    }
    
    /// Perform background checks (activity updates, connection health, etc.)
    private fun performBackgroundChecks() {
        try {
            // Check internet connectivity
            val hasInternet = isInternetAvailable()
            if (!hasInternet) {
                Log.d("BackgroundService", "No internet connection available")
                return
            }
            
            // WebSocket connection health is already checked above
            // Additional background checks can be added here:
            // - Check for app updates
            // - Sync pending messages
            // - Update user activity status
            // - Check for new notifications
            
            Log.d("BackgroundService", "Background checks completed")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error performing background checks: ${e.message}")
        }
    }
    
    private fun connectWebSocket() {
        try {
            // Ensure OkHttpClient is initialized (recreate if null)
            if (okHttpClient == null) {
                Log.w("BackgroundService", "OkHttpClient is null, recreating...")
                okHttpClient = createUnsafeOkHttpClient()
            }
            
            // Flutter SharedPreferences uses "FlutterSharedPreferences" file with "flutter." prefix
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // Keys are stored with "flutter." prefix by shared_preferences package
            val userId = prefs.getString("flutter.user_id", null) ?: prefs.getString("user_id", null)
            val username = prefs.getString("flutter.username", null) ?: prefs.getString("username", null)
            
            if (userId == null || username == null) {
                Log.w("BackgroundService", "Cannot connect WebSocket: User not logged in")
                return
            }
            
            // Generate session ID if not exists
            if (sessionId == null) {
                sessionId = generateSessionId()
            }
            
            Log.d("BackgroundService", "Connecting to WebSocket: $wsUrl")
            Log.d("BackgroundService", "Using OkHttpClient: ${okHttpClient != null}")
            
            if (okHttpClient == null) {
                Log.e("BackgroundService", "OkHttpClient is null after recreation! Cannot connect WebSocket.")
                return
            }
            
            val request = Request.Builder()
                .url(wsUrl)
                .build()
            
            val wsListener = object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    Log.d("BackgroundService", "WebSocket connected")
                    this@BackgroundService.webSocket = webSocket
                    reconnectAttempts = 0
                    
                    // Connection restored - show notification if we had shown disconnect notification
                    if (hasShownDisconnectNotification) {
                        showConnectionRestoredNotification()
                        hasShownDisconnectNotification = false
                    }
                    isConnected = true
                    
                    // Send connect message
                    sendConnectMessage(webSocket, userId, username)
                }
                
                override fun onMessage(webSocket: WebSocket, text: String) {
                    Log.d("BackgroundService", "WebSocket message received: $text")
                    handleWebSocketMessage(text)
                }
                
                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    Log.d("BackgroundService", "WebSocket closing: $code - $reason")
                    webSocket.close(1000, null)
                }
                
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    Log.d("BackgroundService", "WebSocket closed: $code - $reason")
                    this@BackgroundService.webSocket = null
                    isConnected = false
                    checkAndShowConnectionLostNotification()
                    scheduleReconnect()
                }
                
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Log.e("BackgroundService", "WebSocket failure: ${t.message}")
                    Log.e("BackgroundService", "WebSocket failure type: ${t.javaClass.name}")
                    if (t is SSLException || t.cause is SSLException) {
                        Log.e("BackgroundService", "SSL Exception detected! SSL trust configuration may not be working.")
                        t.printStackTrace()
                    }
                    this@BackgroundService.webSocket = null
                    isConnected = false
                    checkAndShowConnectionLostNotification()
                    scheduleReconnect()
                }
            }
            
            webSocket = okHttpClient?.newWebSocket(request, wsListener)
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error connecting WebSocket: ${e.message}")
            isConnected = false
            checkAndShowConnectionLostNotification()
            scheduleReconnect()
        }
    }
    
    private fun sendConnectMessage(ws: WebSocket, userId: String, username: String) {
        try {
            val connectMessage = JSONObject().apply {
                put("type", "connect")
                put("sessionId", sessionId ?: generateSessionId())
                put("userId", userId)
                put("userName", username)
                put("deviceInfo", JSONObject().apply {
                    put("device", "Android Background Service")
                    put("browser", "Skybyn App")
                })
            }
            
            val message = connectMessage.toString()
            ws.send(message)
            Log.d("BackgroundService", "Connect message sent")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error sending connect message: ${e.message}")
        }
    }
    
    private fun handleWebSocketMessage(text: String) {
        try {
            val message = JSONObject(text)
            val type = message.optString("type")
            
            when (type) {
                "app_update" -> {
                    // Skip app update notifications in debug mode
                    if (BuildConfig.DEBUG) {
                        Log.d("BackgroundService", "App update notification ignored in debug mode")
                        return
                    }
                    Log.d("BackgroundService", "App update received via WebSocket")
                    showNotification("App Update Available", "A new version of Skybyn is ready to download", "app_update")
                }
                "broadcast" -> {
                    val broadcastMessage = message.optString("message", "Broadcast message")
                    Log.d("BackgroundService", "Broadcast received: $broadcastMessage")
                    showNotification("Broadcast", broadcastMessage, "broadcast")
                }
                "new_post" -> {
                    Log.d("BackgroundService", "New post notification received")
                    val postId = message.optString("id", "")
                    if (postId.isNotEmpty()) {
                        showNotification("New Post", "Someone posted something new", "new_post")
                    }
                }
                "new_comment" -> {
                    Log.d("BackgroundService", "New comment notification received")
                    val commentId = message.optString("cid", "")
                    if (commentId.isNotEmpty()) {
                        showNotification("New Comment", "Someone commented on a post", "new_comment")
                    }
                }
                "chat" -> {
                    // Handle chat messages in background
                    val fromUserId = message.optString("from", "")
                    val messageContent = message.optString("message", "")
                    if (fromUserId.isNotEmpty() && messageContent.isNotEmpty()) {
                        Log.d("BackgroundService", "Chat message received in background from user: $fromUserId")
                        // Show notification for chat messages
                        showNotification("New Message", messageContent.take(50), "chat")
                    }
                }
                "notification" -> {
                    // Handle generic notifications
                    val title = message.optString("title", "Notification")
                    val body = message.optString("message", message.optString("body", ""))
                    if (body.isNotEmpty()) {
                        showNotification(title, body, "notification")
                    }
                }
                "ping" -> {
                    Log.d("BackgroundService", "Ping received, sending pong")
                    sendPong()
                }
                "pong" -> {
                    Log.d("BackgroundService", "Pong received")
                    // Pong response received, nothing to do
                }
                else -> {
                    Log.d("BackgroundService", "Unknown message type: $type")
                }
            }
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error handling WebSocket message: ${e.message}")
        }
    }
    
    private fun sendPong() {
        try {
            val pongMessage = JSONObject().apply {
                put("type", "pong")
                put("sessionId", sessionId ?: generateSessionId())
            }
            
            val message = pongMessage.toString()
            webSocket?.send(message)
            Log.d("BackgroundService", "Pong sent")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error sending pong: ${e.message}")
        }
    }
    
    private fun checkAndShowConnectionLostNotification() {
        // Only show notification once per disconnection
        if (hasShownDisconnectNotification) {
            return
        }
        
        // Check if internet is available
        val hasInternet = isInternetAvailable()
        
        if (!hasInternet) {
            // No internet connection
            showConnectionLostNotification("No Internet Connection", "Please check your internet connection and try again.")
        } else {
            // Internet available but WebSocket connection lost
            showConnectionLostNotification("Connection Lost", "Unable to connect to Skybyn server. Reconnecting...")
        }
        
        hasShownDisconnectNotification = true
    }
    
    private fun showConnectionLostNotification(title: String, message: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, ADMIN_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setSilent(false)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)
                .setOngoing(false)
                .build()
            
            notificationManager.notify(CONNECTION_LOST_NOTIFICATION_ID, notification)
            Log.d("BackgroundService", "Connection lost notification shown: $title")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error showing connection lost notification: ${e.message}")
        }
    }
    
    private fun showConnectionRestoredNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, ADMIN_CHANNEL_ID)
                .setContentTitle("Connection Restored")
                .setContentText("Skybyn is now connected")
                .setSmallIcon(R.drawable.notification_icon)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setSilent(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(false)
                .build()
            
            notificationManager.notify(CONNECTION_LOST_NOTIFICATION_ID + 1, notification)
            Log.d("BackgroundService", "Connection restored notification shown")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error showing connection restored notification: ${e.message}")
        }
    }
    
    private fun isInternetAvailable(): Boolean {
        return try {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = connectivityManager.activeNetwork ?: return false
                val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            } else {
                @Suppress("DEPRECATION")
                val networkInfo = connectivityManager.activeNetworkInfo
                networkInfo?.isConnected == true
            }
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error checking internet connectivity: ${e.message}")
            false
        }
    }
    
    private fun showNotification(title: String, body: String, messageType: String = "websocket") {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notificationId = System.currentTimeMillis().toInt()
            
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("notification_type", messageType)
                putExtra("websocket_message_type", messageType)
            }
            
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Use admin channel for all notifications
            val channelId = ADMIN_CHANNEL_ID
            val isSilent = messageType != "app_update"
            val priority = if (messageType == "app_update") {
                NotificationCompat.PRIORITY_HIGH
            } else {
                NotificationCompat.PRIORITY_HIGH
            }
            
            val notification = NotificationCompat.Builder(this, channelId)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(priority)
                .setSilent(isSilent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(if (messageType == "app_update") NotificationCompat.DEFAULT_ALL else 0)
                .build()
            
            notificationManager.notify(notificationId, notification)
            Log.d("BackgroundService", "Notification shown: $title (channel: $channelId, silent: $isSilent)")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error showing notification: ${e.message}")
        }
    }
    
    private fun scheduleReconnect() {
        reconnectHandler?.removeCallbacks(reconnectRunnable ?: return)
        
        if (reconnectAttempts >= maxReconnectAttempts) {
            Log.w("BackgroundService", "Max reconnection attempts reached. Giving up.")
            checkAndShowConnectionLostNotification()
            return
        }
        
        reconnectAttempts++
        val delay = minOf(1000L * (1 shl reconnectAttempts), 30000L) // Exponential backoff, max 30s
        
        reconnectRunnable = Runnable {
            Log.d("BackgroundService", "Attempting WebSocket reconnect (attempt $reconnectAttempts)")
            connectWebSocket()
        }
        
        reconnectHandler?.postDelayed(reconnectRunnable!!, delay)
        Log.d("BackgroundService", "Scheduled reconnect in ${delay}ms")
    }
    
    private fun generateSessionId(): String {
        val chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        val random = Random()
        return (1..32).map { chars[random.nextInt(chars.length)] }.joinToString("")
    }

    private fun stopBackgroundTasks() {
        Log.d("BackgroundService", "Stopping background tasks")
        
        // Close WebSocket connection
        webSocket?.close(1000, "Service stopping")
        webSocket = null
        reconnectHandler?.removeCallbacks(reconnectRunnable ?: return)
        reconnectRunnable = null
        
        executor?.let {
            it.shutdownNow()
            try {
                if (!it.awaitTermination(5, TimeUnit.SECONDS)) {
                    Log.w("BackgroundService", "Executor did not terminate gracefully")
                }
            } catch (e: InterruptedException) {
                it.shutdownNow()
                Thread.currentThread().interrupt()
            }
        }
        executor = null
        isRunning = false
    }
} 