import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../widgets/header.dart';
import '../widgets/background_gradient.dart';
import '../widgets/global_search_overlay.dart';
import '../models/friend.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/firebase_realtime_service.dart';
import '../services/websocket_service.dart';
// Firestore disabled - using WebSocket for real-time features instead
// import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'profile_screen.dart';
import 'call_screen.dart';
import '../config/constants.dart';
import '../config/constants.dart' show UrlHelper;
import '../widgets/chat_list_modal.dart';
import '../widgets/app_colors.dart';
import '../services/chat_message_count_service.dart';

class ChatScreen extends StatefulWidget {
  final Friend friend;

  const ChatScreen({
    super.key,
    required this.friend,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final FirebaseRealtimeService _firebaseRealtimeService = FirebaseRealtimeService();
  final WebSocketService _webSocketService = WebSocketService();
  final ChatMessageCountService _chatMessageCountService = ChatMessageCountService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _isSending = false;
  String? _currentUserId;
  int? _userRank; // Store user's rank
  Timer? _onlineStatusTimer;
  bool _friendOnline = false;
  int? _friendLastActive;
  bool _isFirstOnlineStatusCheck = true; // Track if this is the first check
  bool _showSearchForm = false;
  bool _hasMoreMessages = true;
  final FocusNode _messageFocusNode = FocusNode();
  bool _isFriendTyping = false;
  Timer? _typingTimer;
  Timer? _typingStopTimer;
  Timer? _messageCheckTimer; // Periodic check for new messages
  String? _chatStatusMessage; // Message to display at top of chat box
  bool _chatStatusMessageIsError = false; // Whether the message is an error (red) or success (green)
  
  // File attachment and voice recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  double _audioLevel = 0.0; // Audio amplitude level (0.0 to 1.0)
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;
  // Store subscription for cleanup (Firestore disabled - using WebSocket instead)
  StreamSubscription<dynamic>? _onlineStatusSubscription;
  // Store WebSocket online status callback for cleanup
  void Function(String, bool)? _webSocketOnlineStatusCallback;
  // Store WebSocket chat message callback for cleanup
  void Function(String, String, String, String)? _webSocketChatMessageCallback;
  // Menu overlay
  OverlayEntry? _menuOverlayEntry;
  final GlobalKey _menuButtonKey = GlobalKey();
  // Message options overlay
  OverlayEntry? _messageOptionsOverlay;
  Message? _selectedMessage;
  // Microphone button key for positioning visualizer
  final GlobalKey _microphoneButtonKey = GlobalKey();
  // Attachment menu visibility
  bool _showAttachmentMenu = false;
  // Selected file for preview before sending
  File? _selectedFile;
  String? _selectedFileType;
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _friendOnline = widget.friend.online; // Initialize with friend's current status
    _friendLastActive = widget.friend.lastActive; // Initialize with friend's last active
    // Track that this chat screen is now open
    _chatMessageCountService.setCurrentOpenChat(widget.friend.id);
    _loadUserId();
    _loadMessages();
    _setupWebSocketListener();
    _setupScrollListener();
    _setupKeyboardListener();
    _setupTypingListener();
    _setupTypingAnimation();
    _checkFriendOnlineStatus(); // Check immediately
    _startPeriodicMessageCheck(); // Start periodic message checking
    // Clear unread count when opening chat
    _chatMessageCountService.clearUnreadCount(widget.friend.id);
    // Messages are loaded once when opening chat, then WebSocket handles all updates
    // No need for periodic refresh - WebSocket provides real-time message delivery
    // Check online status every 10 seconds
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _checkFriendOnlineStatus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - resume timers
        // Messages are handled by WebSocket - no periodic refresh needed
        if (_onlineStatusTimer == null || !_onlineStatusTimer!.isActive) {
          _onlineStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
            if (mounted) {
              _checkFriendOnlineStatus();
            }
          });
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // App is in background - pause timers to prevent DNS lookup failures
        _onlineStatusTimer?.cancel();
        _onlineStatusTimer = null;
        break;
      case AppLifecycleState.detached:
        // App is being terminated - timers will be cancelled in dispose
        break;
    }
  }

  @override
  void dispose() {
    // Cancel all timers first
    _onlineStatusTimer?.cancel();
    _typingTimer?.cancel();
    _typingStopTimer?.cancel();
    _messageCheckTimer?.cancel();
    _recordingTimer?.cancel();
    
    // Dispose controllers and resources
    _typingAnimationController.dispose();
    _audioRecorder.dispose();
    _messageFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    
    // Cleanup subscriptions and listeners
    WidgetsBinding.instance.removeObserver(this);
    _amplitudeSubscription?.cancel();
    _onlineStatusSubscription?.cancel();
    
    // Clear the current open chat when leaving the screen
    if (_chatMessageCountService.currentOpenChatFriendId == widget.friend.id) {
      _chatMessageCountService.setCurrentOpenChat(null);
    }
    
    // Send typing stop when leaving screen
    if (_firebaseRealtimeService.isConnected && _currentUserId != null) {
      _firebaseRealtimeService.sendTypingStop(widget.friend.id);
    }
    
    // Remove WebSocket callbacks
    if (_webSocketOnlineStatusCallback != null) {
      _webSocketService.removeOnlineStatusCallback(_webSocketOnlineStatusCallback!);
      _webSocketOnlineStatusCallback = null;
    }
    if (_webSocketChatMessageCallback != null) {
      _webSocketService.removeChatMessageCallback(_webSocketChatMessageCallback!);
      _webSocketChatMessageCallback = null;
    }
    
    // Close overlays
    _closeMenu();
    _closeMessageOptions();
    
    super.dispose();
  }

  void _setupKeyboardListener() {
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus) {
        // When keyboard opens, scroll to bottom after a short delay
        // Use multiple delays to ensure it works even if keyboard animation is slow
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _messageFocusNode.hasFocus) {
            _scrollToBottom();
          }
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _messageFocusNode.hasFocus) {
            _scrollToBottom();
          }
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _messageFocusNode.hasFocus) {
            _scrollToBottom();
          }
        });
      }
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Check if user scrolled to the top
      if (_scrollController.position.pixels <= 100 && 
          !_isLoadingOlder && 
          _hasMoreMessages &&
          _messages.isNotEmpty) {
        _loadOlderMessages();
      }
    });
  }

  void _setupTypingAnimation() {
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _typingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _typingAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _setupTypingListener() {
    _messageController.addListener(() {
      if (!_firebaseRealtimeService.isConnected || _currentUserId == null) return;
      
      final text = _messageController.text;
      
      // Cancel existing timer
      _typingTimer?.cancel();
      
      if (text.isNotEmpty) {
        // Send typing start immediately
        _firebaseRealtimeService.sendTypingStart(widget.friend.id);
        
        // Set timer to send typing stop after 2 seconds of no typing
        _typingTimer = Timer(const Duration(seconds: 2), () {
          if (_firebaseRealtimeService.isConnected && _messageController.text.isNotEmpty) {
            // Only send stop if still typing (text hasn't been cleared)
            _firebaseRealtimeService.sendTypingStop(widget.friend.id);
          }
        });
      } else {
        // Text is empty, send typing stop
        _firebaseRealtimeService.sendTypingStop(widget.friend.id);
      }
    });
  }

  Future<void> _loadUserId() async {
    _currentUserId = await _authService.getStoredUserId();
    // Load user profile to get rank
    final user = await _authService.getStoredUserProfile();
    if (user != null && user.rank.isNotEmpty) {
      _userRank = int.tryParse(user.rank);
      if (mounted) {
        setState(() {}); // Update UI to show/hide call buttons based on rank
      }
    }
  }

  /// Start periodic message checking (fallback for when WebSocket fails)
  void _startPeriodicMessageCheck() {
    // Cancel any existing timer
    _messageCheckTimer?.cancel();
    
    // Check for new messages every 5 seconds
    _messageCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _currentUserId != null) {
        _checkForNewMessages();
      }
    });
  }

  /// Check for new messages (only fetches messages newer than the latest one we have)
  Future<void> _checkForNewMessages() async {
    if (_messages.isEmpty || _currentUserId == null) {
      return; // Can't check if we don't have messages or user ID
    }
    
    // Skip periodic check if WebSocket is connected (WebSocket handles real-time updates)
    if (_webSocketService.isConnected) {
      return; // WebSocket is handling real-time updates, no need for periodic check
    }
    
    try {
      // Get the latest message timestamp
      final latestMessage = _messages.last;
      final latestTimestamp = latestMessage.date.millisecondsSinceEpoch ~/ 1000; // Convert to seconds
      
      // Fetch messages from API (will get all messages, but we'll filter)
      final allMessages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );
      
      if (mounted) {
        // Find messages that are newer than our latest message
        final newMessages = allMessages.where((msg) {
          final msgTimestamp = msg.date.millisecondsSinceEpoch ~/ 1000;
          return msgTimestamp > latestTimestamp;
        }).toList();
        
        if (newMessages.isNotEmpty) {
          // Filter out messages that already exist (by ID) to prevent duplicates
          final existingIds = _messages.map((m) => m.id).toSet();
          final trulyNewMessages = newMessages.where((msg) => !existingIds.contains(msg.id)).toList();
          
          if (trulyNewMessages.isNotEmpty) {
            // Use the helper method to add messages safely (double-check for duplicates)
            for (final msg in trulyNewMessages) {
              _addMessageIfNotExists(msg);
            }
            // Scroll to bottom if user is at the bottom
            if (_scrollController.hasClients) {
              final isAtBottom = _scrollController.position.pixels >= 
                  _scrollController.position.maxScrollExtent - 100;
              if (isAtBottom) {
                _scrollToBottom();
              }
            }
          }
        }
      }
    } catch (e) {
      // Silently fail - don't spam errors for periodic checks
      // WebSocket should handle real-time updates, this is just a fallback
    }
  }

  Future<void> _checkFriendOnlineStatus() async {
    // Check if widget is still mounted before proceeding
    if (!mounted) return;
    
    // Store friend ID locally to avoid accessing widget after disposal
    final friendId = widget.friend.id;
    
    if (!mounted) return; // Double check after accessing widget
    
    try {
      final apiUrl = ApiConstants.profile;
      final requestParams = {'userID': friendId};
      
      // Only log the first check or if there's an error/status change
      final shouldLog = _isFirstOnlineStatusCheck;
      
      if (shouldLog) {
        print('[SKYBYN] 📤 [Chat] Checking friend online status');
        print('[SKYBYN]    URL: $apiUrl');
        print('[SKYBYN]    Parameters: ${jsonEncode(requestParams)}');
        developer.log('📤 [Chat] Checking friend online status', name: 'Chat API');
        developer.log('   URL: $apiUrl', name: 'Chat API');
        developer.log('   Parameters: ${jsonEncode(requestParams)}', name: 'Chat API');
      }
      
      final response = await http.post(
        Uri.parse(apiUrl),
        body: requestParams,
      ).timeout(const Duration(seconds: 5));

      // Check if widget is still mounted after async operation
      if (!mounted) return;

      if (shouldLog) {
        print('[SKYBYN] 📥 [Chat] Online Status API Response received');
        print('[SKYBYN]    Status Code: ${response.statusCode}');
        developer.log('📥 [Chat] Online Status API Response received', name: 'Chat API');
        developer.log('   Status Code: ${response.statusCode}', name: 'Chat API');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['responseCode'] == '1') {
          if (shouldLog) {
            print('[SKYBYN]    Response: Success');
            developer.log('   Response: Success', name: 'Chat API');
          }
          // Check last_active timestamp
          // Online: last_active <= 2 minutes
          // Away: last_active > 2 minutes (shown as offline in UI)
          final lastActiveValue = data['last_active'];
          if (shouldLog) {
            print('[SKYBYN]    Last Active (raw): $lastActiveValue');
            developer.log('   Last Active (raw): $lastActiveValue', name: 'Chat API');
          }
          int? lastActive;
          if (lastActiveValue != null) {
            if (lastActiveValue is int) {
              // If it's a large number (milliseconds), convert to seconds
              lastActive = lastActiveValue > 10000000000 
                  ? lastActiveValue ~/ 1000 
                  : lastActiveValue;
            } else if (lastActiveValue is String) {
              final parsed = int.tryParse(lastActiveValue);
              if (parsed != null) {
                lastActive = parsed > 10000000000 ? parsed ~/ 1000 : parsed;
              }
            }
          }
          
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final twoMinutesAgo = now - 120; // 2 minutes = 120 seconds
          final isOnline = lastActive != null && lastActive >= twoMinutesAgo;
          
          // Check if status changed
          final statusChanged = _friendOnline != isOnline;
          
          // Log if first check, status changed, or if logging is enabled
          if (shouldLog || statusChanged) {
            print('[SKYBYN]    Online Status: ${isOnline ? "Online" : "Offline"}${statusChanged ? " (Changed)" : ""}');
            developer.log('   Online Status: ${isOnline ? "Online" : "Offline"}${statusChanged ? " (Changed)" : ""}', name: 'Chat API');
          }

          if (mounted) {
            setState(() {
              _friendOnline = isOnline;
              _friendLastActive = lastActive;
            });
          }
          
          // Mark first check as complete
          if (_isFirstOnlineStatusCheck) {
            _isFirstOnlineStatusCheck = false;
          }
        } else {
          // Always log errors
          print('[SKYBYN]    Response: Failed - responseCode is not "1"');
          developer.log('   Response: Failed - responseCode is not "1"', name: 'Chat API');
        }
      } else {
        // Always log errors
        print('[SKYBYN]    Response: HTTP Error ${response.statusCode}');
        developer.log('   Response: HTTP Error ${response.statusCode}', name: 'Chat API');
      }
    } catch (e) {
      // Check if widget is still mounted before logging
      if (!mounted) return;
      
      // Always log errors
      print('[SKYBYN] ❌ [Chat] Error checking online status: $e');
      developer.log('❌ [Chat] Error checking online status: $e', name: 'Chat API');
      // Silently fail - don't spam errors for online status checks
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    // Log API request
    final apiUrl = ApiConstants.chatGet;
    final requestParams = {
      'friendID': widget.friend.id,
    };
    
    print('[SKYBYN] ═══════════════════════════════════════════════════════');
    print('[SKYBYN] 📤 [Chat] Loading messages from API');
    print('[SKYBYN]    URL: $apiUrl');
    print('[SKYBYN]    Parameters: ${jsonEncode(requestParams)}');
    print('[SKYBYN]    Method: POST');
    developer.log('📤 [Chat] Loading messages from API', name: 'Chat API');
    developer.log('   URL: $apiUrl', name: 'Chat API');
    developer.log('   Parameters: ${jsonEncode(requestParams)}', name: 'Chat API');
    developer.log('   Method: POST', name: 'Chat API');

    try {
      final messages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );
      
      // Log API response
      print('[SKYBYN] 📥 [Chat] Messages API Response received');
      print('[SKYBYN]    Status: Success');
      print('[SKYBYN]    Messages Count: ${messages.length}');
      if (messages.isNotEmpty) {
        print('[SKYBYN]    First Message ID: ${messages.first.id}');
        print('[SKYBYN]    Last Message ID: ${messages.last.id}');
        print('[SKYBYN]    First Message Preview: ${messages.first.content.length > 50 ? messages.first.content.substring(0, 50) + "..." : messages.first.content}');
        // Count messages with attachments
        final messagesWithAttachments = messages.where((m) => m.attachmentUrl != null && m.attachmentType != null).length;
        print('[SKYBYN]    Messages with attachments: $messagesWithAttachments');
        
        // Log all messages to check attachment data
        for (var i = 0; i < messages.length; i++) {
          final msg = messages[i];
          print('[SKYBYN]    Message $i: id=${msg.id}, hasAttachment=${msg.attachmentUrl != null && msg.attachmentType != null}');
          if (msg.attachmentUrl != null || msg.attachmentType != null) {
            print('[SKYBYN]      - attachmentType: ${msg.attachmentType}');
            print('[SKYBYN]      - attachmentUrl: ${msg.attachmentUrl}');
            print('[SKYBYN]      - attachmentName: ${msg.attachmentName}');
            print('[SKYBYN]      - attachmentSize: ${msg.attachmentSize}');
          }
        }
      }
      developer.log('📥 [Chat] Messages API Response received', name: 'Chat API');
      developer.log('   Status: Success', name: 'Chat API');
      developer.log('   Messages Count: ${messages.length}', name: 'Chat API');
      if (messages.isNotEmpty) {
        developer.log('   First Message ID: ${messages.first.id}', name: 'Chat API');
        developer.log('   Last Message ID: ${messages.last.id}', name: 'Chat API');
      }
      print('[SKYBYN] ═══════════════════════════════════════════════════════');
      developer.log('═══════════════════════════════════════════════════════', name: 'Chat API');
      
      if (mounted) {
        setState(() {
          // Messages are already sorted oldest to newest from service
          // But ensure they're sorted by date to be safe
          _messages = messages;
          _messages.sort((a, b) => a.date.compareTo(b.date));
          _isLoading = false;
        });
        // Scroll to bottom when initially loading messages
        _scrollToBottom();
        
        // Mark all unread messages from this friend as read
        _chatService.markMessagesAsRead(friendId: widget.friend.id);
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error loading messages: $e');
      developer.log('❌ [Chat] Error loading messages: $e', name: 'Chat API');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setupWebSocketListener() {
    // Remove any existing callbacks first to prevent duplicates
    if (_webSocketChatMessageCallback != null) {
      _webSocketService.removeChatMessageCallback(_webSocketChatMessageCallback!);
      _webSocketChatMessageCallback = null;
    }
    if (_webSocketOnlineStatusCallback != null) {
      _webSocketService.removeOnlineStatusCallback(_webSocketOnlineStatusCallback!);
      _webSocketOnlineStatusCallback = null;
    }
    
    // Set up Firebase real-time listeners for chat (fallback)
    // Set up online status listener for the friend
    _onlineStatusSubscription = _firebaseRealtimeService.setupOnlineStatusListener(
      widget.friend.id,
      (userId, isOnline) {
        if (userId == widget.friend.id && mounted) {
          final oldStatus = _friendOnline;
          setState(() {
            _friendOnline = isOnline;
          });
        }
      },
    );

    // Set up WebSocket online status listener (primary real-time source)
    _webSocketOnlineStatusCallback = (userId, isOnline) {
      if (userId == widget.friend.id && mounted) {
        final oldStatus = _friendOnline;
        setState(() {
          _friendOnline = isOnline;
        });
      }
    };
    
    // Register callbacks with WebSocket service
    _webSocketChatMessageCallback = (messageId, fromUserId, toUserId, message) {
      // Debug: Log received message
      debugPrint('🔵 [ChatScreen] WebSocket chat message received: id=$messageId, from=$fromUserId, to=$toUserId, msg=${message.substring(0, message.length > 20 ? 20 : message.length)}...');
      
      // Only handle messages for this chat
      // Check if message is for this friend (either as sender or recipient)
      final isForThisChat = fromUserId == widget.friend.id || toUserId == widget.friend.id;
      debugPrint('🔵 [ChatScreen] Message for this chat? $isForThisChat (friend.id=${widget.friend.id}, currentUserId=$_currentUserId)');
      
      if (!isForThisChat) {
        debugPrint('🔵 [ChatScreen] Message rejected - not for this chat');
        return; // Not for this chat
      }
      
      // Ensure _currentUserId is loaded
      if (_currentUserId == null) {
        debugPrint('🔵 [ChatScreen] Current user ID is null, loading...');
        // Load user ID asynchronously and retry
        _loadUserId().then((_) {
          if (mounted) {
            debugPrint('🔵 [ChatScreen] User ID loaded: $_currentUserId, retrying message handling');
            // Retry handling the message after user ID is loaded
            _handleIncomingChatMessage(messageId, fromUserId, toUserId, message);
          }
        });
        return;
      }
      
      // Handle the message
      debugPrint('🔵 [ChatScreen] Handling incoming chat message');
      _handleIncomingChatMessage(messageId, fromUserId, toUserId, message);
    };
    
    _webSocketService.connect(
      onOnlineStatus: _webSocketOnlineStatusCallback,
      onChatMessage: _webSocketChatMessageCallback,
    );
    
    debugPrint('🔵 [ChatScreen] WebSocket callbacks registered. Chat callback: ${_webSocketChatMessageCallback != null}, Online callback: ${_webSocketOnlineStatusCallback != null}');
    debugPrint('🔵 [ChatScreen] Friend ID: ${widget.friend.id}, Current User ID: $_currentUserId');

    // Set up typing status listener
    _firebaseRealtimeService.setupTypingStatusListener(
      widget.friend.id,
      (userId, isTyping) {
        if (userId == widget.friend.id && mounted) {
          setState(() {
            _isFriendTyping = isTyping;
          });
          // Auto-hide typing indicator after 3 seconds if no stop message received
          if (isTyping) {
            _typingStopTimer?.cancel();
            _typingStopTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _isFriendTyping = false;
                });
              }
            });
          } else {
            _typingStopTimer?.cancel();
          }
        }
      },
    );

    // Set up chat message listener (Firebase fallback - only when WebSocket is not connected)
    _firebaseRealtimeService.setupChatListener(
      widget.friend.id,
      (messageId, fromUserId, toUserId, message) {
        // Only process if WebSocket is NOT connected (Firebase is fallback)
        if (_webSocketService.isConnected) {
          debugPrint('🔵 [ChatScreen] Skipping Firebase message - WebSocket is connected');
          return; // WebSocket handles it, skip Firebase to prevent duplicates
        }
        
        // Only handle messages for this chat
        final isForThisChat = fromUserId == widget.friend.id || toUserId == widget.friend.id;
        if (!isForThisChat) {
          return; // Not for this chat
        }
        
        // Ensure _currentUserId is loaded
        if (_currentUserId == null) {
          _loadUserId().then((_) {
            if (mounted) {
              _handleIncomingChatMessage(messageId, fromUserId, toUserId, message);
            }
          });
          return;
        }
        
        // Handle the message
        _handleIncomingChatMessage(messageId, fromUserId, toUserId, message);
      },
    );
  }

  // Handle incoming chat message (extracted for reuse)
  /// Helper method to safely add a message, preventing duplicates
  /// This method is thread-safe and checks for duplicates by message ID
  void _addMessageIfNotExists(Message message) {
    // Double-check for duplicates - check both by ID and by content+timestamp to be extra safe
    final existingById = _messages.indexWhere((m) => m.id == message.id && message.id.isNotEmpty);
    if (existingById != -1) {
      debugPrint('🟢 [ChatScreen] Message ${message.id} already exists (by ID), skipping duplicate');
      return;
    }
    
    // Additional check: if message ID is empty or invalid, check by content and timestamp
    // This prevents duplicates from messages with missing IDs
    if (message.id.isEmpty || message.id.startsWith('temp_')) {
      final existingByContent = _messages.indexWhere((m) => 
        m.content == message.content && 
        m.from == message.from && 
        m.to == message.to &&
        (m.date.difference(message.date).inSeconds.abs() < 2) // Within 2 seconds
      );
      if (existingByContent != -1) {
        debugPrint('🟢 [ChatScreen] Message already exists (by content+timestamp), skipping duplicate');
        return;
      }
    }
    
    // Message doesn't exist, add it
    setState(() {
      _messages.add(message);
      _messages.sort((a, b) => a.date.compareTo(b.date));
    });
    debugPrint('🟢 [ChatScreen] Message ${message.id} added. Total: ${_messages.length}');
  }

  /// Update an existing message (e.g., replace temp ID with real ID)
  void _updateMessage(String oldId, Message newMessage) {
    final index = _messages.indexWhere((m) => m.id == oldId);
    if (index != -1) {
      setState(() {
        _messages[index] = newMessage;
        _messages.sort((a, b) => a.date.compareTo(b.date));
      });
      debugPrint('🟢 [ChatScreen] Message updated from $oldId to ${newMessage.id}');
    } else {
      debugPrint('🟢 [ChatScreen] Message with ID $oldId not found for update');
    }
  }

  /// Find and update a temporary message by content and timestamp
  /// Returns true if message was updated, false if not found
  bool _updateTempMessageByContent(String realId, String fromUserId, String toUserId, String content, DateTime date) {
    // Find message with matching content, from, to, and recent timestamp
    final index = _messages.indexWhere((m) {
      if (!m.id.startsWith('temp_')) return false;
      if (m.from != fromUserId) return false;
      if (m.to != toUserId) return false;
      
      // Timestamp check (increased tolerance to 10s)
      if (m.date.difference(date).inSeconds.abs() > 10) return false;

      // 1. Exact match
      if (m.content == content) return true;

      // 2. Normalize content (remove whitespace, newlines) for formatted match
      // This handles server-side nl2br() or strip_tags()
      final String localClean = m.content.replaceAll(RegExp(r'[\s\n\r]'), '');
      final String remoteClean = content.replaceAll(RegExp(r'[\s\n\r]'), '');
      
      if (localClean == remoteClean) return true;

      // 3. Truncated match (if remote content ends with ...)
      if (content.endsWith('...')) {
        final String prefix = content.substring(0, content.length - 3);
        final String prefixClean = prefix.replaceAll(RegExp(r'[\s\n\r]'), '');
        if (localClean.startsWith(prefixClean) && prefixClean.length > 5) return true; // match at least 5 chars
      }
      
      return false;
    });
    
    if (index != -1) {
      final oldMessage = _messages[index];
      final updatedMessage = Message(
        id: realId,
        from: fromUserId,
        to: toUserId,
        content: oldMessage.content, // Keep local content to preserve formatting and prevent truncation
        date: date,
        viewed: oldMessage.viewed,
        isFromMe: oldMessage.isFromMe,
      );
      setState(() {
        _messages[index] = updatedMessage;
        _messages.sort((a, b) => a.date.compareTo(b.date));
      });
      debugPrint('🟢 [ChatScreen] Temp message updated with real ID: $realId (fuzzy match)');
      return true;
    }
    return false;
  }

  void _handleIncomingChatMessage(String messageId, String fromUserId, String toUserId, String message) {
    debugPrint('🟢 [ChatScreen] _handleIncomingChatMessage: id=$messageId, from=$fromUserId, to=$toUserId');
    
    // Verify this message is for this chat
    if (_currentUserId == null) {
      debugPrint('🟢 [ChatScreen] Cannot process - currentUserId is null');
      return; // Can't process without user ID
    }
    
    final isForThisChat = (fromUserId == widget.friend.id && toUserId == _currentUserId) ||
                          (fromUserId == _currentUserId && toUserId == widget.friend.id);
    debugPrint('🟢 [ChatScreen] Message is for this chat? $isForThisChat (friend.id=${widget.friend.id}, currentUserId=$_currentUserId)');
    
    if (!isForThisChat) {
      debugPrint('🟢 [ChatScreen] Message rejected - not for this chat');
      return; // Not for this chat
    }
    
    final messageDate = DateTime.now();
    
    // If we're the sender, this might be our own message coming back via WebSocket
    // Check if we have a temporary message that matches this content
    if (fromUserId == _currentUserId) {
      // First, check if we have a temp message with matching content
      final tempUpdated = _updateTempMessageByContent(
        messageId,
        fromUserId,
        toUserId,
        message,
        messageDate,
      );
      
      if (tempUpdated) {
        debugPrint('🟢 [ChatScreen] Updated temp message with real ID: $messageId');
        return; // Message updated, no need to add
      }
      
      // Check if message already exists with this ID (not a temp message)
      final existingMessageIndex = _messages.indexWhere((m) => m.id == messageId && !m.id.startsWith('temp_'));
      if (existingMessageIndex != -1) {
        // Message already exists, don't add duplicate
        debugPrint('🟢 [ChatScreen] Message from self already exists, skipping');
        return;
      }
      
      // This was sent from another device (website/other app instance)
      // Add it to the list so it appears on this device
      debugPrint('🟢 [ChatScreen] Message from self (other device) - adding to list');
      final newMessage = Message(
        id: messageId,
        from: fromUserId,
        to: toUserId,
        content: message,
        date: messageDate,
        viewed: false,
        isFromMe: true,
      );
      if (mounted) {
        _addMessageIfNotExists(newMessage);
        // Scroll to bottom to show the new message
        _scrollToBottom();
      }
      return; // Message added, don't process as recipient message
    }
    
    // We're the recipient - check if message already exists
    final existingMessageIndex = _messages.indexWhere((m) => m.id == messageId && !m.id.startsWith('temp_'));
    debugPrint('🟢 [ChatScreen] Message already exists? ${existingMessageIndex != -1} (index: $existingMessageIndex)');
    
    if (existingMessageIndex == -1) {
      // Message doesn't exist, add it
      debugPrint('🟢 [ChatScreen] Adding new message to list');
      final newMessage = Message(
        id: messageId,
        from: fromUserId,
        to: toUserId,
        content: message,
        date: messageDate,
        viewed: false,
        isFromMe: false,
      );
      if (mounted) {
        // Use helper method to prevent duplicates
        _addMessageIfNotExists(newMessage);
        // Always scroll to bottom for new messages
        _scrollToBottom();
        // Mark the new message as read if it's from the friend
        if (!newMessage.isFromMe) {
          _markMessagesAsRead();
        }
      } else {
        debugPrint('🟢 [ChatScreen] Widget not mounted, cannot add message');
      }
    } else {
      debugPrint('🟢 [ChatScreen] Message already exists, skipping');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Mark messages as read when they are displayed
  /// This is called when messages are loaded or when new messages arrive
  Future<void> _markMessagesAsRead() async {
    if (_currentUserId == null) {
      return; // Can't mark as read without user ID
    }

    // Get all unread messages from this friend (messages sent to current user)
    final unreadMessages = _messages.where((m) => 
      !m.isFromMe && 
      !m.viewed && 
      m.from == widget.friend.id
    ).toList();

    if (unreadMessages.isEmpty) {
      return; // No unread messages
    }

    print('[SKYBYN] 📤 [Chat] Marking ${unreadMessages.length} message(s) as read');
    developer.log('📤 [Chat] Marking ${unreadMessages.length} message(s) as read', name: 'Chat API');
    developer.log('   Friend ID: ${widget.friend.id}', name: 'Chat API');

    // Mark all unread messages from this friend as read
    // Use friendId approach for efficiency (marks all at once)
    try {
      final success = await _chatService.markMessagesAsRead(
        friendId: widget.friend.id,
      );
      
      if (success && mounted) {
        // Update local message state to reflect read status
        setState(() {
          for (final message in unreadMessages) {
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              _messages[index] = Message(
                id: message.id,
                from: message.from,
                to: message.to,
                content: message.content,
                date: message.date,
                viewed: true, // Mark as viewed
                isFromMe: message.isFromMe,
              );
            }
          }
        });
        print('[SKYBYN] ✅ Successfully marked ${unreadMessages.length} message(s) as read');
        developer.log('✅ Successfully marked ${unreadMessages.length} message(s) as read', name: 'Chat API');
      } else {
        print('[SKYBYN] ⚠️ Failed to mark messages as read (API returned false)');
        developer.log('⚠️ Failed to mark messages as read (API returned false)', name: 'Chat API');
      }
    } catch (e) {
      // Non-critical error - don't show to user
      print('[SKYBYN] ⚠️ Failed to mark messages as read: $e');
      developer.log('⚠️ Failed to mark messages as read: $e', name: 'Chat API');
    }
  }

  void _openChatListModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ChatListModal(),
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) {
      return;
    }
    
    // Ensure we have current user ID
    if (_currentUserId == null) {
      await _loadUserId();
      if (_currentUserId == null) {
        // Still no user ID, can't send message
        return;
      }
    }
    
    setState(() {
      _isSending = true;
    });

    try {
      // Clear input field
      _messageController.clear();
      
      // Keep keyboard open by maintaining focus
      if (mounted && _messageFocusNode.hasFocus) {
        // Request focus again after a brief delay to ensure keyboard stays open
        Future.microtask(() {
          if (mounted && _messageFocusNode.canRequestFocus) {
            _messageFocusNode.requestFocus();
          }
        });
      }
      
      // Send typing stop when message is sent
      if (_firebaseRealtimeService.isConnected) {
        _firebaseRealtimeService.sendTypingStop(widget.friend.id);
      }
      _typingTimer?.cancel();

      // Generate temporary ID for optimistic UI
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${_currentUserId!}';
      final messageDate = DateTime.now();
      
      // Create temporary message and add to UI immediately (optimistic UI)
      final tempMessage = Message(
        id: tempId,
        from: _currentUserId ?? '',
        to: widget.friend.id,
        content: message,
        date: messageDate,
        viewed: false,
        isFromMe: true,
      );
      
      // Add message to UI immediately
      if (mounted) {
        _addMessageIfNotExists(tempMessage);
        _scrollToBottom();
      }

      // Log API request
      final apiUrl = ApiConstants.chatSend;
      final requestParams = {
        'toUserId': widget.friend.id,
        'content': message.length > 50 ? message.substring(0, 50) + '...' : message,
      };
      
      print('[SKYBYN] ═══════════════════════════════════════════════════════');
      print('[SKYBYN] 📤 [Chat] Sending message to API');
      print('[SKYBYN]    URL: $apiUrl');
      print('[SKYBYN]    To User ID: ${widget.friend.id}');
      print('[SKYBYN]    Message Length: ${message.length}');
      print('[SKYBYN]    Message Preview: ${message.length > 50 ? message.substring(0, 50) + "..." : message}');
      print('[SKYBYN]    Temp ID: $tempId');
      print('[SKYBYN]    Method: POST');
      developer.log('📤 [Chat] Sending message to API', name: 'Chat API');
      developer.log('   URL: $apiUrl', name: 'Chat API');
      developer.log('   To User ID: ${widget.friend.id}', name: 'Chat API');
      developer.log('   Message Length: ${message.length}', name: 'Chat API');
      developer.log('   Temp ID: $tempId', name: 'Chat API');
      developer.log('   Method: POST', name: 'Chat API');
      
      // Track if message was successfully sent
      bool messageSentSuccessfully = false;
      Message? sentMessage;
      
      try {
        // Send message via API
        sentMessage = await _chatService.sendMessage(
          toUserId: widget.friend.id,
          content: message,
        );
        
        // Log API response
        if (sentMessage != null) {
          messageSentSuccessfully = true;
          print('[SKYBYN] 📥 [Chat] Send Message API Response received');
          print('[SKYBYN]    Status: Success');
          print('[SKYBYN]    Message ID: ${sentMessage.id}');
          print('[SKYBYN]    From: ${sentMessage.from}');
          print('[SKYBYN]    To: ${sentMessage.to}');
          developer.log('📥 [Chat] Send Message API Response received', name: 'Chat API');
          developer.log('   Status: Success', name: 'Chat API');
          developer.log('   Message ID: ${sentMessage.id}', name: 'Chat API');
          developer.log('   From: ${sentMessage.from}', name: 'Chat API');
          developer.log('   To: ${sentMessage.to}', name: 'Chat API');
        } else {
          print('[SKYBYN] 📥 [Chat] Send Message API Response received');
          print('[SKYBYN]    Status: Failed (null response)');
          developer.log('📥 [Chat] Send Message API Response received', name: 'Chat API');
          developer.log('   Status: Failed (null response)', name: 'Chat API');
        }
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        developer.log('═══════════════════════════════════════════════════════', name: 'Chat API');
      } catch (e) {
        // Only show error if message was NOT successfully sent
        if (!messageSentSuccessfully) {
          // Extract error message (remove "Exception: " prefix if present)
          String errorMessage = e.toString();
          if (errorMessage.startsWith('Exception: ')) {
            errorMessage = errorMessage.substring(11);
          }
          // Handle 409 Conflict - message may have been sent already
          // Check for various forms of conflict/duplicate messages
          final lowerError = errorMessage.toLowerCase();
          final isConflict = lowerError.contains('409') || 
              lowerError.contains('conflict') || 
              lowerError.contains('already been sent') || 
              errorMessage.contains('may have been sent') ||
              lowerError.contains('duplicate') ||
              lowerError.contains('already sent');
          if (isConflict) {
            // Message might have been sent - try to refresh messages
            _refreshMessages();
            
        // Show a less alarming message (orange instead of red)
        if (mounted) {
          setState(() {
            _chatStatusMessage = 'Message may have been sent already. Refreshing...';
            _chatStatusMessageIsError = false; // Use green/orange color
          });
          
          // Auto-dismiss after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _chatStatusMessage = null;
              });
            }
          });
        }
            // Reset _isSending before returning (finally will also reset it, but this ensures it's reset immediately)
            if (mounted) {
              setState(() {
                _isSending = false;
              });
            }
            return;
          }
          
          // Provide user-friendly error messages
          String userFriendlyMessage = errorMessage;
          if (lowerError.contains('500') || lowerError.contains('server error')) {
            userFriendlyMessage = 'Server error. Please try again in a moment.';
          } else if (lowerError.contains('timeout') || lowerError.contains('connection')) {
            userFriendlyMessage = 'Connection timeout. Please check your internet and try again.';
          } else if (lowerError.contains('network') || lowerError.contains('unreachable')) {
            userFriendlyMessage = 'Network error. Please check your connection and try again.';
          }
          
          // Show error message at top of chat box
          if (mounted) {
            setState(() {
              _chatStatusMessage = userFriendlyMessage;
              _chatStatusMessageIsError = true;
            });
            
            // Auto-dismiss after 4 seconds
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) {
                setState(() {
                  _chatStatusMessage = null;
                });
              }
            });
          }
        } else {
          // Message was sent successfully, but there was an error after (e.g., WebSocket/Firebase)
          // Don't show error to user - message was successfully saved
          print('[SKYBYN] ⚠️ [Chat] Message sent successfully, but error occurred after: $e');
          developer.log('⚠️ [Chat] Message sent successfully, but error occurred after: $e', name: 'Chat API');
        }
      }

      // Reset _isSending IMMEDIATELY after API call (before WebSocket/Firebase)
      // This ensures the button is enabled even if WebSocket/Firebase calls hang
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }

      if (sentMessage != null && mounted) {
        // Update the temporary message with the real message ID from API
        _updateMessage(tempId, sentMessage);
        
        // Keep keyboard open by maintaining focus
        if (_messageFocusNode.hasFocus) {
          Future.microtask(() {
            if (mounted && _messageFocusNode.canRequestFocus) {
              _messageFocusNode.requestFocus();
            }
          });
        }

        // Send message via both WebSocket and Firebase for real-time delivery
        // WebSocket: For immediate delivery when recipient's app is running
        // Firebase: For delivery when app is in background (triggers push notification)
        // NOTE: These are fire-and-forget - don't block on them and don't show errors
        try {
          // Send via WebSocket (non-blocking)
          if (_webSocketService.isConnected) {
            _webSocketService.sendChatMessage(
              messageId: sentMessage.id,
              targetUserId: widget.friend.id,
              content: message,
            );
          }
          
          // Send via Firebase (non-blocking, but await to catch errors)
          if (_firebaseRealtimeService.isConnected) {
            _firebaseRealtimeService.sendChatMessageNotification(
              messageId: sentMessage.id,
              targetUserId: widget.friend.id,
              content: message,
            ).catchError((e) {
              // Silently fail - message was already saved via HTTP API
              print('[SKYBYN] ⚠️ [Chat] Firebase notification failed (non-critical): $e');
            });
          }
        } catch (e) {
          // Don't fail the send - message was already saved via HTTP API
          // Don't show error to user - message was successfully sent
          print('[SKYBYN] ⚠️ [Chat] WebSocket/Firebase error (non-critical, message sent): $e');
        }
      } else {
        // sentMessage is null - API call failed
        // Remove the temporary message from UI
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == tempId);
            _isSending = false;
          });
          // Only show error if we haven't already shown one in the catch block
          if (!messageSentSuccessfully) {
            setState(() {
              _chatStatusMessage = 'Failed to send message. Please try again.';
              _chatStatusMessageIsError = true;
            });
            
            // Auto-dismiss after 4 seconds
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) {
                setState(() {
                  _chatStatusMessage = null;
                });
              }
            });
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _refreshMessages() async {
    try {
      print('[SKYBYN] 🔄 [Chat] Refreshing messages');
      developer.log('🔄 [Chat] Refreshing messages', name: 'Chat API');
      
      // Clear cache to force fresh fetch
      await _chatService.clearCache(widget.friend.id);
      
      // Reload messages from API
      final messages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );
      
      if (mounted) {
        setState(() {
          // Replace all messages with fresh data from API
          _messages = messages;
          _messages.sort((a, b) => a.date.compareTo(b.date));
        });
        
        // Scroll to bottom to show latest messages
        _scrollToBottom();
        
        // Mark messages as read
        _markMessagesAsRead();
        
        print('[SKYBYN] ✅ [Chat] Messages refreshed: ${messages.length} message(s)');
        developer.log('✅ [Chat] Messages refreshed: ${messages.length} message(s)', name: 'Chat API');
        
        // Show success message at top of chat box
        if (mounted) {
          setState(() {
            _chatStatusMessage = 'Refreshed ${messages.length} message(s)';
            _chatStatusMessageIsError = false;
          });
          
          // Auto-dismiss after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _chatStatusMessage = null;
              });
            }
          });
        }
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error refreshing messages: $e');
      developer.log('❌ [Chat] Error refreshing messages: $e', name: 'Chat API');
      
      // Show error message at top of chat box
      if (mounted) {
        setState(() {
          _chatStatusMessage = 'Failed to refresh messages';
          _chatStatusMessageIsError = true;
        });
        
        // Auto-dismiss after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _chatStatusMessage = null;
            });
          }
        });
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMoreMessages) return;

    setState(() {
      _isLoadingOlder = true;
    });

    try {
      final olderMessages = await _chatService.loadOlderMessages(
        friendId: widget.friend.id,
        currentMessageCount: _messages.length,
      );

      if (mounted && olderMessages.isNotEmpty) {
        // Save current scroll position
        final scrollPosition = _scrollController.hasClients 
            ? _scrollController.position.pixels 
            : 0.0;
        final firstMessageId = _messages.isNotEmpty ? _messages.first.id : null;

        // Prepend older messages to the list, avoiding duplicates
        setState(() {
          final existingIds = _messages.map((m) => m.id).toSet();
          final uniqueOlderMessages = olderMessages.where((m) => !existingIds.contains(m.id)).toList();
          _messages = [...uniqueOlderMessages, ..._messages];
          // Sort to ensure correct chronological order (oldest to newest)
          _messages.sort((a, b) => a.date.compareTo(b.date));
          _hasMoreMessages = olderMessages.length >= 50; // If we got less than 50, no more messages
        });

        // Restore scroll position after prepending
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && firstMessageId != null) {
            // Find the position of the first message we had before loading
            final firstMessageIndex = _messages.indexWhere((m) => m.id == firstMessageId);
            if (firstMessageIndex != -1) {
              // Calculate the new scroll position
              final newScrollPosition = scrollPosition + (olderMessages.length * 100.0); // Approximate
              _scrollController.jumpTo(newScrollPosition.clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              ));
            }
          }
        });
      } else if (mounted && olderMessages.isEmpty) {
        // No more messages to load
        setState(() {
          _hasMoreMessages = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlder = false;
        });
      }
    }
  }

  /// Check and request permissions for voice/video calls using Android system dialogs
  Future<bool> _checkCallPermissions(CallType callType) async {
    try {
      // Always need microphone for calls - use Android system dialog
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final micRequest = await Permission.microphone.request();
        if (!micRequest.isGranted) {
          if (micRequest.isPermanentlyDenied && mounted) {
            _showSettingsDialog('Microphone Permission Required',
                'Skybyn needs microphone access to make voice and video calls. Please enable it in settings.');
          }
          return false;
        }
      }

      // For video calls, also need camera - use Android system dialog
      if (callType == CallType.video) {
        final cameraStatus = await Permission.camera.status;
        if (!cameraStatus.isGranted) {
          final cameraRequest = await Permission.camera.request();
          if (!cameraRequest.isGranted) {
            if (cameraRequest.isPermanentlyDenied && mounted) {
              _showSettingsDialog('Camera Permission Required',
                  'Skybyn needs camera access to make video calls. Please enable it in settings.');
            }
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text('${TranslationKeys.errorCheckingPermissions.tr}: $e'),
            ),
          ),
        );
      }
      return false;
    }
  }

  /// Show settings dialog when permission is permanently denied
  void _showSettingsDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(TranslationKeys.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const TranslatedText(TranslationKeys.openSettings),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendDisplayName = widget.friend.nickname.isNotEmpty
        ? widget.friend.nickname
        : widget.friend.username;
    
    // Listen to keyboard changes and scroll to bottom when keyboard appears
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight > 0 && _messageFocusNode.hasFocus) {
      // Use WidgetsBinding to schedule scroll after frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _messageFocusNode.hasFocus) {
          _scrollToBottom();
        }
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: CustomAppBar(
        logoPath: 'assets/images/logo.png',
        onLogoPressed: () {
          // Navigate back to home screen
          Navigator.popUntil(context, (route) => route.isFirst);
        },
        onSearchFormToggle: () {
          setState(() {
            _showSearchForm = !_showSearchForm;
          });
        },
        isSearchFormVisible: _showSearchForm,
      ),
      body: Stack(
        children: [
          const BackgroundGradient(),
          GlobalSearchOverlay(
            isVisible: _showSearchForm,
            onClose: () {
              setState(() {
                _showSearchForm = false;
              });
            },
          ),
          SafeArea(
            child: Column(
              children: [
                // Friend info section under app bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      // Friend avatar and name on the left
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ProfileScreen(
                                  userId: widget.friend.id,
                                  username: widget.friend.username,
                                ),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                child: widget.friend.avatar.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: CachedNetworkImage(
                                          imageUrl: UrlHelper.convertUrl(widget.friend.avatar),
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          httpHeaders: const {},
                                          placeholder: (context, url) => ClipRRect(
                                            borderRadius: BorderRadius.circular(24),
                                            child: Image.asset(
                                              'assets/images/icon.png',
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          errorWidget: (context, url, error) {
                                            // Handle all errors including 404 (HttpExceptionWithStatus)
                                            return ClipRRect(
                                              borderRadius: BorderRadius.circular(24),
                                              child: Image.asset(
                                                'assets/images/icon.png',
                                                width: 48,
                                                height: 48,
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: Image.asset(
                                          'assets/images/icon.png',
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      friendDisplayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Friend.getStatusColorFromText(_getLastActiveStatus()),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _getLastActiveStatus(),
                                          style: TextStyle(
                                            color: Friend.getStatusColorFromText(_getLastActiveStatus()),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Circular buttons on the right
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Call button - only visible if rank > 3
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  // Check permissions before starting call
                                  final hasPermission = await _checkCallPermissions(CallType.audio);
                                  if (hasPermission && mounted) {
                                    Navigator.of(context, rootNavigator: false).push(
                                      MaterialPageRoute(
                                        builder: (newContext) => CallScreen(
                                          friend: widget.friend,
                                          callType: CallType.audio,
                                          isIncoming: false,
                                        ),
                                        // Don't use maintainState: false - it can cause navigation issues
                                        // The chat screen should remain in the stack
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.call,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Video call button - only visible if rank > 3
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  // Check permissions before starting call
                                  final hasPermission = await _checkCallPermissions(CallType.video);
                                  if (hasPermission && mounted) {
                                    Navigator.of(context, rootNavigator: false).push(
                                      MaterialPageRoute(
                                        builder: (newContext) => CallScreen(
                                          friend: widget.friend,
                                          callType: CallType.video,
                                          isIncoming: false,
                                        ),
                                        // Don't use maintainState: false - it can cause navigation issues
                                        // The chat screen should remain in the stack
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            const SizedBox(width: 12),
                          // More options button
                          GestureDetector(
                            key: _menuButtonKey,
                            onTap: () {
                              if (_menuOverlayEntry == null) {
                                _showChatMenu(context, _menuButtonKey);
                              } else {
                                _closeMenu();
                              }
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Chat messages area with rounded container - stretches down to input
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : _messages.isEmpty
                                  ? const Center(
                                      child: TranslatedText(
                                        TranslationKeys.noMessages,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        // Status message banner at top of chat
                                        if (_chatStatusMessage != null)
                                          Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: _chatStatusMessageIsError 
                                                  ? Colors.red.withOpacity(0.8)
                                                  : Colors.green.withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _chatStatusMessage!,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                                  onPressed: () {
                                                    setState(() {
                                                      _chatStatusMessage = null;
                                                    });
                                                  },
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: RefreshIndicator(
                                            onRefresh: _refreshMessages,
                                            color: Colors.white,
                                            backgroundColor: Colors.black.withOpacity(0.3),
                                            child: ListView.builder(
                                              controller: _scrollController,
                                              reverse: false, // Normal order: oldest at top, newest at bottom
                                              padding: const EdgeInsets.all(16),
                                              itemCount: _messages.length + (_isLoadingOlder ? 1 : 0),
                                              itemBuilder: (context, index) {
                                        // Show loading indicator at top when loading older messages
                                        if (_isLoadingOlder && index == 0) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            ),
                                          );
                                        }
                                        // Adjust index if loading indicator is shown
                                        final messageIndex = _isLoadingOlder ? index - 1 : index;
                                        final message = _messages[messageIndex];
                                        return _buildMessageBubble(message);
                                      },
                                            ),
                                          ),
                                        ),
                                        // Typing indicator at the bottom
                                        if (_isFriendTyping)
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '${widget.friend.username} is typing',
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            _buildTypingDot(0),
                                                            const SizedBox(width: 4),
                                                            _buildTypingDot(1),
                                                            const SizedBox(width: 4),
                                                            _buildTypingDot(2),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Input at the bottom - positioned same as CustomBottomNavigationBar
                // Add keyboard padding to keep input above keyboard
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Chat list button (copied from bottom nav)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () => _openChatListModal(context),
                                  icon: const Icon(
                                    Icons.chat_bubble,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Attachment button (only show if rank > 5)
                            if ((_userRank ?? 0) > 5)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: _showAttachmentOptions,
                                    icon: Icon(
                                      _showAttachmentMenu ? Icons.close : Icons.attach_file,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 16,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                maxLines: null,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (value) {
                                  if (value.trim().isNotEmpty) {
                                    _sendMessage();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Voice message button (long press to record) - only show if rank > 5
                            if ((_userRank ?? 0) > 5)
                              GestureDetector(
                                key: _microphoneButtonKey,
                                onLongPressStart: (details) {
                                  _startVoiceRecording();
                                },
                                onLongPressEnd: (details) {
                                  // Check if should cancel based on drag position
                                  final shouldCancel = _shouldCancelRecording;
                                  _stopVoiceRecording(cancel: shouldCancel);
                                },
                                onLongPressMoveUpdate: (details) {
                                  // Check if user dragged up (cancel gesture)
                                  final dragThreshold = 50.0; // pixels
                                  final shouldCancel = details.localPosition.dy < -dragThreshold;
                                  setState(() {
                                    _shouldCancelRecording = shouldCancel;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _isRecording 
                                          ? (_shouldCancelRecording ? Colors.orange.withOpacity(0.8) : Colors.green.withOpacity(0.8))
                                          : Colors.white.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _isRecording ? Icons.mic : Icons.mic_none,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: _sendMessage,
                                  icon: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Selected file preview (shown above input area)
          if (_selectedFile != null)
            _buildFilePreview(),
          // Attachment options menu (shown above input area)
          _buildAttachmentMenu(),
          // Audio visualizer (shown above microphone button when recording) - on top of everything
          if (_isRecording)
            _buildAudioVisualizerOverlay(),
        ],
      ),
    );
  }

  /// Build attachment widget based on type
  Widget _buildAttachmentWidget(Message message) {
    if (message.attachmentUrl == null || message.attachmentType == null) {
      return const SizedBox.shrink();
    }

    // Ensure URL is properly formatted with base URL if needed
    final fullUrl = UrlHelper.convertUrl(message.attachmentUrl!);
    
    // Debug logging for attachment display
    print('[SKYBYN] 📎 [Chat] Building attachment widget: type=${message.attachmentType}, url=$fullUrl, name=${message.attachmentName}');

    switch (message.attachmentType) {
      case 'image':
        return GestureDetector(
          onTap: () {
            // Show full screen image
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    iconTheme: const IconThemeData(color: Colors.white),
                  ),
                  body: Center(
                    child: CachedNetworkImage(
                      imageUrl: fullUrl,
                      fit: BoxFit.contain,
                      httpHeaders: const {},
                    ),
                  ),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: fullUrl,
              width: 250,
              height: 250,
              fit: BoxFit.cover,
              httpHeaders: const {},
              placeholder: (context, url) => Container(
                width: 250,
                height: 250,
                color: Colors.grey.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 250,
                height: 250,
                color: Colors.grey.withOpacity(0.3),
                child: const Icon(Icons.broken_image, color: Colors.white70),
              ),
            ),
          ),
        );

      case 'video':
        return Container(
          width: 250,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: fullUrl,
                  width: 250,
                  height: 200,
                  fit: BoxFit.cover,
                  httpHeaders: const {},
                  errorWidget: (context, url, error) => Container(
                    width: 250,
                    height: 200,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                ),
              ),
              const Icon(Icons.play_circle_filled, color: Colors.white, size: 48),
              if (message.attachmentName != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    message.attachmentName!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );

      case 'audio':
      case 'voice':
        return _buildAudioPlayer(fullUrl, message.attachmentType == 'voice');

      case 'file':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.attachmentName != null)
                      Text(
                        message.attachmentName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (message.attachmentSize != null)
                      Text(
                        _formatFileSize(message.attachmentSize!),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () {
                  // Open file URL
                  // You can use url_launcher or download the file
                },
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /// Format file size
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Build audio player widget
  Widget _buildAudioPlayer(String audioUrl, bool isVoice) {
    return _AudioPlayerWidget(audioUrl: audioUrl, isVoice: isVoice);
  }

  /// Build audio visualizer overlay positioned above microphone button
  Widget _buildAudioVisualizerOverlay() {
    // Use simpler positioning - fixed position above input area
    return Positioned(
      bottom: 150, // Above the input area
      right: 55, // Aligned with microphone button area
      child: _buildVisualizerCircle(),
    );
  }

  /// Build the circular visualizer container
  Widget _buildVisualizerCircle() {
    // Rebuild when audio level changes by using it in the widget tree
    // Use a key based on audio level to force rebuild when it changes significantly
    return Material(
      color: Colors.transparent,
      elevation: 10, // Ensure it's above other elements
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.95),
          shape: BoxShape.circle,
          border: Border.all(
            color: _shouldCancelRecording 
                ? Colors.orange.withOpacity(0.9)
                : (_isRecording ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9)),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (_shouldCancelRecording 
                  ? Colors.orange 
                  : (_isRecording ? Colors.green : Colors.red)).withOpacity(0.6),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipOval(
          child: Container(
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            child: _AudioVisualizerWidget(
              audioLevel: _audioLevel,
              isReadyToSend: _isRecording && !_shouldCancelRecording,
              isCancelled: _shouldCancelRecording,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return AnimatedBuilder(
      animation: _typingAnimation,
      builder: (context, child) {
        final delay = index * 0.2;
        final animatedValue = ((_typingAnimation.value + delay) % 1.0);
        final opacity = (animatedValue < 0.5) ? animatedValue * 2 : 2 - (animatedValue * 2);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3 + (opacity * 0.7)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isFromMe = message.isFromMe;
    final timeAgo = timeago.format(message.date, locale: 'en_short');

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context, message),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isFromMe) ...[
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: widget.friend.avatar.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: UrlHelper.convertUrl(widget.friend.avatar),
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/icon.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                          ),
                          errorWidget: (context, url, error) => ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/icon.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isFromMe
                      ? Colors.blue.withOpacity(0.8)
                      : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isFromMe ? 18 : 4),
                    bottomRight: Radius.circular(isFromMe ? 4 : 18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display attachment if exists
                    if (message.attachmentType != null && message.attachmentUrl != null) ...[
                      _buildAttachmentWidget(message),
                      if (message.content.isNotEmpty) const SizedBox(height: 8),
                    ],
                    // Display text content if exists
                    if (message.content.isNotEmpty)
                      Text(
                        message.content,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isFromMe) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: FutureBuilder<String?>(
                  future: _authService.getStoredUserProfile().then((u) => u?.avatar),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: UrlHelper.convertUrl(snapshot.data!),
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          httpHeaders: const {},
                          placeholder: (context, url) => ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/icon.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                          ),
                          errorWidget: (context, url, error) {
                            // Handle all errors including 404 (HttpExceptionWithStatus)
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/images/icon.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        ),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Close the menu overlay
  void _closeMenu() {
    _menuOverlayEntry?.remove();
    _menuOverlayEntry = null;
  }

  /// Close the message options overlay
  void _closeMessageOptions() {
    _messageOptionsOverlay?.remove();
    _messageOptionsOverlay = null;
    _selectedMessage = null;
  }

  /// Show message options when long-pressed
  void _showMessageOptions(BuildContext context, Message message) {
    _closeMessageOptions(); // Close any existing options
    
    _selectedMessage = message;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    _messageOptionsOverlay = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return Stack(
          children: [
            // Backdrop - tap to close
            GestureDetector(
              onTap: _closeMessageOptions,
              child: Container(
                color: Colors.black.withOpacity(0.3),
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            // Options bar positioned in the center-bottom area
            Positioned(
              bottom: screenHeight * 0.15, // Position from bottom
              left: (screenWidth - 240) / 2, // Center the options bar
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Like button (always visible)
                      _buildMessageOptionButton(
                        icon: Icons.favorite_border,
                        label: 'Like',
                        onTap: () => _likeMessage(message),
                      ),
                      // Edit button (only for own messages)
                      if (message.isFromMe) ...[
                        const SizedBox(width: 8),
                        _buildMessageOptionButton(
                          icon: Icons.edit,
                          label: 'Edit',
                          onTap: () => _editMessage(message),
                        ),
                      ],
                      // Delete button (only for own messages)
                      if (message.isFromMe) ...[
                        const SizedBox(width: 8),
                        _buildMessageOptionButton(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          onTap: () => _deleteMessage(message),
                          isDestructive: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_messageOptionsOverlay!);
  }

  Widget _buildMessageOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: () {
        _closeMessageOptions();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : Colors.white,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isDestructive ? Colors.red : Colors.white,
                fontSize: 10,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _likeMessage(Message message) async {
    // TODO: Implement like message functionality
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Like message feature coming soon'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _editMessage(Message message) async {
    _closeMessageOptions();
    
    // Show edit dialog
    final TextEditingController editController = TextEditingController(text: message.content);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        title: const Text(
          'Edit Message',
          style: TextStyle(color: Colors.white, decoration: TextDecoration.none),
        ),
        content: TextField(
          controller: editController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter message...',
            hintStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(editController.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != message.content && _currentUserId != null) {
      try {
        final apiUrl = '${ApiConstants.apiBase}/message/edit.php';
        final requestParams = {
          'userID': _currentUserId!,
          'friendID': widget.friend.id,
          'messageID': message.id,
          'content': result.length > 50 ? result.substring(0, 50) + '...' : result,
        };
        
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        print('[SKYBYN] 📤 [Chat] Editing message via API');
        print('[SKYBYN]    URL: $apiUrl');
        print('[SKYBYN]    Message ID: ${message.id}');
        print('[SKYBYN]    New Content Length: ${result.length}');
        print('[SKYBYN]    Method: POST');
        developer.log('📤 [Chat] Editing message via API', name: 'Chat API');
        developer.log('   URL: $apiUrl', name: 'Chat API');
        developer.log('   Message ID: ${message.id}', name: 'Chat API');
        developer.log('   New Content Length: ${result.length}', name: 'Chat API');
        
        final response = await http.post(
          Uri.parse(apiUrl),
          body: {
            'userID': _currentUserId!,
            'friendID': widget.friend.id,
            'messageID': message.id,
            'content': result,
          },
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ).timeout(const Duration(seconds: 10));
        
        print('[SKYBYN] 📥 [Chat] Edit Message API Response received');
        print('[SKYBYN]    Status Code: ${response.statusCode}');
        developer.log('📥 [Chat] Edit Message API Response received', name: 'Chat API');
        developer.log('   Status Code: ${response.statusCode}', name: 'Chat API');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == 1) {
            print('[SKYBYN]    Response: Success');
            developer.log('   Response: Success', name: 'Chat API');
            
            // Update message in list
            setState(() {
              final index = _messages.indexWhere((m) => m.id == message.id);
              if (index != -1) {
                _messages[index] = Message(
                  id: message.id,
                  from: message.from,
                  to: message.to,
                  content: result,
                  date: message.date,
                  viewed: message.viewed,
                  isFromMe: message.isFromMe,
                );
              }
            });
            
            // Show success message at top of chat box
            if (mounted) {
              setState(() {
                _chatStatusMessage = 'Message updated';
                _chatStatusMessageIsError = false;
              });
              
              // Auto-dismiss after 2 seconds
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _chatStatusMessage = null;
                  });
                }
              });
            }
          } else {
            print('[SKYBYN]    Response: Failed - ${data['message'] ?? 'Unknown error'}');
            developer.log('   Response: Failed - ${data['message'] ?? 'Unknown error'}', name: 'Chat API');
            
            // Show error message at top of chat box
            if (mounted) {
              setState(() {
                _chatStatusMessage = data['message'] ?? 'Failed to update message';
                _chatStatusMessageIsError = true;
              });
              
              // Auto-dismiss after 3 seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  setState(() {
                    _chatStatusMessage = null;
                  });
                }
              });
            }
          }
        } else {
          print('[SKYBYN]    Response: HTTP Error ${response.statusCode}');
          developer.log('   Response: HTTP Error ${response.statusCode}', name: 'Chat API');
          
          // Show error message at top of chat box
          if (mounted) {
            setState(() {
              _chatStatusMessage = 'Failed to update message';
              _chatStatusMessageIsError = true;
            });
            
            // Auto-dismiss after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _chatStatusMessage = null;
                });
              }
            });
          }
        }
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        developer.log('═══════════════════════════════════════════════════════', name: 'Chat API');
      } catch (e) {
        print('[SKYBYN] ❌ [Chat] Error editing message: $e');
        developer.log('❌ [Chat] Error editing message: $e', name: 'Chat API');
        
        // Show error message at top of chat box
        if (mounted) {
          setState(() {
            _chatStatusMessage = 'Error: $e';
            _chatStatusMessageIsError = true;
          });
          
          // Auto-dismiss after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _chatStatusMessage = null;
              });
            }
          });
        }
      }
    }
  }

  Future<void> _deleteMessage(Message message) async {
    _closeMessageOptions();
    
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: Colors.white, decoration: TextDecoration.none),
        ),
        content: const Text(
          'Are you sure you want to delete this message?',
          style: TextStyle(color: Colors.white70, decoration: TextDecoration.none),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && _currentUserId != null) {
      try {
        final apiUrl = '${ApiConstants.apiBase}/message/delete.php';
        final requestParams = {
          'userID': _currentUserId!,
          'friendID': widget.friend.id,
          'messageID': message.id,
        };
        
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        print('[SKYBYN] 📤 [Chat] Deleting message via API');
        print('[SKYBYN]    URL: $apiUrl');
        print('[SKYBYN]    Message ID: ${message.id}');
        print('[SKYBYN]    Method: POST');
        developer.log('📤 [Chat] Deleting message via API', name: 'Chat API');
        developer.log('   URL: $apiUrl', name: 'Chat API');
        developer.log('   Message ID: ${message.id}', name: 'Chat API');
        developer.log('   Method: POST', name: 'Chat API');
        
        final response = await http.post(
          Uri.parse(apiUrl),
          body: requestParams,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ).timeout(const Duration(seconds: 10));
        
        print('[SKYBYN] 📥 [Chat] Delete Message API Response received');
        print('[SKYBYN]    Status Code: ${response.statusCode}');
        developer.log('📥 [Chat] Delete Message API Response received', name: 'Chat API');
        developer.log('   Status Code: ${response.statusCode}', name: 'Chat API');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == 1) {
            print('[SKYBYN]    Response: Success');
            developer.log('   Response: Success', name: 'Chat API');
            
            // Remove message from list
            setState(() {
              _messages.removeWhere((m) => m.id == message.id);
            });
            
            // Show success message at top of chat box
            if (mounted) {
              setState(() {
                _chatStatusMessage = 'Message deleted';
                _chatStatusMessageIsError = false;
              });
              
              // Auto-dismiss after 2 seconds
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _chatStatusMessage = null;
                  });
                }
              });
            }
          } else {
            print('[SKYBYN]    Response: Failed - ${data['message'] ?? 'Unknown error'}');
            developer.log('   Response: Failed - ${data['message'] ?? 'Unknown error'}', name: 'Chat API');
            
            // Show error message at top of chat box
            if (mounted) {
              setState(() {
                _chatStatusMessage = data['message'] ?? 'Failed to delete message';
                _chatStatusMessageIsError = true;
              });
              
              // Auto-dismiss after 3 seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  setState(() {
                    _chatStatusMessage = null;
                  });
                }
              });
            }
          }
        } else {
          print('[SKYBYN]    Response: HTTP Error ${response.statusCode}');
          developer.log('   Response: HTTP Error ${response.statusCode}', name: 'Chat API');
          
          // Show error message at top of chat box
          if (mounted) {
            setState(() {
              _chatStatusMessage = 'Failed to delete message';
              _chatStatusMessageIsError = true;
            });
            
            // Auto-dismiss after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _chatStatusMessage = null;
                });
              }
            });
          }
        }
        print('[SKYBYN] ═══════════════════════════════════════════════════════');
        developer.log('═══════════════════════════════════════════════════════', name: 'Chat API');
      } catch (e) {
        print('[SKYBYN] ❌ [Chat] Error deleting message: $e');
        developer.log('❌ [Chat] Error deleting message: $e', name: 'Chat API');
        
        // Show error message at top of chat box
        if (mounted) {
          setState(() {
            _chatStatusMessage = 'Error: $e';
            _chatStatusMessageIsError = true;
          });
          
          // Auto-dismiss after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _chatStatusMessage = null;
              });
            }
          });
        }
      }
    }
  }

  /// Show the chat menu with transparent blurry background
  void _showChatMenu(BuildContext context, GlobalKey buttonKey) {
    _closeMenu(); // Close any existing menu

    final RenderBox? renderBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    _menuOverlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Full screen gesture detector to close menu when tapping outside
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // Menu content
            Positioned(
              right: 10,
              top: buttonPosition.dy + buttonSize.height + 8,
              child: GestureDetector(
                onTap: () {
                  // Prevent closing when tapping on the menu itself
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 200,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.getMenuBorderColor(context),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMenuItem(
                              context,
                              icon: Icons.person,
                              text: TranslationKeys.profile,
                              onTap: () {
                                _closeMenu();
                                _navigateToProfile();
                              },
                            ),
                            _buildMenuItem(
                              context,
                              icon: Icons.refresh,
                              text: 'Refresh Messages',
                              onTap: () {
                                _closeMenu();
                                _refreshMessages();
                              },
                            ),
                            Divider(
                              color: AppColors.getMenuDividerColor(context),
                            ),
                            _buildMenuItem(
                              context,
                              icon: Icons.block,
                              text: TranslationKeys.blockUser,
                              isDestructive: true,
                              onTap: () {
                                _closeMenu();
                                _showBlockConfirmation();
                              },
                            ),
                            _buildMenuItem(
                              context,
                              icon: Icons.person_remove,
                              text: TranslationKeys.removeFriend,
                              onTap: () {
                                _closeMenu();
                                _showUnfriendConfirmation();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_menuOverlayEntry!);
  }

  /// Build a menu item widget
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : AppColors.getIconColor(context),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TranslatedText(
                text,
                style: TextStyle(
                  color: isDestructive ? Colors.red : AppColors.getTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to friend's profile
  void _navigateToProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: widget.friend.id),
      ),
    );
  }


  /// Show confirmation dialog for blocking user
  void _showBlockConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const TranslatedText(TranslationKeys.blockUser),
          content: Text(
            TranslationKeys.blockUserConfirmation.tr.replaceAll('{name}', widget.friend.username),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const TranslatedText(TranslationKeys.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _blockUser();
              },
              child: const TranslatedText(
                TranslationKeys.blockUserButton,
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Block user
  Future<void> _blockUser() async {
    try {
      // TODO: Implement API call to block user
      // This should call an API endpoint to block the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.userBlocked),
            duration: Duration(seconds: 2),
          ),
        );
        // Navigate back after blocking
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.errorBlockingUser),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show confirmation dialog for unfriending
  void _showUnfriendConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const TranslatedText(TranslationKeys.unfriendTitle),
          content: Text(
            TranslationKeys.unfriendConfirmation.tr.replaceAll('{name}', widget.friend.username),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const TranslatedText(TranslationKeys.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _unfriendUser();
              },
              child: const TranslatedText(
                TranslationKeys.unfriendButton,
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Unfriend user
  Future<void> _unfriendUser() async {
    try {
      // TODO: Implement API call to unfriend user
      // This should call an API endpoint to remove the friendship
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.userUnfriended),
            duration: Duration(seconds: 2),
          ),
        );
        // Navigate back after unfriending
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.errorUnfriendingUser),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// Get formatted last active status string
  String _getLastActiveStatus() {
    if (_friendLastActive == null) {
      return _friendOnline ? 'Online' : 'Offline';
    }
    
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final twoMinutesAgo = now - 120; // 2 minutes = 120 seconds
    final oneHourAgo = now - 3600; // 1 hour = 3600 seconds
    
    if (_friendLastActive! >= twoMinutesAgo) {
      return 'Online';
    }
    
    // If last activity was more than 1 hour ago, show "Offline"
    if (_friendLastActive! < oneHourAgo) {
      return 'Offline';
    }
    
    final secondsAgo = now - _friendLastActive!;
    
    if (secondsAgo < 60) {
      return 'Last active ${secondsAgo}s ago';
    } else {
      final minutes = secondsAgo ~/ 60;
      return 'Last active ${minutes}m ago';
    }
  }

  /// Show attachment options menu
  void _showAttachmentOptions() {
    setState(() {
      _showAttachmentMenu = !_showAttachmentMenu;
    });
  }

  /// Build attachment options menu (horizontal circular buttons)
  Widget _buildAttachmentMenu() {
    if (!_showAttachmentMenu) return const SizedBox.shrink();

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Positioned(
      bottom: keyboardHeight > 0 ? 55 : 103, // Above the input area if the keyboard is shown
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAttachmentOption(
              icon: Icons.image,
              label: 'Photo',
              onTap: () {
                setState(() {
                  _showAttachmentMenu = false;
                });
                _pickImage(ImageSource.gallery);
              },
            ),
            _buildAttachmentOption(
              icon: Icons.camera_alt,
              label: 'Camera',
              onTap: () {
                setState(() {
                  _showAttachmentMenu = false;
                });
                _pickImage(ImageSource.camera);
              },
            ),
            _buildAttachmentOption(
              icon: Icons.videocam,
              label: 'Video',
              onTap: () {
                setState(() {
                  _showAttachmentMenu = false;
                });
                _pickVideo();
              },
            ),
            _buildAttachmentOption(
              icon: Icons.insert_drive_file,
              label: 'File',
              onTap: () {
                setState(() {
                  _showAttachmentMenu = false;
                });
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual attachment option button (circular)
  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build file preview widget (shown when file is selected)
  Widget _buildFilePreview() {
    if (_selectedFile == null || _selectedFileType == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 80, // Above the input area
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            // Preview thumbnail
            if (_selectedFileType == 'image')
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _selectedFile!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              )
            else if (_selectedFileType == 'video')
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 30,
                ),
              )
            else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insert_drive_file,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            const SizedBox(width: 12),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedFileType == 'image'
                        ? 'Image selected'
                        : _selectedFileType == 'video'
                            ? 'Video selected'
                            : 'File selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_selectedFileName != null)
                    Text(
                      _selectedFileName!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Cancel button
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedFile = null;
                  _selectedFileType = null;
                  _selectedFileName = null;
                });
              },
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
            // Send button
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () async {
                  if (_selectedFile != null && _selectedFileType != null) {
                    final file = _selectedFile!;
                    final type = _selectedFileType!;
                    final fileName = _selectedFileName ?? 'file';
                    
                    // Clear selection
                    setState(() {
                      _selectedFile = null;
                      _selectedFileType = null;
                      _selectedFileName = null;
                    });
                    
                    // Upload and send
                    await _uploadAndSendFile(file, type, fileName);
                  }
                },
                icon: const Icon(
                  Icons.send,
                  color: Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pick image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source, imageQuality: 85);
      
      if (image != null) {
        setState(() {
          _selectedFile = File(image.path);
          _selectedFileType = 'image';
          _selectedFileName = path.basename(image.path);
          _showAttachmentMenu = false;
        });
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error picking image: $e');
      if (mounted) {
        setState(() {
          _chatStatusMessage = 'Failed to pick image';
          _chatStatusMessageIsError = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _chatStatusMessage = null;
            });
          }
        });
      }
    }
  }

  /// Pick video
  Future<void> _pickVideo() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      
      if (video != null) {
        setState(() {
          _selectedFile = File(video.path);
          _selectedFileType = 'video';
          _selectedFileName = path.basename(video.path);
          _showAttachmentMenu = false;
        });
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error picking video: $e');
      if (mounted) {
        setState(() {
          _chatStatusMessage = 'Failed to pick video';
          _chatStatusMessageIsError = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _chatStatusMessage = null;
            });
          }
        });
      }
    }
  }

  /// Pick file
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _selectedFileType = 'file';
          _selectedFileName = result.files.single.name;
          _showAttachmentMenu = false;
        });
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error picking file: $e');
      if (mounted) {
        setState(() {
          _chatStatusMessage = 'Failed to pick file';
          _chatStatusMessageIsError = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _chatStatusMessage = null;
            });
          }
        });
      }
    }
  }

  /// Start voice recording
  Future<void> _startVoiceRecording() async {
    if (_isRecording) return; // Already recording
    
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _chatStatusMessage = 'Microphone permission is required';
            _chatStatusMessageIsError = true;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _chatStatusMessage = null;
              });
            }
          });
        }
        return;
      }

      // Get temporary directory for recording
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${directory.path}/voice_$timestamp.m4a';

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _recordingPath!,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _audioLevel = 0.0;
      });

      // Start listening to audio amplitude for visualization
      try {
        _amplitudeSubscription = _audioRecorder.onAmplitudeChanged(
          const Duration(milliseconds: 50), // Update more frequently for smoother visualization
        ).listen((amplitude) {
          if (mounted && _isRecording) {
            // Amplitude object has 'current' and 'max' properties in dB
            // Values are typically negative: -160 (silence) to 0 (loud)
            // Use the current amplitude for real-time visualization
            final currentDb = amplitude.current;
            
            // Normalize: map from dB range to 0.0-1.0
            // Typical voice range: -60dB (quiet) to -20dB (loud speaking)
            // We'll use a wider range for better responsiveness: -80dB to -10dB
            const minDb = -80.0; // Very quiet threshold
            const maxDb = -10.0;  // Loud speaking threshold
            
            // Clamp the input value first
            final clampedDb = currentDb.clamp(minDb, maxDb);
            // Normalize: (value - min) / (max - min)
            final normalizedLevel = ((clampedDb - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
            
            // Apply minimal smoothing for maximum responsiveness
            // Use exponential moving average: 20% old, 80% new for very fast response
            final smoothedLevel = (_audioLevel * 0.2 + normalizedLevel * 0.8);
            
            // Always update to ensure real-time visualization
            if (mounted) {
              setState(() {
                _audioLevel = smoothedLevel;
              });
            }
          }
        });
      } catch (e) {
        // If amplitude monitoring is not available, use a simulated wave
        print('[SKYBYN] ⚠️ [Chat] Amplitude monitoring not available: $e');
        // Start a timer to simulate audio levels with more variation
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (!_isRecording) {
            timer.cancel();
            return;
          }
          if (mounted) {
            // Simulate audio level with wave pattern and randomness
            final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
            final wave = (math.sin(time * 2) + 1) / 2;
            final random = math.Random().nextDouble() * 0.3;
            final simulatedLevel = (wave * 0.4 + random * 0.6 + 0.2).clamp(0.0, 1.0);
            setState(() {
              _audioLevel = (_audioLevel * 0.4 + simulatedLevel * 0.6);
            });
          }
        });
      }

      // Start timer to update duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
          });
        }
      });

      // Visualizer is shown via _buildAudioVisualizerOverlay() in the Stack
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error starting recording: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _chatStatusMessage = 'Failed to start recording';
          _chatStatusMessageIsError = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _chatStatusMessage = null;
            });
          }
        });
      }
    }
  }

  bool _shouldCancelRecording = false;

  /// Format duration in seconds to MM:SS
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Stop voice recording
  Future<void> _stopVoiceRecording({required bool cancel}) async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;

      if (_isRecording) {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _recordingDuration = 0;
          _audioLevel = 0.0;
        });

        if (!cancel && path != null && File(path).existsSync()) {
          // Only send if recording was at least 1 second
          if (_recordingDuration >= 1) {
            await _uploadAndSendFile(
              File(path),
              'voice',
              'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            );
          } else {
            // Too short, delete it
            File(path).deleteSync();
            if (mounted) {
              setState(() {
                _chatStatusMessage = 'Recording too short';
                _chatStatusMessageIsError = true;
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _chatStatusMessage = null;
                  });
                }
              });
            }
          }
        } else if (path != null && File(path).existsSync()) {
          // Delete cancelled recording
          File(path).deleteSync();
        }
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error stopping recording: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
    }
  }

  /// Upload file and send message
  Future<void> _uploadAndSendFile(File file, String type, String fileName) async {
    if (_currentUserId == null) return;

    try {
      setState(() {
        _isSending = true;
      });

      print('[SKYBYN] 📤 [Chat] Uploading file: $fileName, type: $type');

      // Upload file
      final uploadUrl = '${ApiConstants.apiBase}/chat/upload.php';
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      
      request.fields['userID'] = _currentUserId!;
      request.fields['to'] = widget.friend.id;
      request.fields['type'] = type;
      
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path, filename: fileName),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        print('[SKYBYN] 📥 [Chat] Upload response received');
        print('[SKYBYN]    Response body: ${response.body}');
        final data = json.decode(response.body);
        print('[SKYBYN]    Parsed data: $data');
        print('[SKYBYN]    responseCode: ${data['responseCode']}, type: ${data['responseCode'].runtimeType}');
        
        // Check for success (responseCode can be 1, "1", or true)
        final responseCode = data['responseCode'];
        final isSuccess = responseCode == 1 || responseCode == '1' || responseCode == true;
        
        if (isSuccess) {
          // APIResponse::sendSuccess merges data directly into response, not under 'data' key
          final fileUrl = (data['fileUrl'] ?? data['data']?['fileUrl']) as String?;
          final messageId = (data['messageId'] ?? data['data']?['messageId']) as int?;
          
          if (fileUrl == null) {
            throw Exception('File URL not found in response');
          }

          print('[SKYBYN] ✅ [Chat] File uploaded: $fileUrl');

          // Create message with attachment
          final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${_currentUserId!}';
          final tempMessage = Message(
            id: tempId,
            from: _currentUserId!,
            to: widget.friend.id,
            content: type == 'voice' ? '🎤 Voice message' : '',
            date: DateTime.now(),
            isFromMe: true,
            attachmentType: type,
            attachmentUrl: fileUrl,
            attachmentName: fileName,
            attachmentSize: await file.length(),
          );

          setState(() {
            _messages.add(tempMessage);
          });

          _scrollToBottom();

          // If messageId is returned, update the temp message
          if (messageId != null) {
            final sentMessage = Message(
              id: messageId.toString(),
              from: _currentUserId!,
              to: widget.friend.id,
              content: tempMessage.content,
              date: tempMessage.date,
              isFromMe: true,
              attachmentType: type,
              attachmentUrl: fileUrl,
              attachmentName: fileName,
              attachmentSize: tempMessage.attachmentSize,
            );
            _updateMessage(tempId, sentMessage);
          }

          // Send via WebSocket
          try {
            // WebSocket sendChatMessage requires messageId, targetUserId, and content
            // For file attachments, we'll send a text message indicating the attachment
            final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
            _webSocketService.sendChatMessage(
              messageId: tempMessageId,
              targetUserId: widget.friend.id,
              content: type == 'voice' ? '🎤 Voice message' : (tempMessage.content.isNotEmpty ? tempMessage.content : '📎 File'),
            );
          } catch (e) {
            print('[SKYBYN] ⚠️ [Chat] WebSocket send failed (non-critical): $e');
          }

          // Mark messages as read
          _markMessagesAsRead();
          
          // Clear selected file
          setState(() {
            _selectedFile = null;
            _selectedFileType = null;
            _selectedFileName = null;
            _isSending = false;
          });
        } else {
          // Log the actual response for debugging
          print('[SKYBYN] ❌ [Chat] Upload failed - responseCode: ${data['responseCode']}, message: ${data['message']}');
          throw Exception(data['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('Upload failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error uploading file: $e');
      if (mounted) {
        setState(() {
          _chatStatusMessage = 'Failed to send file';
          _chatStatusMessageIsError = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _chatStatusMessage = null;
            });
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }
}

/// Audio player widget for voice messages and audio files
class _AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final bool isVoice;

  const _AudioPlayerWidget({
    required this.audioUrl,
    required this.isVoice,
  });

  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _audioPlayer.setUrl(widget.audioUrl);
      _audioPlayer.durationStream.listen((duration) {
        if (duration != null) {
          setState(() {
            _duration = duration;
          });
        }
      });
      _audioPlayer.positionStream.listen((position) {
        setState(() {
          _position = position;
        });
      });
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      });
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error initializing audio player: $e');
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
      } else {
        setState(() {
          _isLoading = true;
        });
        await _audioPlayer.play();
        setState(() {
          _isPlaying = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[SKYBYN] ❌ [Chat] Error toggling playback: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
            onPressed: _togglePlayPause,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.isVoice ? Icons.mic : Icons.music_note,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.isVoice ? 'Voice message' : 'Audio file',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white.withOpacity(0.3),
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 2,
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds.toDouble()
                              : 0.0,
                          max: _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: (value) {
                            _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio visualizer widget that shows audio waveform
class _AudioVisualizerWidget extends StatefulWidget {
  final double audioLevel; // 0.0 to 1.0
  final bool isReadyToSend;
  final bool isCancelled;

  const _AudioVisualizerWidget({
    super.key,
    required this.audioLevel,
    this.isReadyToSend = false,
    this.isCancelled = false,
  });

  @override
  State<_AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<_AudioVisualizerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _animationOffset = 0.0;
  double _previousAudioLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100), // Faster animation for real-time feel
    )..repeat();
    
    _animationController.addListener(() {
      setState(() {
        _animationOffset = _animationController.value * 2 * math.pi;
      });
    });
  }

  @override
  void didUpdateWidget(_AudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update previous level when widget updates
    _previousAudioLevel = oldWidget.audioLevel;
    // Force rebuild when audio level changes significantly
    if ((widget.audioLevel - oldWidget.audioLevel).abs() > 0.001) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Create animated bars based on real-time audio level
    final barCount = 20; // Increased for denser waveform
    final bars = List.generate(barCount, (index) {
      // Base position for each bar (0.0 to 1.0)
      final position = index / barCount;
      
      // Each bar responds differently based on its position to create a wave effect
      final barPhase = position * 2 * math.pi;
      
      // Create a subtle rotating wave pattern for visual interest
      final waveOffset = (math.sin(barPhase + _animationOffset) + 1) / 2; // 0 to 1
      
      // Primary driver: actual audio level from microphone
      // Each bar gets a different response based on position to create variation
      // Use a sine wave pattern so bars peak at different times
      final barVariation = (math.sin(barPhase * 3 + _animationOffset * 0.7) + 1) / 2; // 0 to 1
      
      // Combine: 85% actual audio level, 15% position-based variation for wave effect
      // This makes bars respond to voice but with a dynamic wave pattern
      final audioModulated = widget.audioLevel * (0.5 + barVariation * 0.5);
      final combinedLevel = (audioModulated * 0.85 + waveOffset * 0.15).clamp(0.0, 1.0);
      
      // Calculate height - directly responsive to audio
      final minHeight = 4.0;
      final maxHeight = 40.0; // Slightly taller for better visualization
      final height = minHeight + (combinedLevel * (maxHeight - minHeight));
      
      // Color intensity based on audio level (brighter when louder)
      final baseOpacity = 0.4;
      final colorIntensity = (baseOpacity + (widget.audioLevel * 0.6)).clamp(0.3, 1.0);
      
      // Determine bar color
      Color barColor = Colors.red;
      if (widget.isCancelled) {
        barColor = Colors.orange;
      } else if (widget.isReadyToSend) {
        barColor = Colors.green;
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 50), // Faster updates for responsiveness
        curve: Curves.easeOut,
        width: 2.0, // Thinner bars for density
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          color: barColor.withOpacity(colorIntensity),
          borderRadius: BorderRadius.circular(1.0),
        ),
      );
    });

    return SizedBox(
      width: 70, // Slightly wider for more bars
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: bars,
      ),
    );
  }
}

