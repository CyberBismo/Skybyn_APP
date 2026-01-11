import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/friend_service.dart';
import '../services/auth_service.dart';
import '../services/firebase_realtime_service.dart';
import '../services/websocket_service.dart';
import '../services/chat_message_count_service.dart';
import '../services/chat_service.dart';
import '../models/friend.dart';
import '../models/message.dart';
import '../screens/chat_screen.dart';

import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../config/constants.dart';

class ChatListModal extends StatefulWidget {
  const ChatListModal({super.key});

  @override
  State<ChatListModal> createState() => _ChatListModalState();
}

class _ChatListModalState extends State<ChatListModal> {
  final FriendService _friendService = FriendService();
  final AuthService _authService = AuthService();
  final FirebaseRealtimeService _firebaseRealtimeService = FirebaseRealtimeService();
  final ChatMessageCountService _chatMessageCountService = ChatMessageCountService();
  final ChatService _chatService = ChatService();
  final WebSocketService _webSocketService = WebSocketService();

  List<Friend> _friends = [];
  bool _isLoading = true;
  
  // Store last messages for each friend
  final Map<String, Message?> _lastMessages = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _setupWebSocketListener();
    _setupUnreadCountListener();
    _setupChatMessageListener();
  }

  @override
  void dispose() {
    // Remove online status listener
    _webSocketService.removeOnlineStatusCallback(_handleOnlineStatusUpdate);
    
    // Remove unread count listener
    _chatMessageCountService.removeListener(_onUnreadCountChanged);
    super.dispose();
  }

  void _setupUnreadCountListener() {
    // Listen to unread count changes to update the UI
    _chatMessageCountService.addListener(_onUnreadCountChanged);
  }

  void _onUnreadCountChanged() {
    if (mounted) {
      setState(() {
        // Trigger rebuild to show updated unread counts
      });
    }
  }

  void _setupWebSocketListener() {
    // Listen to WebSocket updates (Online Status + Chat Messages)
    _webSocketService.connect(
      onOnlineStatus: _handleOnlineStatusUpdate,
      onChatMessage: _handleNewMessage,
    );
  }

  void _handleNewMessage(String messageId, String fromUserId, String toUserId, String message) async {
    if (!mounted) return;
    
    final currentUserId = await _authService.getStoredUserId();
    if (currentUserId == null) return;
    
    // Determine which friend this message is from/to
    String? friendId;
    if (fromUserId == currentUserId) {
      friendId = toUserId; // Message sent to this friend
    } else if (toUserId == currentUserId) {
      friendId = fromUserId; // Message received from this friend
    }
    
    if (friendId != null && friendId.isNotEmpty) {
      final friendIdNonNull = friendId; // Non-null assertion

      setState(() {
        // Update last message for this friend
        _lastMessages[friendIdNonNull] = Message(
          id: messageId,
          from: fromUserId,
          to: toUserId,
          content: message,
          date: DateTime.now(),
          viewed: false,
          isFromMe: fromUserId == currentUserId,
        );
        _sortFriends();
      });
    }
  }

  void _setupChatMessageListener() {
    // Listen to Firebase chat messages (Fallback)
    _firebaseRealtimeService.setupChatListener(
      '', // Empty friendId means listen to all chats
      _handleNewMessage,
    );
  }
  void _sortFriends() {
    _friends.sort((a, b) {
      final msgA = _lastMessages[a.id];
      final msgB = _lastMessages[b.id];
      
      // If one has a message and other doesn't, the one with message comes first
      if (msgA != null && msgB == null) return -1;
      if (msgA == null && msgB != null) return 1;
      
      // If both have messages, sort by date descending (newest first)
      if (msgA != null && msgB != null) {
        return msgB.date.compareTo(msgA.date);
      }
      
      // If neither has message, sort by online status then name
      if (a.online != b.online) {
        return a.online ? -1 : 1;
      }
      
      final nameA = a.nickname.isNotEmpty ? a.nickname : a.username;
      final nameB = b.nickname.isNotEmpty ? b.nickname : b.username;
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });
  }

  void _handleOnlineStatusUpdate(String userId, bool isOnline) {
    if (!mounted) return;
    
    setState(() {
      final index = _friends.indexWhere((f) => f.id == userId);
      if (index != -1) {
        // Only update if status actually changed
        if (_friends[index].online != isOnline) {
          _friends[index] = _friends[index].copyWith(online: isOnline);
          // Re-sort list if status changed (online users usually on top)
          _sortFriends();
        }
      }
    });
  }

  Future<void> _loadFriends() async {
    final userId = await _authService.getStoredUserId();
    if (!mounted) return;
    if (userId == null) {
      setState(() {
        _friends = [];
        _isLoading = false;
      });
      return;
    }

    // Load cached data first, then update if changes detected
    final friends = await _friendService.fetchFriendsForUser(
      userId: userId,
      onUpdated: (updatedFriends) {
        // Update UI when friends list changes in background
        if (mounted) {
          setState(() {
            _friends = updatedFriends;
            _sortFriends();
          });
        }
      },
    );

    if (!mounted) return;

    // Load last messages from local DB cache *before* showing the list
    // This ensures valid sorting on initial render
    try {
      final latestMessages = await _chatService.getLatestMessages();
      for (var friendId in latestMessages.keys) {
        _lastMessages[friendId] = latestMessages[friendId];
      }
    } catch (e) {
      // Ignore
    }

    setState(() {
      _friends = friends;
      _isLoading = false;
      _sortFriends();
    });
    
    // Load last messages for all friends
    _loadLastMessages();
  }

  Future<void> _loadLastMessages() async {
    final currentUserId = await _authService.getStoredUserId();
    if (currentUserId == null) return;
    
    // 1. Fast load from local DB using getLatestMessages (efficient SQL query)
    try {
      final latestMessages = await _chatService.getLatestMessages();
      if (mounted) {
        setState(() {
          // Update all known friends with their latest message from local DB
          for (var friendId in latestMessages.keys) {
            _lastMessages[friendId] = latestMessages[friendId];
          }
        });
      }
    } catch (e) {
      // Ignore error
    }

    // 2. Individual check (Robustness): Ensure we have the last message for every friend
    // The bulk query might miss edge cases, so we explicitly check each friend
    // Create a copy of the list to avoid concurrent modification
    final friendsList = List<Friend>.from(_friends);
    for (var friend in friendsList) {
      try {
        // Try local DB first
        Message? lastMsg = await _chatService.getLastMessage(friend.id);
        
        // If missing locally, force fetch from API (source of truth)
        if (lastMsg == null) {
            await _chatService.fetchLatestMessage(friend.id);
            // Re-fetch from local DB to verify it was cached and ensure consistency
            // This satisfies "update from the cached data"
            lastMsg = await _chatService.getLastMessage(friend.id);
        }

        if (mounted && lastMsg != null) {
          // Update if we don't have one or if this one is newer/different
          final current = _lastMessages[friend.id];
          if (current == null || lastMsg.id != current.id || lastMsg.date.isAfter(current.date)) {
             setState(() {
               _lastMessages[friend.id] = lastMsg;
               _sortFriends();
             });
          }
        }
      } catch (e) {
        // Ignore
      }
    }
    
    // Sort after initial load
    if (mounted) {
      setState(() {
        _sortFriends();
      });
    }
    
    // 3. Background sync for each friend to get new messages
    for (var friend in friendsList) {
      try {
        // Sync messages (fetches new ones from server)
        final newMessages = await _chatService.syncMessages(friend.id, currentUserId);
        
        // If we got new messages, update the latest message and re-sort
        if (mounted && newMessages.isNotEmpty) {
          // Find the newest message in the batch
          Message? newest;
          for (var msg in newMessages) {
            if (newest == null || msg.date.isAfter(newest.date)) {
              newest = msg;
            }
          }
          
          if (newest != null) {
            setState(() {
              // Only update if it's newer than what we have
              final current = _lastMessages[friend.id];
              if (current == null || newest!.date.isAfter(current.date)) {
                _lastMessages[friend.id] = newest;
                _sortFriends();
              }
            });
          }
        }
      } catch (e) {
        // Silently fail - sync is optional
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.white.withOpacity(0.05),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Colors.white.withOpacity(0.12),
                      child: ListenableBuilder(
                        listenable: TranslationService(),
                        builder: (context, _) {
                          return TextField(
                            decoration: InputDecoration(
                              hintText: TranslationKeys.searchFriends.tr,
                              hintStyle: const TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                              prefixIcon: const Icon(Icons.search, color: Colors.white),
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            style: const TextStyle(color: Colors.white),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: 5, // Show 5 skeleton items
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _SkeletonFriendItem(),
                      );
                    },
                  ),
                )
              else
                Flexible(
                  child: _friends.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: TranslatedText(
                              TranslationKeys.noFriendsFound,
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadFriends,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _friends.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final friend = _friends[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Colors.white.withOpacity(0.2),
                                      child: friend.avatar.isNotEmpty
                                          ? ClipOval(
                                              child: CachedNetworkImage(
                                                imageUrl: UrlHelper.convertUrl(friend.avatar),
                                                width: 44,
                                                height: 44,
                                                fit: BoxFit.cover,
                                                httpHeaders: const {},
                                                placeholder: (context, url) => Image.asset(
                                                  'assets/images/icon.png',
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                ),
                                                errorWidget: (context, url, error) {
                                                  // Handle all errors including 404 (HttpExceptionWithStatus)
                                                  return Image.asset(
                                                    'assets/images/icon.png',
                                                    width: 44,
                                                    height: 44,
                                                    fit: BoxFit.cover,
                                                  );
                                                },
                                              ),
                                            )
                                          : Image.asset(
                                              'assets/images/icon.png',
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                    title: Text(
                                      friend.nickname.isNotEmpty ? friend.nickname : friend.username,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: _getLastMessageText(friend.id),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Unread message count badge
                                        Builder(
                                          builder: (context) {
                                            final unreadCount = _chatMessageCountService.getUnreadCount(friend.id);
                                            if (unreadCount > 0) {
                                              return Container(
                                                margin: const EdgeInsets.only(right: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: friend.getStatusColor(),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          friend.getLastActiveStatus(),
                                          style: TextStyle(
                                            color: friend.getStatusColor(),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      // Clear unread count when opening chat
                                      await _chatMessageCountService.clearUnreadCount(friend.id);
                                      Navigator.of(context).pop(); // Close the modal first
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(
                                            friend: friend,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget? _getLastMessageText(String friendId) {
    final lastMessage = _lastMessages[friendId];
    if (lastMessage != null) {
      // Truncate message if too long
      final messageText = lastMessage.content.length > 50
          ? '${lastMessage.content.substring(0, 50)}...'
          : lastMessage.content;
      
      return Text(
        messageText,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return null;
  }
}

/// Animated skeleton placeholder for friend list items
class _SkeletonFriendItem extends StatefulWidget {
  @override
  State<_SkeletonFriendItem> createState() => _SkeletonFriendItemState();
}

class _SkeletonFriendItemState extends State<_SkeletonFriendItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: _ShimmerWidget(
          controller: _controller,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white.withOpacity(0.2),
          ),
        ),
        title: _ShimmerWidget(
          controller: _controller,
          child: Container(
            height: 16,
            width: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _ShimmerWidget(
            controller: _controller,
            child: Container(
              height: 12,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShimmerWidget(
              controller: _controller,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _ShimmerWidget(
              controller: _controller,
              child: Container(
                height: 12,
                width: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer effect widget
class _ShimmerWidget extends StatelessWidget {
  final AnimationController controller;
  final Widget child;

  const _ShimmerWidget({
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + (controller.value * 2), 0.0),
              end: Alignment(1.0 + (controller.value * 2), 0.0),
              colors: [
                Colors.white.withOpacity(0.3),
                Colors.white.withOpacity(0.6),
                Colors.white.withOpacity(0.3),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: child,
    );
  }
}