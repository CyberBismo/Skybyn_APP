package no.skybyn.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL

class BubbleApiPlugin(private val context: Context) {

    companion object {
        private const val CHANNEL_ID = "skybyn_bubbles_v2"
        private const val CHANNEL_NAME = "Skybyn Chat Bubbles"
    }

    fun showBubble(
        friendId: String,
        friendName: String,
        friendAvatar: String,
        unreadCount: Int,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(false)
            return
        }

        val nm = context.getSystemService(NotificationManager::class.java)

        // Log bubble eligibility for debugging
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            android.util.Log.d("BubbleApi", "areBubblesEnabled=${nm.areBubblesEnabled()}")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            android.util.Log.d("BubbleApi", "bubblePreference=${nm.bubblePreference} (0=none,1=selected,2=all)")
        }

        Thread {
            try {
                ensureChannel()

                val avatarBitmap: Bitmap? = if (friendAvatar.isNotEmpty()) {
                    try {
                        val conn = URL(friendAvatar).openConnection() as HttpURLConnection
                        conn.connectTimeout = 4000
                        conn.readTimeout = 4000
                        conn.connect()
                        BitmapFactory.decodeStream(conn.inputStream)?.let { makeCircular(it) }
                    } catch (_: Exception) { null }
                } else null

                val icon = if (avatarBitmap != null)
                    IconCompat.createWithAdaptiveBitmap(avatarBitmap)
                else
                    IconCompat.createWithResource(context, R.drawable.logo)

                val person = Person.Builder()
                    .setName(friendName)
                    .setIcon(icon)
                    .setImportant(true)
                    .build()

                // Dynamic shortcut — required for bubbles on Android 12+
                val shortcutIntent = Intent(context, BubbleChatActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    putExtra("friend_id", friendId)
                    putExtra("friend_name", friendName)
                    putExtra("friend_avatar", friendAvatar)
                }
                val shortcut = ShortcutInfoCompat.Builder(context, friendId)
                    .setIntent(shortcutIntent)
                    .setLongLived(true)
                    .setIcon(icon)
                    .setShortLabel(friendName)
                    .setPerson(person)
                    .build()
                ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)

                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0

                val bubbleIntent = PendingIntent.getActivity(
                    context,
                    friendId.hashCode(),
                    Intent(context, BubbleChatActivity::class.java).apply {
                        putExtra("friend_id", friendId)
                        putExtra("friend_name", friendName)
                        putExtra("friend_avatar", friendAvatar)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                    },
                    flags,
                )

                val bubbleMetadata = NotificationCompat.BubbleMetadata.Builder(bubbleIntent, icon)
                    .setDesiredHeight(700)
                    .setAutoExpandBubble(false)
                    .setSuppressNotification(true)
                    .build()

                val bodyText = if (unreadCount > 0)
                    "$unreadCount unread message${if (unreadCount > 1) "s" else ""}"
                else "New message"

                val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                    .setContentTitle(friendName)
                    .setContentText(bodyText)
                    .setSmallIcon(R.drawable.logo)
                    .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                    .addPerson(person)
                    .setShortcutId(friendId)
                    .setBubbleMetadata(bubbleMetadata)
                    .setAutoCancel(false)
                    .build()

                android.util.Log.d("BubbleApi", "Posting bubble notification for $friendName (id=${friendId.hashCode()})")
                NotificationManagerCompat.from(context).notify(friendId.hashCode(), notification)
                android.util.Log.d("BubbleApi", "Bubble notification posted successfully")
                result.success(true)
            } catch (e: Exception) {
                android.util.Log.e("BubbleApi", "Error posting bubble: ${e.message}", e)
                result.error("ERROR", e.message, null)
            }
        }.start()
    }

    fun dismissBubble(friendId: String) {
        NotificationManagerCompat.from(context).cancel(friendId.hashCode())
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(NotificationManager::class.java)
            // Delete old channel so setAllowBubbles takes effect on recreate
            nm.deleteNotificationChannel("skybyn_bubbles")
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setAllowBubbles(true)
                }
            }
            nm.createNotificationChannel(channel)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val created = nm.getNotificationChannel(CHANNEL_ID)
                android.util.Log.d("BubbleApi", "Channel canBubble=${created?.canBubble()} importance=${created?.importance}")
            }
        }
    }

    private fun makeCircular(src: Bitmap): Bitmap {
        val size = minOf(src.width, src.height)
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, Rect(0, 0, src.width, src.height), Rect(0, 0, size, size), paint)
        return out
    }
}
