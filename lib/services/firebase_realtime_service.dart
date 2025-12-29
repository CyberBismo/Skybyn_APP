// Firestore disabled - using WebSocket for real-time features instead
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import '../models/post.dart';
import 'auth_service.dart';
import '../config/constants.dart';

/// Firebase-based real-time service for communication/signaling only
/// 
/// IMPORTANT: This service uses Firestore ONLY for real-time notifications/signaling.
/// All actual data is stored in your own database and accessed via REST APIs.
/// 
/// Architecture:
/// 1. Your backend stores data in your database
/// 2. Your backend writes minimal notifications to Firestore
/// 3. App receives Firestore notifications in real-time
/// 4. App fetches actual data from your REST API
/// 5. App updates UI with data from your API
class FirebaseRealtimeService {
  static final FirebaseRealtimeService _instance = FirebaseRealtimeService._internal();
  factory FirebaseRealtimeService() => _instance;
  FirebaseRealtimeService._internal();

  // Firestore disabled - using WebSocket for real-time features instead
  // final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  bool _isInitialized = false;
  bool _isConnected = false;
  String? _userId;
  String? _sessionId;
  
  // Stream subscriptions (Firestore disabled - these are not used)
  StreamSubscription<dynamic>? _userStatusSubscription;
  StreamSubscription<dynamic>? _postsSubscription;
  StreamSubscription<dynamic>? _notificationsSubscription;
  StreamSubscription<dynamic>? _broadcastsSubscription;
  StreamSubscription<dynamic>? _appUpdatesSubscription;
  StreamSubscription<dynamic>? _chatMessagesSubscription;
  StreamSubscription<dynamic>? _typingStatusSubscription;
  StreamSubscription<dynamic>? _onlineStatusSubscription;

