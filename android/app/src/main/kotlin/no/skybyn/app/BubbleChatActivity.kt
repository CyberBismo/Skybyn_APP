package no.skybyn.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class BubbleChatActivity : FlutterActivity() {

    companion object {
        var pendingFriendId: String = ""
        var pendingFriendName: String = ""
        var pendingFriendAvatar: String = ""
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        pendingFriendId = intent.getStringExtra("friend_id") ?: ""
        pendingFriendName = intent.getStringExtra("friend_name") ?: ""
        pendingFriendAvatar = intent.getStringExtra("friend_avatar") ?: ""
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no.skybyn.app/bubble_chat")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBubbleData" -> result.success(
                        mapOf(
                            "friendId" to pendingFriendId,
                            "friendName" to pendingFriendName,
                            "friendAvatar" to pendingFriendAvatar,
                        )
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
