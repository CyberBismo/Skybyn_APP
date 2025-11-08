import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../widgets/background_gradient.dart';
import '../widgets/post_card.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/custom_snack_bar.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/notification_service.dart';
import '../services/websocket_service.dart';
import '../services/auto_update_service.dart';
import '../services/firebase_messaging_service.dart';
import 'create_post_screen.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../widgets/chat_list_modal.dart';
import '../widgets/friends_modal.dart';
import '../widgets/find_friends_widget.dart';
import '../services/friend_service.dart';
import '../widgets/search_form.dart';
import '../widgets/app_colors.dart';
import '../widgets/global_search_overlay.dart';
import '../widgets/update_dialog.dart';
import '../widgets/notification_overlay.dart';
import '../config/constants.dart';
import '../services/translation_service.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Lifecycle event handler for keyboard-aware scrolling
class LifecycleEventHandler extends WidgetsBindingObserver {
  final Future<void> Function()? detachedCallBack;
  final Future<void> Function()? inactiveCallBack;
  final Future<void> Function()? pausedCallBack;
  final Future<void> Function()? resumedCallBack;

  LifecycleEventHandler({
    this.detachedCallBack,
    this.inactiveCallBack,
    this.pausedCallBack,
    this.resumedCallBack,
  });

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.detached:
        if (detachedCallBack != null) await detachedCallBack!();
        break;
      case AppLifecycleState.inactive:
        if (inactiveCallBack != null) await inactiveCallBack!();
        break;
      case AppLifecycleState.paused:
        if (pausedCallBack != null) await pausedCallBack!();
        break;
      case AppLifecycleState.resumed:
        if (resumedCallBack != null) await resumedCallBack!();
        break;
      default:
        break;
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _webSocketService = WebSocketService();
  final _scrollController = ScrollController();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  static const MethodChannel _notificationChannel = MethodChannel('no.skybyn.app/notification');
  // Removed unused _user field
  String? _currentUserId;
  List<Post> _posts = [];
  bool _isLoading = true;
  int _friendsCount = -1; // -1 means not loaded yet
  bool _showFindFriendsBox = false;
  bool _findFriendsBoxDismissed = false; // Track if user dismissed the box
  int _findFriendsBoxResetCounter = 0; // Counter to force widget reset when box reappears
  Timer? _findFriendsTimer;

  bool _showSearchForm = false;
  String? _focusedPostId;
  LifecycleEventHandler? _lifecycleEventHandler;
  bool _showNotificationOverlay = false;
  int _unreadNotificationCount = 0;
  bool _showNoPostsMessage = false;
  Timer? _noPostsTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchUnreadNotificationCount();
    _loadFriendsCount();

    // Set up Firebase messaging callback for update notifications
    FirebaseMessagingService.setUpdateCheckCallback(_checkForUpdates);
    
    // Check if app was opened from notification
    _checkNotificationIntent();

