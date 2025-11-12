import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/post.dart';
import 'auth_service.dart';

/// Firebase-based real-time service that replaces WebSocket for all communication
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

      // Ensure user document exists in Firestore (create if doesn't exist)
      await _ensureUserDocument();
      
      // Update user status to online
      await _updateUserStatus(true);
      
      // Set up real-time listeners
      await _setupListeners();
      
      _isConnected = true;
      print('✅ [FirebaseRealtime] Connected to Firebase');
    } catch (e) {
      print('❌ [FirebaseRealtime] Error connecting: $e');
      _isConnected = false;
      rethrow;
    }
  }

  /// Set up all Firestore listeners
  Future<void> _setupListeners() async {
    if (_userId == null) return;

    // Listen to new posts
    _postsSubscription = _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        if (data['userId'] != _userId) { // Don't notify for own posts
          try {
            final post = Post.fromJson({...data, 'id': doc.id});
            _onNewPost?.call(post);
          } catch (e) {
            print('❌ [FirebaseRealtime] Error parsing post: $e');
          }
        }
      }
    });

    // Listen to notifications
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
        }
      }
    });

    // Listen to broadcasts
    _broadcastsSubscription = _firestore
        .collection('broadcasts')
        .where('status', isEqualTo: 'sending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final message = data['message'] as String? ?? '';
          _onBroadcast?.call(message);
        }
      }
    });

    // Listen to app updates
    _appUpdatesSubscription = _firestore
        .collection('app_updates')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          _onAppUpdate?.call();
        }
      }
    });

    // Listen to chat messages (set up per chat in ChatScreen)
    // Listen to typing status (set up per chat in ChatScreen)
    // Listen to online status (set up per user in screens)
  }

  /// Handle notification from Firestore
  void _handleNotification(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    
    switch (type) {
      case 'new_post':
        final postId = data['payload']?['postId'] as String? ?? '';
        if (postId.isNotEmpty) {
          // Fetch post details and call onNewPost
          _firestore.collection('posts').doc(postId).get().then((doc) {
            if (doc.exists) {
              try {
                final post = Post.fromJson({...doc.data()!, 'id': doc.id});
                _onNewPost?.call(post);
              } catch (e) {
                print('❌ [FirebaseRealtime] Error parsing post from notification: $e');
              }
            }
          });
        }
        break;
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
    }
  }

  /// Set up chat message listener for a specific chat
  void setupChatListener(String friendId, Function(String, String, String, String) onMessage) {
    if (_userId == null) return;

    _chatMessagesSubscription?.cancel();
    
    // Listen to messages between current user and friend
    _chatMessagesSubscription = _firestore
        .collection('chat_messages')
        .where('fromUserId', whereIn: [_userId, friendId])
        .where('toUserId', whereIn: [_userId, friendId])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final fromUserId = data['fromUserId'] as String? ?? '';
          final toUserId = data['toUserId'] as String? ?? '';
          final message = data['message'] as String? ?? '';
          final messageId = doc.doc.id;
          
          // Only notify if message is for current user
          if (toUserId == _userId) {
            onMessage(messageId, fromUserId, toUserId, message);
          }
        }
      }
    });
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
    });
  }

  /// Set up online status listener for a specific user
  void setupOnlineStatusListener(String userId, Function(String, bool) onStatusChange) {
    _onlineStatusSubscription?.cancel();
    
    _onlineStatusSubscription = _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final lastActive = data['last_active'] as int? ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final twoMinutesAgo = now - 120;
        final isOnline = lastActive >= twoMinutesAgo;
        
        onStatusChange(userId, isOnline);
      }
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

  /// Update user online status in Firestore
  Future<void> updateUserStatus(bool isOnline) async {
    if (_userId == null) return;
    
    try {
      await _firestore.collection('users').doc(_userId).update({
        'online': isOnline ? 1 : 0,
        'last_active': FieldValue.serverTimestamp(),
        'sessionId': _sessionId,
      });
      if (kDebugMode) {
        print('✅ [FirebaseRealtime] Updated user status in Firestore: online=$isOnline');
      }
    } catch (e) {
      print('❌ [FirebaseRealtime] Error updating user status in Firestore: $e');
    }
  }

  /// Update user activity (last_active timestamp) in Firestore
  Future<void> updateActivity() async {
    if (_userId == null) return;
    
    try {
      await _firestore.collection('users').doc(_userId).update({
        'last_active': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [FirebaseRealtime] Error updating activity in Firestore: $e');
      }
    }
  }

  /// Ensure user document exists in Firestore
  Future<void> _ensureUserDocument() async {
    if (_userId == null) return;
    
    try {
      final userDoc = _firestore.collection('users').doc(_userId);
      final doc = await userDoc.get();
      
      if (!doc.exists) {
        // Create user document if it doesn't exist
        await userDoc.set({
          'userId': _userId,
          'online': 0,
          'last_active': FieldValue.serverTimestamp(),
          'sessionId': _sessionId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (kDebugMode) {
          print('✅ [FirebaseRealtime] Created user document in Firestore');
        }
      }
    } catch (e) {
      print('❌ [FirebaseRealtime] Error ensuring user document: $e');
    }
  }

  /// Internal method for updating user status (used during connect/disconnect)
  Future<void> _updateUserStatus(bool isOnline) async {
    await updateUserStatus(isOnline);
  }

  /// Disconnect and clean up
  Future<void> disconnect() async {
    if (!_isConnected) return;

    print('🔄 [FirebaseRealtime] Disconnecting...');
    
    // Update user status to offline
    await _updateUserStatus(false);
    
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

