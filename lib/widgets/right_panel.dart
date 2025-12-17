import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/friend_service.dart';
import '../services/auth_service.dart';
import '../services/firebase_realtime_service.dart';
import '../services/websocket_service.dart';
import '../models/friend.dart';
import '../screens/profile_screen.dart';
import '../services/translation_service.dart';
import 'find_friends_widget.dart';
import '../config/constants.dart';

class RightPanel extends StatefulWidget {
  const RightPanel({super.key});

  @override
  State<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends State<RightPanel> {
  final FriendService _friendService = FriendService();
  final AuthService _authService = AuthService();
  final FirebaseRealtimeService _firebaseRealtimeService = FirebaseRealtimeService();
  final WebSocketService _webSocketService = WebSocketService();

  List<Friend> _friends = [];
  bool _isLoading = true;
  bool _showFindFriendsBox = false;
  int _findFriendsBoxResetCounter = 0;

  // Store subscriptions for cleanup
  final Map<String, StreamSubscription> _onlineStatusSubscriptions = {};
  // Store WebSocket online status callback for cleanup
  void Function(String, bool)? _webSocketOnlineStatusCallback;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _setupWebSocketListener();
  }

  @override
  void dispose() {
    // Cancel all online status subscriptions when widget is disposed
    for (var subscription in _onlineStatusSubscriptions.values) {
      subscription.cancel();
    }
    _onlineStatusSubscriptions.clear();
    // Remove WebSocket online status callback when widget is disposed
    if (_webSocketOnlineStatusCallback != null) {
      _webSocketService.removeOnlineStatusCallback(_webSocketOnlineStatusCallback!);
      _webSocketOnlineStatusCallback = null;
    }
    super.dispose();
  }

  void _setupWebSocketListener() {
    // Set up Firebase online status listeners for all friends (fallback)
    for (var friend in _friends) {
      _setupOnlineStatusListenerForFriend(friend.id);
    }

    // Set up WebSocket online status listener (primary real-time source)
    // This single callback handles all friends' online status updates
    _webSocketOnlineStatusCallback = (userId, isOnline) {
      if (mounted) {
        setState(() {
          final index = _friends.indexWhere((f) => f.id == userId);
          if (index != -1) {
            final oldStatus = _friends[index].online;
            _friends[index] = _friends[index].copyWith(online: isOnline);
          }
        });
      }
    };
    
    // Register callback with WebSocket service
    _webSocketService.connect(
      onOnlineStatus: _webSocketOnlineStatusCallback,
    );
  }

  void _setupOnlineStatusListenerForFriend(String friendId) {
    // Cancel existing subscription if any
    _onlineStatusSubscriptions[friendId]?.cancel();
    
    // Set up Firebase listener for this friend
    _onlineStatusSubscriptions[friendId] = _firebaseRealtimeService.setupOnlineStatusListener(
      friendId,
      (userId, isOnline) {
        if (mounted) {
          setState(() {
            final index = _friends.indexWhere((f) => f.id == userId);
            if (index != -1) {
              final oldStatus = _friends[index].online;
              _friends[index] = _friends[index].copyWith(online: isOnline);
            }
          });
        }
      },
    );
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
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _isLoading = false;
    });
    
    // Set up Firebase online status listeners for all friends
    for (var friend in _friends) {
      _setupOnlineStatusListenerForFriend(friend.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions once - these won't change during animation
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    const appBarHeight = 60.0;
    final statusBarHeight = mediaQuery.padding.top;
    const bottomNavHeight = 80.0;
    final bottomPadding = Theme.of(context).platform == TargetPlatform.iOS 
        ? 8.0 
        : 8.0 + mediaQuery.padding.bottom;
    // Height = screen height - header (appBar + statusBar) - bottom nav (bottomNav + bottomPadding)
    final modalHeight = screenHeight - 
        (appBarHeight + statusBarHeight) - 
        (bottomNavHeight + bottomPadding);
    final modalWidth = screenWidth * 0.9;
    
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: appBarHeight + statusBarHeight,
        ),
        child: SizedBox(
          width: modalWidth,
          height: modalHeight,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.white.withOpacity(0.05),
                child: Column(
                  children: [
                    // Title with find friends button and close button
                    Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.my_location, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _showFindFriendsBox = !_showFindFriendsBox;
                              if (_showFindFriendsBox) {
                                _findFriendsBoxResetCounter++;
                              }
                            });
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: ListenableBuilder(
                              listenable: TranslationService(),
                              builder: (context, _) {
                                return Text(
                                  TranslationService().translate('friends'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                    // Find Friends box
                    if (_showFindFriendsBox)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: FindFriendsWidget(
                          key: ValueKey('find_friends_$_findFriendsBoxResetCounter'),
                          onFriendsFound: () {
                            // Refresh friends list when a friend is added
                            Future.delayed(const Duration(milliseconds: 500), () {
                              if (mounted) {
                                _loadFriends();
                              }
                            });
                          },
                          onDismiss: () {
                            setState(() {
                              _showFindFriendsBox = false;
                            });
                          },
                        ),
                      ),
                    // Content area
                    Expanded(
                    child: _isLoading
                        ? ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: 5, // Show 5 skeleton items
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              return _SkeletonFriendItem();
                            },
                          )
                        : _friends.isEmpty
                            ? const SizedBox.shrink()
                            : RefreshIndicator(
                                onRefresh: _loadFriends,
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: _friends.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final friend = _friends[index];
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
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
                                                    placeholder: (context, url) => Container(
                                                      color: Colors.white.withOpacity(0.1),
                                                    ),
                                                    errorWidget: (context, url, error) {
                                                      // Handle all errors including 404 (HttpExceptionWithStatus)
                                                      return const Icon(
                                                        Icons.person,
                                                        color: Colors.white,
                                                      );
                                                    },
                                                  ),
                                                )
                                              : const Icon(Icons.person, color: Colors.white),
                                        ),
                                        title: Text(
                                          friend.nickname.isNotEmpty ? friend.nickname : friend.username,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                        subtitle: Text(
                                          friend.getLastActiveStatus(),
                                          style: TextStyle(
                                            color: friend.getStatusColor(),
                                            fontSize: 12,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: friend.getStatusColor(),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.chevron_right, color: Colors.white70),
                                          ],
                                        ),
                                        onTap: () {
                                          Navigator.of(context).pop();
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => ProfileScreen(
                                                userId: friend.id,
                                                username: friend.username,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
      child: Material(
        color: Colors.transparent,
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