    // Listen to keyboard visibility changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Add listener for keyboard visibility changes
        _lifecycleEventHandler = LifecycleEventHandler(
          detachedCallBack: () async {},
          inactiveCallBack: () async {},
          pausedCallBack: () async {},
          resumedCallBack: () async {
            // Re-scroll to focused post when app resumes
            if (_focusedPostId != null) {
              _scrollToFocusedPost();
            }
            // Check for notification intent when app resumes
            _checkNotificationIntent();
          },
        );
        WidgetsBinding.instance.addObserver(_lifecycleEventHandler!);
      }
    });

    _webSocketService.connect(
      onAppUpdate: _checkForUpdates,
      onNewPost: (Post newPost) {
        if (mounted) {
          setState(() {
            if (!_posts.any((post) => post.id == newPost.id)) {
              _posts.insert(0, newPost);
            }
          });
        }
      },
      onDeletePost: (String postId) {
        if (mounted) {
          setState(() {
            _posts.removeWhere((post) => post.id == postId);
          });
        }
      },
      onNewComment: (String postId, String commentId) {
        _addCommentToPost(postId, commentId);
      },
      onDeleteComment: (String postId, String commentId) {
        _removeCommentFromPost(postId, commentId);
      },
      onBroadcast: (String message) {
        if (mounted) {
          final translationService = TranslationService();
          final notificationService = NotificationService();
          notificationService.showNotification(
            title: translationService.translate('broadcast'),
            body: message,
            payload: 'broadcast',
          );

          // For iOS Simulator, also show a SnackBar as fallback
          if (Platform.isIOS) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text('📢 Broadcast: $message'),
                    backgroundColor: Colors.blue,
                    duration: const Duration(seconds: 5),
                    behavior: SnackBarBehavior.fixed,
                  ),
                );
              }
            });
          }
        }
      },
    );
  }

  void _startNoPostsTimer() {
    _noPostsTimer?.cancel();
    _showNoPostsMessage = false;
    
    if (_posts.isEmpty && !_isLoading) {
      _noPostsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _posts.isEmpty && !_isLoading) {
          setState(() {
            _showNoPostsMessage = true;
          });
        }
      });
    }
  }

  void _stopNoPostsTimer() {
    _noPostsTimer?.cancel();
    _noPostsTimer = null;
    _showNoPostsMessage = false;
  }

  @override
  void dispose() {
    _noPostsTimer?.cancel();
    _findFriendsTimer?.cancel();
    _webSocketService.disconnect();
    _scrollController.dispose();
    if (_lifecycleEventHandler != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleEventHandler!);
    }
    super.dispose();
  }

  Future<void> _updatePost(String postId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        print('❌ Cannot update post $postId: No user ID found');
        return;
      }

      final updatedPost = await PostService().fetchPost(postId: postId, userId: userId);

      if (mounted) {
        setState(() {
          final postIndex = _posts.indexWhere((p) => p.id == postId);
          if (postIndex != -1) {
            _posts[postIndex] = updatedPost;
          }
        });
      }
    } catch (e) {
      print('❌ Error updating post $postId: $e');

      // If the error is due to HTML warnings mixed with JSON, try a different approach
      if (e.toString().contains('HTML without JSON') || e.toString().contains('invalid response format')) {
        try {
          await _loadData();
        } catch (refreshError) {
          print('❌ Feed refresh also failed: $refreshError');
        }
      }
      // Don't show error to user for real-time updates, just log it
      // The post will remain in its current state
    }
  }

  Future<void> _fetchAndAddPost(String postId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      final newPost = await PostService().fetchPost(postId: postId, userId: userId);
      if (mounted) {
        setState(() {
          // Add the new post to the beginning of the list
          _posts.insert(0, newPost);
        });
      }
    } catch (e) {
      print('Error fetching new post $postId: $e');
      // If fetching fails, show a message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text('${TranslationKeys.postCreatedButCouldNotLoadDetails.tr}: ${e.toString()}'),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _handlePostDeleted(String postId) {
    setState(() {
      // Remove the deleted post from the list
      _posts.removeWhere((post) => post.id == postId);
    });
  }

  Future<void> _loadData() async {
    final userId = await _authService.getStoredUserId();
    if (userId == null) {
      setState(() {
        _posts = [];
        _isLoading = false;
        _currentUserId = null;
      });
      return;
    }

    // Set user ID immediately
    setState(() {
      _currentUserId = userId;
    });

    // Load cached posts first (fast, non-blocking)
    final postService = PostService();
    try {
      // Try to get cached posts immediately
      final cachedPosts = await postService.loadTimelineFromCache();
      if (cachedPosts.isNotEmpty && mounted) {
        setState(() {
          _posts = cachedPosts;
          _isLoading = false; // Show cached data immediately
        });
        _stopNoPostsTimer();
      } else {
        setState(() => _isLoading = true);
      }
    } catch (e) {
      setState(() => _isLoading = true);
    }

    // Fetch fresh data in background
    try {
      final freshPosts = await postService.fetchPostsForUser(userId: userId).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _posts = freshPosts;
          _isLoading = false;
        });
        if (_posts.isEmpty) {
          _startNoPostsTimer();
        } else {
          _stopNoPostsTimer();
        }
      }
    } catch (timelineError) {
      print('⚠️ [HomeScreen] Error loading fresh posts: $timelineError');
      // If we don't have cached posts and fetch fails, show empty state
      if (mounted && _posts.isEmpty) {
        setState(() {
          _posts = [];
          _isLoading = false;
        });
        _startNoPostsTimer();
      }
    }
  }

  Future<void> _refreshData() async {
    final translationService = TranslationService();

    try {
      final userId = await _authService.getStoredUserId();
      if (userId != null) {
        // Store old post count for comparison
        final oldPostCount = _posts.length;
        
        // Clear cache to force fresh data
        final postService = PostService();
        await postService.clearTimelineCache();
        
        // Reset dismissed flag so box can show again after refresh
        _findFriendsBoxDismissed = false;
        // Increment reset counter to force widget rebuild with fresh state
        _findFriendsBoxResetCounter++;
        
        // Also refresh notification count and friends count
        _fetchUnreadNotificationCount();
        _loadFriendsCount(); // Reload friends count to check if box should show again
        
        final newPosts = await postService.fetchPostsForUser(userId: userId).timeout(const Duration(seconds: 15));

        if (mounted) {
          setState(() {
            _posts = newPosts;
            _isLoading = false;
          });

          if (_posts.isEmpty) {
            _startNoPostsTimer();
          } else {
            _stopNoPostsTimer();
          }

          // Show success feedback only if there's a significant change
          // (optional - can be removed if too noisy)
          if (newPosts.length != oldPostCount) {
            if (newPosts.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(translationService.translate('refreshed_found_posts').replaceAll('{count}', newPosts.length.toString())),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translationService.translate('please_login_to_refresh')),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [HomeScreen] Error refreshing data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${translationService.translate('failed_to_refresh')}: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // Method to handle when a post's input field gains focus
  void _onPostInputFocused(String postId) {
    setState(() {
      _focusedPostId = postId;
    });

    // Scroll to the focused post after a short delay to allow keyboard to appear
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _focusedPostId == postId) {
        _scrollToFocusedPost();
      }
    });
  }

  // Method to handle when a post's input field loses focus
  void _onPostInputUnfocused(String postId) {
    if (_focusedPostId == postId) {
      setState(() {
        _focusedPostId = null;
      });
    }
  }

  // Scroll to the focused post
  void _scrollToFocusedPost() {
    if (_focusedPostId == null || !_scrollController.hasClients) return;

    final postIndex = _posts.indexWhere((post) => post.id == _focusedPostId);
    if (postIndex == -1) return;

    // Wait for the next frame to ensure layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusedPostId == null) return;

      // Calculate the position to scroll to
      // Each post takes approximately 200-300 pixels, plus spacing
      const estimatedPostHeight = 250.0;
      const estimatedSpacing = 20.0;
      final targetPosition = postIndex * (estimatedPostHeight + estimatedSpacing);

      // Add some padding to ensure the input is visible above the keyboard
      final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      final additionalPadding = keyboardHeight > 0 ? 150.0 : 50.0;

      final finalPosition = (targetPosition + additionalPadding).clamp(0.0, _scrollController.position.maxScrollExtent);

      _scrollController.animateTo(
        finalPosition,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _removeCommentFromPost(String postId, String commentId) {
    setState(() {
      final postIndex = _posts.indexWhere((p) => p.id == postId);
      if (postIndex != -1) {
        _posts[postIndex].commentsList.removeWhere((c) => c.id == commentId);
      }
    });
  }

  /// Check if app was opened from a notification and handle accordingly
  Future<void> _checkNotificationIntent() async {
    if (!Platform.isAndroid) {
      return; // Only Android supports this
    }
    
    try {
      final notificationType = await _notificationChannel.invokeMethod<String>('getNotificationType');
      
      if (notificationType == 'app_update') {
        // Skip app update notifications in debug mode
        if (kDebugMode) {
          print('⚠️ [HomeScreen] App update notification ignored in debug mode');
          return;
        }
        print('📱 [HomeScreen] App opened from app_update notification - showing update dialog');
        // Wait for next frame to ensure UI is ready
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted) {
              await _checkForUpdates();
            }
          }
        });
      }
    } catch (e) {
      // Method channel might not be available, ignore silently
      print('⚠️ [HomeScreen] Could not check notification intent: $e');
    }
  }

  // Check for app updates
  Future<void> _checkForUpdates() async {
    // Skip app update checks in debug mode
    if (kDebugMode) {
      print('⚠️ [HomeScreen] Update check ignored in debug mode');
      return;
    }

    final translationService = TranslationService();

    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translationService.translate('auto_updates_only_android'))),
      );
      return;
    }

    // Prevent multiple dialogs from showing at once
    if (AutoUpdateService.isDialogShowing) {
      print('⚠️ [HomeScreen] Update dialog already showing, skipping...');
      return;
    }

    try {
      final updateInfo = await AutoUpdateService.checkForUpdates();

      if (updateInfo != null && updateInfo.isAvailable) {
        // Show update dialog if not already showing
        if (mounted && !AutoUpdateService.isDialogShowing) {
          // Mark dialog as showing immediately to prevent duplicates
          AutoUpdateService.setDialogShowing(true);
          
          // Get current version
          final packageInfo = await PackageInfo.fromPlatform();
          final currentVersion = packageInfo.version;
          
          // Mark this version as shown (so we don't spam the user)
          await AutoUpdateService.markUpdateShownForVersion(updateInfo.version);
          
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => UpdateDialog(
              currentVersion: currentVersion,
              latestVersion: updateInfo.version,
              releaseNotes: updateInfo.releaseNotes,
              downloadUrl: updateInfo.downloadUrl,
            ),
          ).then((_) {
            // Dialog closed, mark as not showing
            AutoUpdateService.setDialogShowing(false);
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(translationService.translate('no_updates_available'))),
          );
        }
      }
    } catch (e) {
      // Mark dialog as not showing on error
      AutoUpdateService.setDialogShowing(false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${translationService.translate('error_checking_updates')}: $e')),
        );
      }
    }
  }

  Future<void> _addCommentToPost(String postId, String commentId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        print('❌ Cannot add comment to post $postId: No user ID found');
        return;
      }

      // Try to fetch the new comment data from the API
      try {
        final url = ApiConstants.getComment;
        final body = {'commentID': commentId, 'userID': userId};

        final response = await http.post(
          Uri.parse(url),
          body: body,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Flutter Mobile App',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data is List && data.isNotEmpty && data.first['responseCode'] == '1') {
            final commentData = data.first;
            final comment = Comment(
              id: commentData['id'].toString(),
              userId: commentData['user'].toString(),
              username: commentData['username'] ?? 'Unknown',
              avatar: commentData['avatar'] ?? '',
              content: commentData['content'] ?? '',
            );

            if (mounted) {
              setState(() {
                final postIndex = _posts.indexWhere((p) => p.id == postId);
                if (postIndex != -1) {
                  // Add the new comment to the top of the comment section
                  _posts[postIndex].commentsList.insert(0, comment);
                }
              });
            }
            return; // Success, no need to fallback
          } else {
            print('❌ API returned error for comment $commentId: ${data.first['message'] ?? 'Unknown error'}');
          }
        } else {
          print('❌ HTTP error ${response.statusCode} when fetching comment $commentId');
        }
      } catch (e) {
        print('❌ Error fetching comment $commentId: $e');
      }

      // Fallback: Update the entire post to get the latest comments
      await _updatePost(postId);
    } catch (e) {
      print('❌ Error adding comment $commentId to post $postId: $e');
      // Final fallback: try to update the post
      try {
        await _updatePost(postId);
      } catch (updateError) {
        print('❌ Final fallback also failed: $updateError');
      }
    }
  }

  void _openChatListModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ChatListModal(),
    );
  }

  void _openFriendsModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const FriendsModal();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0), // Start from right
          end: Offset.zero, // End at center
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ));
        
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
    );
  }

  Future<void> _loadFriendsCount() async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        if (mounted) {
          setState(() {
            _friendsCount = 0;
          });
          _startFindFriendsTimer();
        }
        return;
      }

      final friendService = FriendService();
      final friends = await friendService.fetchFriendsForUser(userId: userId);
      if (mounted) {
        setState(() {
          _friendsCount = friends.length;
        });
        print('✅ [HomeScreen] Friends count loaded: $_friendsCount');
        if (_friendsCount <= 0) {
          _startFindFriendsTimer();
        } else {
          _stopFindFriendsTimer();
        }
      }
    } catch (e) {
      print('⚠️ [HomeScreen] Error loading friends count: $e');
      if (mounted) {
        setState(() {
          _friendsCount = 0;
        });
        _startFindFriendsTimer();
      }
    }
  }

  void _startFindFriendsTimer() {
    _findFriendsTimer?.cancel();
    _showFindFriendsBox = false;
    
    // Don't show if user dismissed it (will only show again after refresh)
    if (_findFriendsBoxDismissed) {
      return;
    }
    
    // Show the find friends box after 2 seconds delay
    _findFriendsTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _friendsCount <= 0 && !_isLoading && !_findFriendsBoxDismissed) {
        setState(() {
          _showFindFriendsBox = true;
        });
      }
    });
  }

  void _stopFindFriendsTimer() {
    _findFriendsTimer?.cancel();
    _findFriendsTimer = null;
    if (mounted) {
      setState(() {
        _showFindFriendsBox = false;
      });
    }
  }

  Future<void> _fetchUnreadNotificationCount() async {
    final userId = await _authService.getStoredUserId();
    if (userId == null || !mounted) return;

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.notificationCount),
        body: {'userID': userId},
      );

      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _unreadNotificationCount = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  void _toggleNotificationOverlay() {
    setState(() {
      _showNotificationOverlay = !_showNotificationOverlay;
    });
    if (!_showNotificationOverlay) {
      // If closing, refresh count
      _fetchUnreadNotificationCount();
    }
  }

  void _closeNotificationOverlay() {
    setState(() {
      _showNotificationOverlay = false;
    });
    _fetchUnreadNotificationCount(); // Refresh count after closing
  }

  void _onUnreadCountChanged(int count) {
    if (mounted) {
      setState(() {
        _unreadNotificationCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final translationService = TranslationService();

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: CustomAppBar(
          logoPath: 'assets/images/logo.png',
          onLogout: _handleLogout,
          onLogoPressed: () {
            // Force refresh data when logo is pressed
            _refreshData();
          },
          onSearchFormToggle: () {
            setState(() {
              _showSearchForm = !_showSearchForm;
            });
          },
          isSearchFormVisible: _showSearchForm,
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: Theme.of(context).platform == TargetPlatform.iOS ? 8.0 : 8.0 + MediaQuery.of(context).padding.bottom,
          ),
          child: CustomBottomNavigationBar(
            onStarPressed: () {},
            onAddPressed: () async {
              final postId = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.7,
                  minChildSize: 0.4,
                  maxChildSize: 0.9,
                  builder: (context, scrollController) => Container(
                    margin: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 60, // Account for status bar and app bar
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom, // Account for keyboard
                      ),
                      child: const CreatePostScreen(),
                    ),
                  ),
                ),
              );

              // If a post was created, fetch the specific post
              if (postId != null) {
                await _fetchAndAddPost(postId);
              }
            },
            onFriendsPressed: _openFriendsModal,
            onChatPressed: _openChatListModal,
            onNotificationsPressed: _toggleNotificationOverlay,
            unreadNotificationCount: _unreadNotificationCount,
          ),
        ),
        body: Stack(
          children: [
            const BackgroundGradient(),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_posts.isEmpty)
              RefreshIndicator(
                onRefresh: () async {
                  _stopNoPostsTimer();
                  await _refreshData();
                },
                color: Colors.white, // White refresh indicator to match theme
                backgroundColor: Colors.transparent, // Transparent background
                strokeWidth: 2.0, // Thinner stroke for better appearance
                displacement: 40.0, // Position the indicator lower
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), // Always allow scrolling for refresh
                  padding: EdgeInsets.only(
                    top: 60.0 + MediaQuery.of(context).padding.top + 5.0, // App bar height + status bar + 5px gap (matches posts)
                    bottom: 80.0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10.0, right: 10.0),
                    child: _showNoPostsMessage
                        ? SizedBox(
                            height: MediaQuery.of(context).size.height - 200,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    TranslationService().translate('no_posts_display'),
                                    style: TextStyle(
                                      color: AppColors.getSecondaryTextColor(context),
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    TranslationService().translate('pull_to_refresh'),
                                    style: TextStyle(
                                      color: AppColors.getHintColor(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (int index = 0; index < 3; index++) ...[
                                const SizedBox(height: 10),
                                _SkeletonPostCard(),
                              ],
                            ],
                          ),
                  ),
                ),
              )
            else
              RefreshIndicator(
                onRefresh: () async {
                  await _refreshData();
                },
                color: Colors.white, // White refresh indicator to match theme
                backgroundColor: Colors.transparent, // Transparent background
                strokeWidth: 2.0, // Thinner stroke for better appearance
                displacement: 40.0, // Position the indicator lower
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(), // Always allow scrolling for refresh
                  padding: EdgeInsets.only(
                    top: 60.0 + MediaQuery.of(context).padding.top + 5.0, // App bar height + status bar + 5px gap (reduced to prevent overlap)
                    bottom: 80.0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10.0, right: 10.0),
                    child: Column(
                      children: [
                        for (final post in _posts) ...[
                          const SizedBox(height: 10),
                          PostCard(key: ValueKey(post.id), post: post, currentUserId: _currentUserId, onPostDeleted: _handlePostDeleted, onPostUpdated: _updatePost, onInputFocused: () => _onPostInputFocused(post.id), onInputUnfocused: () => _onPostInputUnfocused(post.id)),
                        ],
                        // Add extra space at bottom to ensure pull-to-refresh works even with few posts
                        // Also add space for the Find Friends overlay if it's shown
                        SizedBox(height: _friendsCount <= 0 ? 200.0 : MediaQuery.of(context).size.height * 0.1),
                      ],
                    ),
                  ),
                ),
              ),
            // Global search overlay
            GlobalSearchOverlay(
              isVisible: _showSearchForm,
              onClose: () {
                setState(() {
                  _showSearchForm = false;
                });
              },
            ),
            // Notification overlay
            if (_showNotificationOverlay)
              GestureDetector(
                onTap: _closeNotificationOverlay,
                child: NotificationOverlay(
                  onClose: _closeNotificationOverlay,
                  onUnreadCountChanged: _onUnreadCountChanged,
                ),
              ),
            // Find Friends overlay at the bottom (with delay)
            // Always render but use Offstage to keep in tree and preserve state
            Positioned(
              left: 0,
              right: 0,
              bottom: 80.0 + (Theme.of(context).platform == TargetPlatform.iOS ? 8.0 : 8.0 + MediaQuery.of(context).padding.bottom),
              child: Offstage(
                offstage: !(_showFindFriendsBox && _friendsCount <= 0 && !_isLoading),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: FindFriendsWidget(
                    key: ValueKey('find_friends_$_findFriendsBoxResetCounter'),
                    onLocationUpdated: () {
                      // Don't refresh friends count immediately to avoid unmounting widget
                      // It will be refreshed naturally when needed
                    },
                    onDismiss: () {
                      setState(() {
                        _showFindFriendsBox = false;
                        _findFriendsBoxDismissed = true; // Mark as dismissed
                      });
                      _stopFindFriendsTimer(); // Stop any pending timer
                    },
                    onFriendsFound: () {
                      // Refresh friends count when a friend is added (delayed to avoid unmounting)
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          _loadFriendsCount();
                        }
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated skeleton placeholder for post cards
class _SkeletonPostCard extends StatefulWidget {
  @override
  State<_SkeletonPostCard> createState() => _SkeletonPostCardState();
}

class _SkeletonPostCardState extends State<_SkeletonPostCard>
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
        color: PostCardStyles.getCardBackgroundColor(context),
        borderRadius: BorderRadius.circular(PostCardStyles.cardRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PostCardStyles.cardRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: PostCardStyles.blurSigma,
            sigmaY: PostCardStyles.blurSigma,
          ),
          child: Padding(
            padding: PostCardStyles.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with avatar and username
                Row(
                  children: [
                    _ShimmerWidget(
                      controller: _controller,
                      child: Container(
                        width: PostCardStyles.avatarSize,
                        height: PostCardStyles.avatarSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(PostCardStyles.avatarRadius),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerWidget(
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
                          const SizedBox(height: 8),
                          _ShimmerWidget(
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
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                // Content lines
                _ShimmerWidget(
                  controller: _controller,
                  child: Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ShimmerWidget(
                  controller: _controller,
                  child: Container(
                    height: 14,
                    width: MediaQuery.of(context).size.width * 0.7,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ShimmerWidget(
                  controller: _controller,
                  child: Container(
                    height: 14,
                    width: MediaQuery.of(context).size.width * 0.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ShimmerWidget(
                      controller: _controller,
                      child: Container(
                        height: 20,
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    _ShimmerWidget(
                      controller: _controller,
                      child: Container(
                        height: 20,
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    _ShimmerWidget(
                      controller: _controller,
                      child: Container(
                        height: 20,
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
