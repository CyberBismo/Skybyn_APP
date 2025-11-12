import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isInitialized = false;
  bool _isConnected = false;
  String? _userId;
  String? _sessionId;
  
  // Stream subscriptions
  StreamSubscription<DocumentSnapshot>? _userStatusSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notificationsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _broadcastsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _appUpdatesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatMessagesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _typingStatusSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _onlineStatusSubscription;

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
      print('ℹ️ [FirebaseRealtime] Service already initialized');
      return;
    }

    try {
      print('🔄 [FirebaseRealtime] Initializing Firebase Realtime service...');
      
      // Generate session ID
      _sessionId = _generateSessionId();
      
      _isInitialized = true;
      print('✅ [FirebaseRealtime] Service initialized');
    } catch (e) {
      print('❌ [FirebaseRealtime] Error initializing service: $e');
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
      if (kDebugMode) {
        print('✅ [FirebaseRealtime] onOnlineStatus callback registered (total: ${_onOnlineStatusCallbacks.length})');
      }
    }

    // Ensure service is initialized
    if (!_isInitialized) {
      await initialize();
    }

    if (_isConnected) {
      print('ℹ️ [FirebaseRealtime] Already connected, updating callbacks');
      return;
    }

    try {
      print('🔄 [FirebaseRealtime] Connecting to Firebase...');
      
      // Get current user
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      _userId = user?.id;
      
      if (_userId == null) {
        print('⚠️ [FirebaseRealtime] No user logged in, cannot connect');
        return;
      }

      // Note: We don't store user data in Firestore - only use it for real-time signaling
      // User data and online status are stored in your own database
      
      // Set up real-time listeners
      await _setupListeners();
      
      _isConnected = true;
      print('✅ [FirebaseRealtime] Connected to Firebase');
    } catch (e) {
      // Check if it's a Firestore database not found error
      if (e.toString().contains('does not exist') || 
          e.toString().contains('NOT_FOUND') ||
          e.toString().contains('database')) {
        print('⚠️ [FirebaseRealtime] Firestore database not available: $e');
        print('ℹ️ [FirebaseRealtime] App will continue without real-time notifications');
        print('ℹ️ [FirebaseRealtime] To enable Firestore, create a database at: https://console.cloud.google.com/datastore/setup?project=skybyn');
        _isConnected = false;
        // Don't rethrow - allow app to continue without Firestore
      } else {
        print('❌ [FirebaseRealtime] Error connecting: $e');
        _isConnected = false;
        // Don't rethrow - allow app to continue
      }
    }
  }

  /// Set up all Firestore listeners
  /// 
  /// These listeners watch for NOTIFICATIONS only, not actual data.
  /// When a notification is received, the app fetches the actual data from your REST API.
  Future<void> _setupListeners() async {
    if (_userId == null) return;

    try {
      // Listen to new post notifications
      // Your backend should write to 'post_notifications' when a post is created
      _postsSubscription = _firestore
          .collection('post_notifications')
          .where('status', isEqualTo: 'pending')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>?;
          if (data != null) {
            final postId = data['postId'] as String? ?? '';
            final postUserId = data['userId'] as String? ?? '';
            
            // Don't notify for own posts
            if (postId.isNotEmpty && postUserId != _userId) {
              // Fetch actual post data from your API
              _fetchPostFromAPI(postId);
            }
            
            // Mark notification as processed
            doc.doc.reference.update({'status': 'processed'});
          }
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in post notifications listener: $error');
      // Continue without this listener - app will still work
    });

    // Listen to user notifications (comments, etc.)
    // Your backend should write to 'notifications' when events occur
    _notificationsSubscription = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: _userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          _handleNotification(data);
          // Mark as processed
          doc.doc.reference.update({'status': 'processed'});
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in notifications listener: $error');
    });

    // Listen to broadcast notifications
    // Your backend should write to 'broadcast_notifications' when broadcasting
    _broadcastsSubscription = _firestore
        .collection('broadcast_notifications')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final message = data['message'] as String? ?? '';
          if (message.isNotEmpty) {
            _onBroadcast?.call(message);
          }
          // Mark as processed
          doc.doc.reference.update({'status': 'processed'});
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in broadcast notifications listener: $error');
    });

    // Listen to app update notifications
    // Your backend should write to 'app_update_notifications' when updates are available
    _appUpdatesSubscription = _firestore
        .collection('app_update_notifications')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _onAppUpdate?.call();
          // Mark as processed
          doc.doc.reference.update({'status': 'processed'});
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in app update notifications listener: $error');
    });

    // Chat messages, typing status, and online status are set up per chat/user in screens
    } catch (e) {
      print('⚠️ [FirebaseRealtime] Firestore database not available: $e');
      print('ℹ️ [FirebaseRealtime] App will continue without real-time notifications');
      print('ℹ️ [FirebaseRealtime] To enable Firestore, create a database at: https://console.cloud.google.com/datastore/setup?project=skybyn');
      // Continue without Firestore - app will still work
    }
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
  /// Note: This receives full message text directly from Firestore
  /// Backend writes chat message notifications to Firestore when messages are sent
  void setupChatListener(String friendId, Function(String, String, String, String) onMessage) {
    if (_userId == null) return;

    _chatMessagesSubscription?.cancel();
    
    // Listen to chat message notifications
    // Backend writes full message text to Firestore for real-time delivery
    _chatMessagesSubscription = _firestore
        .collection('chat_message_notifications')
        .where('toUserId', isEqualTo: _userId)
        .where('fromUserId', isEqualTo: friendId)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final messageId = data['messageId'] as String? ?? doc.doc.id;
          final fromUserId = data['fromUserId'] as String? ?? '';
          final toUserId = data['toUserId'] as String? ?? '';
          // Get full message text directly from Firestore (no need to fetch from API)
          final message = data['message'] as String? ?? '';
          
          if (message.isNotEmpty) {
            // Use message text directly from Firestore
            onMessage(messageId, fromUserId, toUserId, message);
          } else {
            // Fallback: if message text is missing, fetch from API
            print('⚠️ [FirebaseRealtime] Message text missing in Firestore, fetching from API');
            _fetchMessageFromAPI(messageId, fromUserId, toUserId, onMessage);
          }
          
          // Mark notification as processed
          doc.doc.reference.update({'status': 'processed'});
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in chat message notifications listener: $error');
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
      print('❌ [FirebaseRealtime] Error fetching post from API: $e');
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
      print('❌ [FirebaseRealtime] Error fetching message from API: $e');
    }
  }

  /// Set up typing status listener for a specific chat
  void setupTypingStatusListener(String friendId, Function(String, bool) onTyping) {
    if (_userId == null) return;

    _typingStatusSubscription?.cancel();
    
    _typingStatusSubscription = _firestore
        .collection('typing_status')
        .where('chatId', isEqualTo: '${_userId}_$friendId')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        final data = doc.doc.data() as Map<String, dynamic>;
        final userId = data['userId'] as String? ?? '';
        final isTyping = data['isTyping'] as bool? ?? false;
        
        if (userId != _userId) {
          onTyping(userId, isTyping);
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in typing status listener: $error');
    });
  }

  /// Set up online status listener for a specific user
  /// Note: This listens to a notification collection, not user data
  /// Your backend should write online status notifications to Firestore when status changes
  /// Returns a StreamSubscription that can be cancelled
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> setupOnlineStatusListener(
    String userId,
    Function(String, bool) onStatusChange,
  ) {
    // Listen to online_status_notifications collection for this user
    // Your backend should write notifications here when a user's online status changes
    return _firestore
        .collection('online_status_notifications')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>?;
          if (data != null) {
            final isOnline = data['isOnline'] == true || 
                            data['isOnline'] == 1 ||
                            data['isOnline'] == '1' ||
                            data['isOnline'] == 'true';
            
            onStatusChange(userId, isOnline);
            
            // Mark notification as processed
            doc.doc.reference.update({'status': 'processed'});
          }
        }
      }
    }, onError: (error) {
      print('⚠️ [FirebaseRealtime] Error in online status listener: $error');
    });
  }

  /// Send typing status
  Future<void> sendTypingStart(String targetUserId) async {
    if (_userId == null) return;
    
    await _firestore.collection('typing_status').doc('${_userId}_$targetUserId').set({
      'userId': _userId,
      'targetUserId': targetUserId,
      'isTyping': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Send typing stop
  Future<void> sendTypingStop(String targetUserId) async {
    if (_userId == null) return;
    
    await _firestore.collection('typing_status').doc('${_userId}_$targetUserId').set({
      'userId': _userId,
      'targetUserId': targetUserId,
      'isTyping': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Note: User data (online status, activity) is stored in your own database, not Firestore
  // Firestore is only used for ephemeral real-time signaling (typing status, call signals)

  /// Disconnect and clean up
  Future<void> disconnect() async {
    if (!_isConnected) return;

    print('🔄 [FirebaseRealtime] Disconnecting...');
    
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
    print('✅ [FirebaseRealtime] Disconnected');
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