  // Callbacks for real-time updates
  Function(Post)? _onNewPost;
  Function(String, String)? _onNewComment; // postId, commentId
  Function(String)? _onDeletePost;
  Function(String, String)? _onDeleteComment; // postId, commentId
  Function(String)? _onBroadcast; // broadcast message
  Function()? _onAppUpdate; // app update notification
  Function(String, String, String, String)? _onChatMessage; // messageId, fromUserId, toUserId, message
  Function(String, bool)? _onTypingStatus; // userId, isTyping
  final List<Function(String, bool)> _onOnlineStatusCallbacks = []; // Multiple listeners for online status

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  /// Initialize the Firebase Realtime Service
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // Generate session ID
      _sessionId = _generateSessionId();
      
      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }

  /// Connect to Firebase and set up real-time listeners
  Future<void> connect({
    Function(Post)? onNewPost,
    Function(String, String)? onNewComment,
    Function(String)? onDeletePost,
    Function(String, String)? onDeleteComment,
    Function(String)? onBroadcast,
    Function()? onAppUpdate,
    Function(String, String, String, String)? onChatMessage,
    Function(String, bool)? onTypingStatus,
    Function(String, bool)? onOnlineStatus,
  }) async {
    // Store callbacks
    if (onNewPost != null) _onNewPost = onNewPost;
    if (onNewComment != null) _onNewComment = onNewComment;
    if (onDeletePost != null) _onDeletePost = onDeletePost;
    if (onDeleteComment != null) _onDeleteComment = onDeleteComment;
    if (onBroadcast != null) _onBroadcast = onBroadcast;
    if (onAppUpdate != null) _onAppUpdate = onAppUpdate;
    if (onChatMessage != null) _onChatMessage = onChatMessage;
    if (onTypingStatus != null) _onTypingStatus = onTypingStatus;
    if (onOnlineStatus != null) {
      _onOnlineStatusCallbacks.add(onOnlineStatus);
    }

    // Ensure service is initialized
    if (!_isInitialized) {
      await initialize();
    }

    if (_isConnected) {
      return;
    }

    try {
      // Get current user
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      _userId = user?.id;
      
      if (_userId == null) {
        return;
      }

      // Firestore disabled - using WebSocket for real-time features instead
      // Set up real-time listeners
      // await _setupListeners(); // Disabled - using WebSocket instead
      
      _isConnected = false; // Mark as not connected since Firestore is disabled
    } catch (e) {
      // Check if it's a Firestore database not found error
      if (e.toString().contains('does not exist') || 
          e.toString().contains('NOT_FOUND') ||
          e.toString().contains('database')) {
        _isConnected = false;
        // Don't rethrow - allow app to continue without Firestore
      } else {
        _isConnected = false;
        // Don't rethrow - allow app to continue
      }
    }
  }

  /// Set up all Firestore listeners
  /// 
  /// DISABLED: Firestore is not used - WebSocket is used for real-time features instead
  /// This method is kept for compatibility but does nothing.
  Future<void> _setupListeners() async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
    
    /* DISABLED - Firestore not used
    // ... (original commented out code)
    */ 
  }

  /// Handle notification from Firestore
  /// Note: Notifications contain IDs/references, not full data
  /// The app fetches actual data from your REST API
  void _handleNotification(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    
    switch (type) {
      case 'new_comment':
        final postId = data['payload']?['postId'] as String? ?? '';
        final commentId = data['payload']?['commentId'] as String? ?? '';
        if (postId.isNotEmpty && commentId.isNotEmpty) {
          _onNewComment?.call(postId, commentId);
        }
        break;
      case 'delete_post':
        final postId = data['payload']?['postId'] as String? ?? '';
        if (postId.isNotEmpty) {
          _onDeletePost?.call(postId);
        }
        break;
      case 'delete_comment':
        final postId = data['payload']?['postId'] as String? ?? '';
        final commentId = data['payload']?['commentId'] as String? ?? '';
        if (postId.isNotEmpty && commentId.isNotEmpty) {
          _onDeleteComment?.call(postId, commentId);
        }
        break;
      // Note: new_post is handled in _setupListeners via _fetchPostFromAPI
    }
  }

  /// Set up chat message listener for a specific chat
  /// WebSocket is the primary method for real-time chat delivery
  /// This listener acts as a fallback when WebSocket is unavailable
  void setupChatListener(String friendId, Function(String, String, String, String) onMessage) {
    if (_userId == null) return;

    _chatMessagesSubscription?.cancel();
    
    // Listen to chat_notifications/{myUserId}
    // This node receives messages sent via sendChatMessageNotification when WebSocket fails
    final DatabaseReference notificationsRef = _database.ref()
        .child('chat_notifications')
        .child(_userId!);
        
    // Create query
    Query query = notificationsRef.orderByChild('timestamp');
    
    // If friendId is provided, we could filter client-side since RTDB doesn't support multiple query clauses easily
    // But for now, we'll listen to all and filter in the callback
    
    _chatMessagesSubscription = query.onChildAdded.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        final messageId = data['messageId']?.toString() ?? event.snapshot.key ?? '';
        final fromUserId = data['fromUserId']?.toString() ?? '';
        final toUserId = data['toUserId']?.toString() ?? '';
        final message = data['message']?.toString() ?? '';
        final type = data['type']?.toString() ?? '';
        
        // Filter by friendId if needed
        if (friendId.isNotEmpty && fromUserId != friendId) {
          return;
        }
        
        // Only process chat messages
        if (type == 'chat' || type.isEmpty) { // Handle legacy/missing type
             if (message.isNotEmpty) {
               onMessage(messageId, fromUserId, toUserId, message);
               
               // Remove notification after processing to prevent duplicates
               // and keep the node clean
               event.snapshot.ref.remove(); 
             }
        }
      }
    }, onError: (error) {
      print('[SKYBYN] ⚠️ [Firebase] Chat listener error: $error');
    });
  }

  /// Fetch post data from your API when notification is received
  Future<void> _fetchPostFromAPI(String postId) async {
    try {
      // Fetch post from your REST API
      final response = await http.post(
        Uri.parse(ApiConstants.getPost),
        body: {'postID': postId, 'userID': _userId},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        String responseBody = response.body;
        
        // Handle HTML warnings mixed with JSON
        if (responseBody.trim().startsWith('<')) {
          final jsonMatch = RegExp(r'\[.*\]$', dotAll: true).firstMatch(responseBody);
          if (jsonMatch != null) {
            responseBody = jsonMatch.group(0)!;
          }
        }
        
        final List<dynamic> data = json.decode(responseBody);
        if (data.isNotEmpty && data.first['responseCode'] == '1') {
          final postMap = data.first as Map<String, dynamic>;
          final post = Post.fromJson(postMap);
          _onNewPost?.call(post);
        }
      }
    } catch (e) {
    }
  }

  /// Fetch message data from your API when notification is received
  Future<void> _fetchMessageFromAPI(
    String messageId,
    String fromUserId,
    String toUserId,
    Function(String, String, String, String) onMessage,
  ) async {
    try {
      // Fetch message from your REST API
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/chat/get.php'),
        body: {'messageId': messageId},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' && data['message'] != null) {
          final messageData = data['message'];
          final message = messageData['message'] as String? ?? '';
          onMessage(messageId, fromUserId, toUserId, message);
        }
      }
    } catch (e) {
    }
  }

  /// Set up typing status listener for a specific chat
  /// DISABLED: Firestore is not used - WebSocket handles typing status
  void setupTypingStatusListener(String friendId, Function(String, bool) onTyping) {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
  }

  /// Set up online status listener for a specific user
  /// DISABLED: Firestore is not used - WebSocket handles online status
  /// Returns a StreamSubscription that can be cancelled (but returns a dummy subscription)
  StreamSubscription<dynamic> setupOnlineStatusListener(
    String userId,
    Function(String, bool) onStatusChange,
  ) {
    // Firestore disabled - using WebSocket for real-time features instead
    // Return a dummy subscription that does nothing
    return const Stream<dynamic>.empty().listen((_) {});
  }

  /// Send typing status
  /// DISABLED: Firestore is not used - WebSocket handles typing status
  Future<void> sendTypingStart(String targetUserId) async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
  }

  /// Send typing stop
  /// DISABLED: Firestore is not used - WebSocket handles typing status
  Future<void> sendTypingStop(String targetUserId) async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
  }

  /// Send chat message notification to Firebase
  /// This writes to Realtime Database which should trigger a push notification via Cloud Functions
  /// or simply be available for the recipient if they have an active listener.
  Future<void> sendChatMessageNotification({
    required String messageId,
    required String targetUserId,
    required String content,
  }) async {
    if (_userId == null) return;
    
    try {
      // Write to chat_notifications node in Realtime Database
      // Path: chat_notifications/{targetUserId}/{messageId}
      final DatabaseReference notificationsRef = _database.ref()
          .child('chat_notifications')
          .child(targetUserId)
          .child(messageId);
          
      await notificationsRef.set({
        'messageId': messageId,
        'fromUserId': _userId,
        'toUserId': targetUserId,
        'message': content,
        'status': 'pending',
        'timestamp': ServerValue.timestamp,
        'type': 'chat',
      });
      
      print('[SKYBYN] ✅ [Firebase] Notification written to chat_notifications/$targetUserId/$messageId');
    } catch (e) {
      print('[SKYBYN] ⚠️ [Firebase] Failed to write notification: $e');
      // Don't throw - Firebase is a fallback, HTTP API is primary
    }
  }

  // Note: User data (online status, activity) is stored in your own database, not Firestore
  // Firestore is only used for ephemeral real-time signaling (typing status, call signals)

  /// Disconnect and clean up
  Future<void> disconnect() async {
    if (!_isConnected) return;
    // Note: User status is updated in your own database, not Firestore
    
    // Cancel all subscriptions
    await _postsSubscription?.cancel();
    await _notificationsSubscription?.cancel();
    await _broadcastsSubscription?.cancel();
    await _appUpdatesSubscription?.cancel();
    await _chatMessagesSubscription?.cancel();
    await _typingStatusSubscription?.cancel();
    await _onlineStatusSubscription?.cancel();
    
    _postsSubscription = null;
    _notificationsSubscription = null;
    _broadcastsSubscription = null;
    _appUpdatesSubscription = null;
    _chatMessagesSubscription = null;
    _typingStatusSubscription = null;
    _onlineStatusSubscription = null;
    
    _isConnected = false;
  }

  /// Remove online status callback
  void removeOnlineStatusCallback(Function(String, bool) callback) {
    _onOnlineStatusCallbacks.remove(callback);
  }

  /// Generate session ID
  String _generateSessionId() {
    return DateTime.now().millisecondsSinceEpoch.toString() + 
           (1000 + (9999 - 1000) * (DateTime.now().millisecondsSinceEpoch % 1000) / 1000).toStringAsFixed(0);
  }
}
