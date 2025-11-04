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
import okhttp3.*
import org.json.JSONObject
import java.util.Random
import javax.net.ssl.*
import java.security.cert.X509Certificate
import java.security.SecureRandom
import javax.net.ssl.SSLException

class BackgroundService : Service() {
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "skybyn_background_service"
    private val CHANNEL_NAME = "Skybyn Background Service"
    
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
    private val wsUrl = "wss://server.skybyn.no:4433"
    
    // Notification auto-hide
    private var notificationHideTask: java.util.concurrent.ScheduledFuture<*>? = null
    private val NOTIFICATION_AUTO_HIDE_DELAY_SECONDS = 5L // Hide notification after 5 seconds

    override fun onCreate() {
        super.onCreate()
        Log.d("BackgroundService", "onCreate called")
        createNotificationChannel()
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
        
        // Handle notification visibility actions
        when (intent?.action) {
            "SHOW_NOTIFICATION" -> {
                updateNotificationVisibility(true)
                return START_STICKY
            }
            "HIDE_NOTIFICATION" -> {
                updateNotificationVisibility(false)
                return START_STICKY
            }
        }
        
        if (!isRunning) {
            // Start with invisible notification
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+ requires foreground service type to be specified
                startForeground(NOTIFICATION_ID, createNotification(false), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, createNotification(false))
            }
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
        
        // Cancel any pending notification hide task
        notificationHideTask?.cancel(false)
        notificationHideTask = null
        
        stopBackgroundTasks()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Create channel with IMPORTANCE_NONE for invisible notification initially
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_NONE
            ).apply {
                description = "Keeps Skybyn running in background"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun updateNotificationChannel(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = if (show) {
                NotificationManager.IMPORTANCE_LOW
            } else {
                NotificationManager.IMPORTANCE_NONE
            }
            
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                importance
            ).apply {
                description = "Keeps Skybyn running in background"
                setShowBadge(false)
                if (show) {
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(false)
                } else {
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(false)
                }
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private var notificationVisible = false
    
    private fun createNotification(visible: Boolean = false): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Skybyn")
            .setContentText(if (visible) "Running in background" else "")
            .setSmallIcon(R.drawable.notification_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(!visible)
            .setPriority(if (visible) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_MIN)
        
        if (!visible) {
            // Make notification invisible/minimal
            builder.setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
        }
        
        return builder.build()
    }
    
    private fun updateNotificationVisibility(visible: Boolean) {
        // Only update if state actually changed
        if (notificationVisible == visible) {
            Log.d("BackgroundService", "Notification visibility unchanged: $visible")
            return
        }
        
        // Cancel any pending auto-hide task
        notificationHideTask?.cancel(false)
        notificationHideTask = null
        
        notificationVisible = visible
        updateNotificationChannel(visible)
        
        val notification = createNotification(visible)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        
        Log.d("BackgroundService", "Notification visibility updated: $visible")
        
        // If showing notification, schedule auto-hide after a few seconds
        if (visible && executor != null) {
            notificationHideTask = executor?.schedule({
                try {
                    Log.d("BackgroundService", "Auto-hiding background notification after delay")
                    updateNotificationVisibility(false)
                } catch (e: Exception) {
                    Log.e("BackgroundService", "Error auto-hiding notification: ${e.message}")
                }
            }, NOTIFICATION_AUTO_HIDE_DELAY_SECONDS, TimeUnit.SECONDS)
            
            Log.d("BackgroundService", "Scheduled notification auto-hide in $NOTIFICATION_AUTO_HIDE_DELAY_SECONDS seconds")
        }
    }

    private fun startBackgroundTasks() {
        Log.d("BackgroundService", "Starting background tasks")
        
        // Start WebSocket connection
        connectWebSocket()
        
        // Schedule periodic task to keep service alive
        executor?.scheduleAtFixedRate({
            try {
                // Check WebSocket connection health
                if (webSocket == null || reconnectAttempts >= maxReconnectAttempts) {
                    Log.d("BackgroundService", "WebSocket disconnected, attempting reconnect...")
                    connectWebSocket()
                }
            } catch (e: Exception) {
                Log.e("BackgroundService", "Error in background task: ${e.message}")
            }
        }, 0, 60, TimeUnit.SECONDS) // Run every 60 seconds
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
                    scheduleReconnect()
                }
            }
            
            webSocket = okHttpClient?.newWebSocket(request, wsListener)
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error connecting WebSocket: ${e.message}")
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
                    // Could show notification here if needed
                }
                "new_comment" -> {
                    Log.d("BackgroundService", "New comment notification received")
                    // Could show notification here if needed
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
            
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setSilent(true)
                .build()
            
            notificationManager.notify(notificationId, notification)
            Log.d("BackgroundService", "Notification shown: $title")
        } catch (e: Exception) {
            Log.e("BackgroundService", "Error showing notification: ${e.message}")
        }
    }
    
    private fun scheduleReconnect() {
        reconnectHandler?.removeCallbacks(reconnectRunnable ?: return)
        
        if (reconnectAttempts >= maxReconnectAttempts) {
            Log.w("BackgroundService", "Max reconnection attempts reached. Giving up.")
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