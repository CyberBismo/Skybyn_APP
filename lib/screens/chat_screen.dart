import 'package:flutter/material.dart';
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
import '../services/websocket_service.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'profile_screen.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final Friend friend;

  const ChatScreen({
    super.key,
    required this.friend,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final WebSocketService _wsService = WebSocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _currentUserId;
  Timer? _refreshTimer;
  bool _showSearchForm = false;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadMessages();
    _setupWebSocketListener();
    // Refresh messages every 3 seconds when screen is active
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _refreshMessages();
      }
    });
  }

  Future<void> _loadUserId() async {
    _currentUserId = await _authService.getStoredUserId();
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
          _messages = messages;
          _isLoading = false;
        });
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
    // Update WebSocket callbacks to include chat handling
    // This will update callbacks without disconnecting if already connected
    // WebSocket is only connected when app is in foreground (handled by main.dart lifecycle)
    _wsService.connect(
      onChatMessage: (messageId, fromUserId, toUserId, message) {
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
                _messages.add(newMessage);
              });
              _scrollToBottom();
            }
          }
        }
      },
      // Pass null for other callbacks to preserve existing ones
      // The WebSocket service will merge callbacks
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
        });

        // Send via WebSocket for real-time delivery (if app is in focus)
        if (_wsService.isConnected) {
          _wsService.sendMessage(jsonEncode({
            'type': 'chat',
            'id': sentMessage.id,
            'from': sentMessage.from,
            'to': sentMessage.to,
            'message': sentMessage.content,
          }));
        }
      }
    } catch (e) {
      print('❌ [ChatScreen] Error sending message: $e');
      // Remove temp message on error
      setState(() {
        _messages.removeWhere((m) => m.id.startsWith('temp_'));
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
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
          setState(() {
            _messages = messages;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Silently fail - don't spam errors
      print('⚠️ [ChatScreen] Error refreshing messages: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

    return Scaffold(
      extendBodyBehindAppBar: true,
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
                                          imageUrl: widget.friend.avatar,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Image.asset(
                                            'assets/images/icon.png',
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          ),
                                          errorWidget: (context, url, error) => Image.asset(
                                            'assets/images/icon.png',
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          ),
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
                                            color: widget.friend.online
                                                ? Colors.greenAccent
                                                : Colors.white70,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          widget.friend.online
                                              ? 'Online'
                                              : 'Offline',
                                          style: TextStyle(
                                            color: widget.friend.online
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
                            child: IconButton(
                              onPressed: () {
                                // TODO: Implement more options
                              },
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
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
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.all(16),
                                      itemCount: _messages.length,
                                      itemBuilder: (context, index) {
                                        final message = _messages[index];
                                        return _buildMessageBubble(message);
                                      },
                                    ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Input at the bottom - positioned same as CustomBottomNavigationBar
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
                            Expanded(
                              child: TextField(
                                controller: _messageController,
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
                        imageUrl: widget.friend.avatar,
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
                        imageUrl: snapshot.data!,
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
}

