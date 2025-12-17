import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'call_screen.dart';
import '../config/constants.dart';
import '../widgets/chat_list_modal.dart';
import '../widgets/app_colors.dart';
import '../services/chat_message_count_service.dart';
import '../widgets/skeleton_loader.dart';

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
  bool _showSearchForm = false;
  bool _hasMoreMessages = true;
  final FocusNode _messageFocusNode = FocusNode();
  bool _isFriendTyping = false;
  Timer? _typingTimer;
  Timer? _typingStopTimer;
  Timer? _messageCheckTimer; // Periodic check for new messages
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
    _setupWebSocketListener(); // Set up WebSocket listener for real-time messages
    _setupScrollListener();
    _setupKeyboardListener();
    // _setupTypingListener();
    _setupTypingAnimation();
    _checkFriendOnlineStatus(); // Check immediately
    _startPeriodicMessageCheck(); // Start periodic message checking as fallback
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
    WidgetsBinding.instance.removeObserver(this);
    // Clear the current open chat when leaving the screen
    if (_chatMessageCountService.currentOpenChatFriendId == widget.friend.id) {
      _chatMessageCountService.setCurrentOpenChat(null);
    }
    _closeMenu();
    _closeMessageOptions();
    _messageFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _onlineStatusTimer?.cancel();
    _typingTimer?.cancel();
    _typingStopTimer?.cancel();
    _messageCheckTimer?.cancel();
    _typingAnimationController.dispose();
    // Send typing stop when leaving screen
      if (_firebaseRealtimeService.isConnected && _currentUserId != null) {
        _firebaseRealtimeService.sendTypingStop(widget.friend.id);
      }
      // Cancel online status subscription when widget is disposed
      _onlineStatusSubscription?.cancel();
      // Remove WebSocket online status callback when widget is disposed
      if (_webSocketOnlineStatusCallback != null) {
        _webSocketService.removeOnlineStatusCallback(_webSocketOnlineStatusCallback!);
        _webSocketOnlineStatusCallback = null;
      }
      // Remove WebSocket chat message callback when widget is disposed
      if (_webSocketChatMessageCallback != null) {
        _webSocketService.removeChatMessageCallback(_webSocketChatMessageCallback!);
        _webSocketChatMessageCallback = null;
      }
      // Close menu if open
      _closeMenu();
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
    // Chat scroll listener disabled - UI only
    // _scrollController.addListener(() {
    //   // Chat loading disabled
    // });
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

  // Typing listener removed - UI only
  // void _setupTypingListener() {
  //   // Chat typing logic removed
  // }

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

  /// Start periodic message checking as fallback if WebSocket is not connected
  void _startPeriodicMessageCheck() {
    _messageCheckTimer?.cancel();

    // Check every 3 seconds if WebSocket is not connected
    _messageCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;

      // Only poll if WebSocket is not connected
      if (!_webSocketService.isConnected) {
        await _checkForNewMessages();
      }
    });
  }

  /// Check for new messages using get.php API (fallback when WebSocket is not connected)
  Future<void> _checkForNewMessages() async {
    if (_currentUserId == null || _isLoading) return;

    try {
      // Get the latest message ID and timestamp to detect new messages
      final lastMessageId = _messages.isNotEmpty ? _messages.last.id : null;
      final lastMessageDate = _messages.isNotEmpty
          ? _messages.last.date.millisecondsSinceEpoch ~/ 1000
          : 0;

      // Fetch messages from API
      final messages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );

      if (mounted && messages.isNotEmpty) {
        // Find new messages (messages we don't have yet)
        final newMessages = <Message>[];
        for (final msg in messages) {
          // Check by ID first (most reliable)
          if (lastMessageId != null && msg.id == lastMessageId) {
            // We've reached the last message we have, stop checking
            break;
          }

          // Check if we already have this message
          if (!_messages.any((m) => m.id == msg.id)) {
            // Check if it's newer than our last message
            final msgTimestamp = msg.date.millisecondsSinceEpoch ~/ 1000;
            if (msgTimestamp >= lastMessageDate) {
              newMessages.add(msg);
            }
          }
        }

        if (newMessages.isNotEmpty) {
          setState(() {
            // Add new messages
            _messages.addAll(newMessages);
            // Sort messages by date
            _messages.sort((a, b) => a.date.compareTo(b.date));
          });

          // Scroll to bottom to show new messages
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      }
    } catch (e) {
      // Silently fail - don't spam errors for periodic checks
    }
  }

  Future<void> _checkFriendOnlineStatus() async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.profile),
        body: {'userID': widget.friend.id},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['responseCode'] == '1') {
          // Check last_active timestamp
          // Online: last_active <= 2 minutes
          // Away: last_active > 2 minutes (shown as offline in UI)
          final lastActiveValue = data['last_active'];
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

          if (mounted) {
            setState(() {
              _friendOnline = isOnline;
              _friendLastActive = lastActive;
            });
          }
        }
      }
    } catch (e) {
      // Silently fail - don't spam errors for online status checks
      if (mounted) {
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_currentUserId == null) {
      // Wait for user ID to be loaded
      await Future.delayed(const Duration(milliseconds: 100));
      if (_currentUserId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final messages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );
      if (mounted) {
        setState(() {
          _messages = messages;
          // Sort messages by date (oldest first) for proper display
          _messages.sort((a, b) => a.date.compareTo(b.date));
          _isLoading = false;
        });
        // Scroll to bottom after a short delay to ensure list is rendered
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // Log error for debugging
      debugPrint('Error loading messages: $e');
    }
  }

  /// Set up WebSocket listener for real-time chat messages
  void _setupWebSocketListener() {
    // Register callback for offline notifications
    _webSocketService.connect(
      onChatOffline: (fromUserId, toUserId, message) {
        _handleChatOffline(fromUserId, toUserId, message);
      },
    );
    // Remove existing callback if any
    if (_webSocketChatMessageCallback != null) {
      _webSocketService.removeChatMessageCallback(_webSocketChatMessageCallback!);
    }

    // Register callback to receive chat messages
    _webSocketChatMessageCallback = (String messageId, String fromUserId, String toUserId, String messageContent) {
      if (!mounted || _currentUserId == null) return;

      // Only handle messages between current user and this friend
      // This prevents processing messages from other conversations
      final isMessageForThisChat =
        (fromUserId == _currentUserId && toUserId == widget.friend.id) ||  // We sent to friend
        (fromUserId == widget.friend.id && toUserId == _currentUserId);    // Friend sent to us

      if (isMessageForThisChat) {
        _handleIncomingChatMessage(messageId, fromUserId, toUserId, messageContent);
      }
    };

    _webSocketService.registerChatMessageCallback(_webSocketChatMessageCallback!);
  }

  // Chat message handling logic removed - UI only
  // void _addMessageIfNotExists(Message message) {
  //   // Removed
  // }

  // Chat status logic removed - UI only
  // bool _isStatusMoreAdvanced(MessageStatus newStatus, MessageStatus oldStatus) {
  //   // Removed
  // }

  /// Handle incoming chat message from WebSocket
  void _handleIncomingChatMessage(String messageId, String fromUserId, String toUserId, String messageContent) {
    if (!mounted || _currentUserId == null) return;

    // Check if message already exists by ID (prevent duplicates)
    if (_messages.any((m) => m.id == messageId)) {
      return;
    }

    // Check for duplicate based on content, sender, and recent timestamp (prevent race condition duplicates)
    // This handles the case where chat_sent arrives before optimistic message is added
    final now = DateTime.now();
    final isDuplicateByContent = _messages.any((m) =>
      m.content == messageContent &&
      m.from == fromUserId &&
      m.to == toUserId &&
      now.difference(m.date).inSeconds.abs() < 5 // Within 5 seconds
    );

    if (isDuplicateByContent) {
      return;
    }

    try {
      // Parse date if available, otherwise use current time
      DateTime messageDate = DateTime.now();

      final isFromMe = fromUserId == _currentUserId;

      // If this is an incoming message (not from me), try to store it in database
      // This is a workaround for bot protection blocking sender's storage attempt
      if (!isFromMe && messageId.startsWith('temp_')) {
        _storeIncomingMessageInDatabase(fromUserId, toUserId, messageContent).catchError((e) {
          // Continue anyway - message is displayed via WebSocket
        });
      }

      // If message has temp ID, fetch real ID from API
      if (messageId.startsWith('temp_') || messageId.isEmpty) {
        // Fetch message ID from API by getting latest messages
        _fetchMessageIdFromAPI(fromUserId, messageContent, messageDate).then((realMessageId) {
          if (realMessageId != null && mounted) {
            // Update message with real ID
            final messageIndex = _messages.indexWhere((m) =>
              m.content == messageContent &&
              m.from == fromUserId &&
              (m.id == messageId || m.id.startsWith('temp_'))
            );

            if (messageIndex != -1) {
              setState(() {
                _messages[messageIndex] = Message(
                  id: realMessageId,
                  from: fromUserId,
                  to: toUserId,
                  content: messageContent,
                  date: _messages[messageIndex].date,
                  viewed: false,
                  isFromMe: isFromMe,
                  status: MessageStatus.sent,
                );
                _messages.sort((a, b) => a.date.compareTo(b.date));
              });
            } else {
              // Message not found, create new one with real ID
              final message = Message(
                id: realMessageId,
                from: fromUserId,
                to: toUserId,
                content: messageContent,
                date: messageDate,
                viewed: false,
                isFromMe: isFromMe,
                status: MessageStatus.sent,
              );

              setState(() {
                _messages.add(message);
                _messages.sort((a, b) => a.date.compareTo(b.date));
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom();
              });
            }
          }
        }).catchError((e) {
          debugPrint('[SKYBYN] ⚠️ [Chat] Error fetching message ID from API: $e');
          // Still add message with temp ID if API fails
          _addMessageWithTempId(messageId, fromUserId, toUserId, messageContent, messageDate, isFromMe);
        });
        return;
      }

      // If this is a confirmation for a message we sent (chat_sent), update the optimistic message
      if (isFromMe && !messageId.startsWith('temp_')) {
        // Find optimistic message with same content and update it
        final tempIndex = _messages.indexWhere((m) =>
          m.content == messageContent &&
          m.isFromMe &&
          (m.status == MessageStatus.sending || m.id.startsWith('temp_'))
        );

        if (tempIndex != -1) {
          // Update existing optimistic message with real ID
          setState(() {
            _messages[tempIndex] = Message(
              id: messageId,
              from: fromUserId,
              to: toUserId,
              content: messageContent,
              date: messageDate,
              viewed: false,
              isFromMe: true,
              status: MessageStatus.sent,
            );
            _messages.sort((a, b) => a.date.compareTo(b.date));
          });
          return; // Don't add duplicate
        }
      }

      // Create message object for new incoming message with real ID
      final message = Message(
        id: messageId,
        from: fromUserId,
        to: toUserId,
        content: messageContent,
        date: messageDate,
        viewed: false,
        isFromMe: isFromMe,
        status: MessageStatus.sent,
      );

      setState(() {
        _messages.add(message);
        // Sort messages by date
        _messages.sort((a, b) => a.date.compareTo(b.date));
      });

      // Scroll to bottom to show new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      // Silently fail
    }
  }

  /// Fetch message ID from API by matching content and sender
  Future<String?> _fetchMessageIdFromAPI(String fromUserId, String messageContent, DateTime messageDate) async {
    try {
      // Get recent messages from API
      final messages = await _chatService.getMessages(
        friendId: fromUserId,
      );

      // Find message matching content and sender, within last 30 seconds
      final now = DateTime.now();
      for (final msg in messages) {
        final timeDiff = now.difference(msg.date).inSeconds;
        if (msg.content == messageContent &&
            msg.from == fromUserId &&
            timeDiff <= 30) {
          return msg.id;
        }
      }
    } catch (e) {
      debugPrint('[SKYBYN] ⚠️ [Chat] Error fetching messages from API: $e');
    }
    return null;
  }

  /// Add message with temp ID (fallback if API fails)
  void _addMessageWithTempId(String messageId, String fromUserId, String toUserId, String messageContent, DateTime messageDate, bool isFromMe) {
    final message = Message(
      id: messageId,
      from: fromUserId,
      to: toUserId,
      content: messageContent,
      date: messageDate,
      viewed: false,
      isFromMe: isFromMe,
      status: MessageStatus.sent,
    );

    setState(() {
      _messages.add(message);
      _messages.sort((a, b) => a.date.compareTo(b.date));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  /// Handle chat offline notification - send FCM notification to recipient
  Future<void> _handleChatOffline(String fromUserId, String toUserId, String message) async {
    try {
      // Get username and avatar from current user profile (sender's own profile)
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      final senderUsername = user?.username ?? 'Someone';
      final senderAvatar = user?.avatar ?? '';

      // Get session token and user ID for authentication
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('sessionToken');
      final currentUserId = prefs.getString('userID') ?? prefs.getString(StorageKeys.userId);

      if (sessionToken == null || currentUserId == null) {
        // Session not available - cannot send notification
        return;
      }

      // Build avatar URL if provided
      String? avatarUrl;
      if (senderAvatar.isNotEmpty && !senderAvatar.startsWith('http')) {
        // If avatar is a relative path, convert to full URL
        avatarUrl = 'https://skybyn.no/$senderAvatar';
      } else if (senderAvatar.isNotEmpty) {
        avatarUrl = senderAvatar;
      }

      // Call firebase.php API to send notification
      // Use simple http.post() like token.php does (no custom client, minimal headers)
      final url = ApiConstants.firebase;
      final response = await http.post(
        Uri.parse(url),
        body: {
          'userID': currentUserId, // Required for session validation
          'sessionToken': sessionToken, // Required for session validation
          'user': toUserId,
          'title': senderUsername,
          'body': message,
          'type': 'admin',
          'from': fromUserId,
          'priority': 'high',
          'channel': 'chat_messages',
          if (avatarUrl != null) 'image': avatarUrl,
          'payload': jsonEncode({
            'messageId': 'temp_${DateTime.now().millisecondsSinceEpoch}',
            'from': fromUserId,
            'to': toUserId,
            'message': message,
            'chat': message,
          }),
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Check both responseCode (like token.php) and status field
        final responseCode = responseData['responseCode'] ?? responseData['status'];
        final isSuccess = responseCode == '1' || responseCode == 'success' || responseCode == 'ok';

        if (isSuccess) {
          debugPrint('[SKYBYN] ✅ [Chat] FCM notification sent successfully to user: $toUserId');
          if (responseData['messageId'] != null) {
            debugPrint('[SKYBYN] 📨 [Chat] FCM message ID: ${responseData['messageId']}');
          }
        } else {
          final errorMsg = responseData['message'] ?? 'Unknown error';
          debugPrint('[SKYBYN] ⚠️ [Chat] FCM notification failed: $errorMsg');
        }
      } else {
        debugPrint('[SKYBYN] ❌ [Chat] FCM notification HTTP error: ${response.statusCode}');
        try {
          final responseData = json.decode(response.body);
          debugPrint('[SKYBYN] ❌ [Chat] Error message: ${responseData['message'] ?? response.body}');
        } catch (e) {
          debugPrint('[SKYBYN] ❌ [Chat] Response body: ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('[SKYBYN] ❌ [Chat] Error sending FCM notification: $e');
    }
  }

  /// Store incoming message in database (called when recipient receives message via WebSocket)
  /// This is a workaround for bot protection blocking sender's storage attempt
  Future<void> _storeIncomingMessageInDatabase(String fromUserId, String toUserId, String message) async {
    try {
      final url = ApiConstants.chatSend;
      // Use simple http.post() like token.php does (no custom client, minimal headers)
      final response = await http.post(
        Uri.parse(url),
        body: {
          'userID': fromUserId,
          'to': toUserId,
          'message': message,
        },
      ).timeout(const Duration(seconds: 10));

      // Response handled silently
    } catch (e) {
      // Don't throw - message is already displayed via WebSocket
    }
  }
  //   // Removed
  // }

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

    if (_currentUserId == null) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    // Clear input field immediately for better UX
    _messageController.clear();

    try {
      // Send message via API
      final sentMessage = await _chatService.sendMessage(
        toUserId: widget.friend.id,
        content: message,
      );

      if (sentMessage != null && mounted) {
        // Add message to local list optimistically
        setState(() {
          _messages.add(sentMessage);
          // Keep messages sorted by date
          _messages.sort((a, b) => a.date.compareTo(b.date));
        });

        // Scroll to bottom to show new message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        // Refresh messages to get latest from server (handles any server-side updates)
        // Do this in background to avoid blocking UI
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            final refreshedMessages = await _chatService.getMessages(
              friendId: widget.friend.id,
            );
            if (mounted && refreshedMessages.isNotEmpty) {
              setState(() {
                _messages = refreshedMessages;
                _messages.sort((a, b) => a.date.compareTo(b.date));
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom();
              });
            }
          } catch (e) {
            // Ignore refresh errors - we already have the message
          }
        });
      }
    } catch (e) {
      // Restore message text on error
      _messageController.text = message;

      if (mounted) {
        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Chat refresh logic removed - UI only
  // Future<void> _refreshMessages() async {
  //   // Removed
  // }

  // Chat load older messages logic removed - UI only
  // Future<void> _loadOlderMessages() async {
  //   // Removed
  // }

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
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: UrlHelper.convertUrl(widget.friend.avatar),
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          httpHeaders: const {},
                                          placeholder: (context, url) => Image.asset(
                                            'assets/images/icon.png',
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          ),
                                          errorWidget: (context, url, error) {
                                            // Handle all errors including 404 (HttpExceptionWithStatus)
                                            return Image.asset(
                                              'assets/images/icon.png',
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            );
                                          },
                                        ),
                                      )
                                    : Image.asset(
                                        'assets/images/icon.png',
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
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
                          if (_userRank != null && _userRank! > 3) ...[
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
                          ],
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
                              ? const ChatScreenSkeleton()
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
                                        Expanded(
                                          child: RefreshIndicator(
                                            onRefresh: () async {}, // Chat refresh disabled - UI only
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
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                enabled: !_isSending,
                                onSubmitted: (_) => _sendMessage(),
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
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child:                                 IconButton(
                                  onPressed: _isSending ? null : _sendMessage,
                                  icon: _isSending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white54,
                                          ),
                                        )
                                      : const Icon(
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
        ],
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
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: UrlHelper.convertUrl(widget.friend.avatar),
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Image.asset(
                            'assets/images/icon.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                          errorWidget: (context, url, error) => Image.asset(
                            'assets/images/icon.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    : Image.asset(
                        'assets/images/icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
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
                      return ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: UrlHelper.convertUrl(snapshot.data!),
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          httpHeaders: const {},
                          placeholder: (context, url) => Image.asset(
                            'assets/images/icon.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                          errorWidget: (context, url, error) {
                            // Handle all errors including 404 (HttpExceptionWithStatus)
                            return Image.asset(
                              'assets/images/icon.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      );
                    }
                    return Image.asset(
                      'assets/images/icon.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
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
        final response = await http.post(
          Uri.parse('${ApiConstants.apiBase}/message/edit.php'),
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

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == 1) {
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

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message updated'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(data['message'] ?? 'Failed to update message'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to update message'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
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
        final response = await http.post(
          Uri.parse('${ApiConstants.apiBase}/message/delete.php'),
          body: {
            'userID': _currentUserId!,
            'friendID': widget.friend.id,
            'messageID': message.id,
          },
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == 1) {
            // Remove message from list
            setState(() {
              _messages.removeWhere((m) => m.id == message.id);
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message deleted'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(data['message'] ?? 'Failed to delete message'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to delete message'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
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
                              icon: Icons.delete_outline,
                              text: TranslationKeys.clearChatHistory,
                              onTap: () {
                                _closeMenu();
                                _showClearChatConfirmation();
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

  /// Show confirmation dialog for clearing chat
  void _showClearChatConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const TranslatedText(TranslationKeys.clearChatHistoryTitle),
          content: const TranslatedText(TranslationKeys.clearChatHistoryMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const TranslatedText(TranslationKeys.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearChatHistory();
              },
              child: const TranslatedText(
                TranslationKeys.clearChatHistoryButton,
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Clear chat history
  Future<void> _clearChatHistory() async {
    try {
      // TODO: Implement API call to clear chat history
      // For now, just clear local messages
      setState(() {
        _messages.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.chatHistoryCleared),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.errorClearingChat),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
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
}
