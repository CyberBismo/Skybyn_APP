import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/background_gradient.dart';
import '../widgets/global_search_overlay.dart';
import '../models/friend.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/firebase_realtime_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_screen.dart';
import 'call_screen.dart';
import '../config/constants.dart';
import '../widgets/chat_list_modal.dart';

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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _isSending = false;
  String? _currentUserId;
  Timer? _onlineStatusTimer;
  bool _friendOnline = false;
  bool _showSearchForm = false;
  bool _hasMoreMessages = true;
  final FocusNode _messageFocusNode = FocusNode();
  bool _isFriendTyping = false;
  Timer? _typingTimer;
  Timer? _typingStopTimer;
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;
  // Store subscription for cleanup
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _onlineStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _friendOnline = widget.friend.online; // Initialize with friend's current status
    _loadUserId();
    _loadMessages();
    _setupWebSocketListener();
    _setupScrollListener();
    _setupKeyboardListener();
    _setupTypingListener();
    _setupTypingAnimation();
    _checkFriendOnlineStatus(); // Check immediately
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
    _messageFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _onlineStatusTimer?.cancel();
    _typingTimer?.cancel();
    _typingStopTimer?.cancel();
    _typingAnimationController.dispose();
    // Send typing stop when leaving screen
      if (_firebaseRealtimeService.isConnected && _currentUserId != null) {
        _firebaseRealtimeService.sendTypingStop(widget.friend.id);
      }
      // Cancel online status subscription when widget is disposed
      _onlineStatusSubscription?.cancel();
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
          final lastActive = int.tryParse(data['last_active']?.toString() ?? '0') ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final twoMinutesAgo = now - 120; // 2 minutes = 120 seconds
          final isOnline = lastActive >= twoMinutesAgo;

          if (mounted && _friendOnline != isOnline) {
            setState(() {
              _friendOnline = isOnline;
            });
          }
        }
      }
    } catch (e) {
      // Silently fail - don't spam errors for online status checks
      if (mounted) {
        print('⚠️ [ChatScreen] Error checking friend online status: $e');
      }
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final messages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );
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
      }
    } catch (e) {
      print('❌ [ChatScreen] Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setupWebSocketListener() {
    // Set up Firebase real-time listeners for chat
    // Set up online status listener for the friend
    _onlineStatusSubscription = _firebaseRealtimeService.setupOnlineStatusListener(
      widget.friend.id,
      (userId, isOnline) {
        if (userId == widget.friend.id && mounted) {
          final oldStatus = _friendOnline;
          print('🔥 [ChatScreen] Firebase online status update: userId=$userId, oldStatus=$oldStatus -> newStatus=$isOnline');
          setState(() {
            _friendOnline = isOnline;
          });
        }
      },
    );

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

    // Set up chat message listener
    _firebaseRealtimeService.setupChatListener(
      widget.friend.id,
      (messageId, fromUserId, toUserId, message) {
        // Only handle messages for this chat
        if ((fromUserId == widget.friend.id && toUserId == _currentUserId) ||
            (fromUserId == _currentUserId && toUserId == widget.friend.id)) {
          // Check if message already exists
          if (!_messages.any((m) => m.id == messageId)) {
            final newMessage = Message(
              id: messageId,
              from: fromUserId,
              to: toUserId,
              content: message,
              date: DateTime.now(),
              viewed: false,
              isFromMe: fromUserId == _currentUserId,
            );
            if (mounted) {
              setState(() {
                // Add new message to the end (bottom) of the list
                _messages.add(newMessage);
                // Sort messages by date to ensure correct order (oldest to newest)
                _messages.sort((a, b) => a.date.compareTo(b.date));
              });
              // Always scroll to bottom for new messages
              _scrollToBottom();
            }
          }
        }
      },
    );
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
    if (message.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      // Optimistically add message to UI
      final tempMessage = Message(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        from: _currentUserId ?? '',
        to: widget.friend.id,
        content: message,
        date: DateTime.now(),
        viewed: false,
        isFromMe: true,
      );

      setState(() {
        _messages.add(tempMessage);
      });
      _messageController.clear();
      _scrollToBottom();
      
      // Send typing stop when message is sent
      if (_firebaseRealtimeService.isConnected) {
        _firebaseRealtimeService.sendTypingStop(widget.friend.id);
      }
      _typingTimer?.cancel();

      // Send message via API
      final sentMessage = await _chatService.sendMessage(
        toUserId: widget.friend.id,
        content: message,
      );

      if (sentMessage != null && mounted) {
        // Replace temp message with real one
        setState(() {
          _messages.removeWhere((m) => m.id == tempMessage.id);
          _messages.add(sentMessage);
          // Sort messages by date to ensure correct order (oldest to newest)
          _messages.sort((a, b) => a.date.compareTo(b.date));
        });
        // Scroll to bottom to show the sent message
        _scrollToBottom();

        // Note: Chat messages are sent via ChatService which handles Firebase
        // Real-time delivery is handled by Firebase listeners set up in _setupWebSocketListener()
      }
    } catch (e) {
      debugPrint('❌ [ChatScreen] Error sending message: $e');
      
      // Extract error message (remove "Exception: " prefix if present)
      String errorMessage = e.toString();
      debugPrint('🔍 [ChatScreen] Raw error: $errorMessage');
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      debugPrint('🔍 [ChatScreen] Cleaned error message: $errorMessage');
      
      // Handle 409 Conflict - message may have been sent already
      // Check for various forms of conflict/duplicate messages
      final lowerError = errorMessage.toLowerCase();
      debugPrint('🔍 [ChatScreen] Lowercase error: $lowerError');
      
      final isConflict = lowerError.contains('409') || 
          lowerError.contains('conflict') || 
          lowerError.contains('already been sent') || 
          lowerError.contains('may have been sent') ||
          lowerError.contains('duplicate') ||
          lowerError.contains('already sent');
      
      debugPrint('🔍 [ChatScreen] Is conflict detected: $isConflict');
      
      if (isConflict) {
        // Message might have been sent - try to refresh messages
        debugPrint('⚠️ [ChatScreen] 409 Conflict detected - message may have been sent already, refreshing...');
        
        // Remove temp message since it might have been sent
        setState(() {
          _messages.removeWhere((m) => m.id.startsWith('temp_'));
        });
        
        // Refresh messages to check if it was sent
        _refreshMessages();
        
        // Show a less alarming message (orange instead of red)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message may have been sent already. Refreshing...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // Remove temp message on error
      setState(() {
        _messages.removeWhere((m) => m.id.startsWith('temp_'));
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
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

  Future<void> _refreshMessages() async {
    try {
      final messages = await _chatService.getMessages(
        friendId: widget.friend.id,
      );
      if (mounted) {
        // Only update if we have new messages
        final currentMessageIds = _messages.map((m) => m.id).toSet();
        final newMessages = messages.where((m) => !currentMessageIds.contains(m.id)).toList();
        
        if (newMessages.isNotEmpty) {
          // Check if user is near bottom before updating
          final wasNearBottom = _scrollController.hasClients 
              ? _scrollController.position.pixels >= 
                  _scrollController.position.maxScrollExtent - 200
              : true;
          
          setState(() {
            // Update messages and sort to ensure correct order
            _messages = messages;
            _messages.sort((a, b) => a.date.compareTo(b.date));
          });
          
          // Only scroll to bottom if user was already near the bottom
          // This prevents interrupting user if they're reading older messages
          if (wasNearBottom) {
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      // Silently fail - don't spam errors
      print('⚠️ [ChatScreen] Error refreshing messages: $e');
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

        // Prepend older messages to the list
        setState(() {
          _messages = [...olderMessages, ..._messages];
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
    } catch (e) {
      print('❌ [ChatScreen] Error loading older messages: $e');
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
      print('❌ [ChatScreen] Error checking permissions: $e');
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
            child: TranslatedText(TranslationKeys.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: TranslatedText(TranslationKeys.openSettings),
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
                                            color: _friendOnline
                                                ? Colors.greenAccent
                                                : Colors.white70,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _friendOnline
                                              ? 'Online'
                                              : 'Offline',
                                          style: TextStyle(
                                            color: _friendOnline
                                                ? Colors.greenAccent
                                                : Colors.white70,
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
                          // Call button
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
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => CallScreen(
                                        friend: widget.friend,
                                        callType: CallType.audio,
                                        isIncoming: false,
                                      ),
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
                          // Video call button
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
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => CallScreen(
                                        friend: widget.friend,
                                        callType: CallType.video,
                                        isIncoming: false,
                                      ),
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
                            child: PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              color: Colors.white.withOpacity(0.95),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (value) {
                                _handleMenuAction(value);
                              },
                              itemBuilder: (BuildContext context) => [
                                PopupMenuItem<String>(
                                  value: 'view_profile',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person, size: 20, color: Colors.black87),
                                      const SizedBox(width: 12),
                                      TranslatedText(TranslationKeys.profile),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'clear_chat',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline, size: 20, color: Colors.black87),
                                      const SizedBox(width: 12),
                                      TranslatedText(TranslationKeys.clearChatHistory),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem<String>(
                                  value: 'block',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.block, size: 20, color: Colors.red),
                                      const SizedBox(width: 12),
                                      TranslatedText(TranslationKeys.blockUser),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'unfriend',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person_remove, size: 20, color: Colors.orange),
                                      const SizedBox(width: 12),
                                      TranslatedText(TranslationKeys.removeFriend),
                                    ],
                                  ),
                                ),
                              ],
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
                                  ? Center(
                                      child: TranslatedText(
                                        TranslationKeys.noMessages,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        Expanded(
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
                  padding: EdgeInsets.only(
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

    return Padding(
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
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
    );
  }

  /// Handle menu actions from the 3-dot menu
  void _handleMenuAction(String action) {
    switch (action) {
      case 'view_profile':
        _navigateToProfile();
        break;
      case 'clear_chat':
        _showClearChatConfirmation();
        break;
      case 'block':
        _showBlockConfirmation();
        break;
      case 'unfriend':
        _showUnfriendConfirmation();
        break;
    }
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
          title: TranslatedText(TranslationKeys.clearChatHistoryTitle),
          content: TranslatedText(TranslationKeys.clearChatHistoryMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: TranslatedText(TranslationKeys.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearChatHistory();
              },
              child: TranslatedText(
                TranslationKeys.clearChatHistoryButton,
                style: const TextStyle(color: Colors.red),
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
          SnackBar(
            content: TranslatedText(TranslationKeys.chatHistoryCleared),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [ChatScreen] Error clearing chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(TranslationKeys.errorClearingChat),
            duration: const Duration(seconds: 3),
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
          title: TranslatedText(TranslationKeys.blockUser),
          content: Text(
            TranslationKeys.blockUserConfirmation.tr.replaceAll('{name}', widget.friend.username),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: TranslatedText(TranslationKeys.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _blockUser();
              },
              child: TranslatedText(
                TranslationKeys.blockUserButton,
                style: const TextStyle(color: Colors.red),
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
      debugPrint('🛑 [ChatScreen] Blocking user: ${widget.friend.id}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(TranslationKeys.userBlocked),
            duration: const Duration(seconds: 2),
          ),
        );
        // Navigate back after blocking
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ [ChatScreen] Error blocking user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(TranslationKeys.errorBlockingUser),
            duration: const Duration(seconds: 3),
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
          title: TranslatedText(TranslationKeys.unfriendTitle),
          content: Text(
            TranslationKeys.unfriendConfirmation.tr.replaceAll('{name}', widget.friend.username),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: TranslatedText(TranslationKeys.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _unfriendUser();
              },
              child: TranslatedText(
                TranslationKeys.unfriendButton,
                style: const TextStyle(color: Colors.orange),
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
      debugPrint('👋 [ChatScreen] Unfriending user: ${widget.friend.id}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(TranslationKeys.userUnfriended),
            duration: const Duration(seconds: 2),
          ),
        );
        // Navigate back after unfriending
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ [ChatScreen] Error unfriending user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(TranslationKeys.errorUnfriendingUser),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

