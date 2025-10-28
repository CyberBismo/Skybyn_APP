import 'package:flutter/material.dart';
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
import '../widgets/search_form.dart';
import '../widgets/app_colors.dart';
import '../widgets/update_dialog.dart';
import '../config/constants.dart';

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
  // Removed unused _user field
  String? _currentUserId;
  List<Post> _posts = [];
  bool _isLoading = true;

  bool _showInAppNotification = false;
  String _inAppNotificationTitle = '';
  String _inAppNotificationBody = '';
  bool _showSearchForm = false;
  String? _focusedPostId;
  LifecycleEventHandler? _lifecycleEventHandler;

  @override
  void initState() {
    super.initState();
    _loadData();

    // Set up Firebase messaging callback for update notifications
    FirebaseMessagingService.setUpdateCheckCallback(_checkForUpdates);

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
          },
        );
        WidgetsBinding.instance.addObserver(_lifecycleEventHandler!);
      }
    });

    print('🔧 [HomeScreen] Connecting to WebSocket...');
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
            print('Attempting to delete post. Received ID: "$postId" (Type: ${postId.runtimeType})');
            final postIdsInList = _posts.map((p) => 'ID: "${p.id}" (Type: ${p.id.runtimeType})').join(', ');
            print('Current post IDs in list: [$postIdsInList]');
            final initialCount = _posts.length;
            _posts.removeWhere((post) => post.id == postId);
            final finalCount = _posts.length;
            if (initialCount == finalCount) {
              print('Delete failed: No post found with ID "$postId".');
            } else {
              print('Delete successful: Post with ID "$postId" removed.');
            }
          });
        }
      },
      onNewComment: (String postId, String commentId) {
        print('📥 [WebSocket] Received new comment message: postId=$postId, commentId=$commentId');
        _addCommentToPost(postId, commentId);
      },
      onDeleteComment: (String postId, String commentId) {
        print('📥 [WebSocket] Received delete comment message: postId=$postId, commentId=$commentId');
        _removeCommentFromPost(postId, commentId);
      },
      onBroadcast: (String message) {
        if (mounted) {
          final notificationService = NotificationService();
          notificationService.showNotification(
            title: 'Broadcast',
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

  @override
  void dispose() {
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

      print('🔄 Updating post $postId for user $userId');
      final updatedPost = await PostService().fetchPost(postId: postId, userId: userId);

      if (mounted) {
        setState(() {
          final postIndex = _posts.indexWhere((p) => p.id == postId);
          if (postIndex != -1) {
            _posts[postIndex] = updatedPost;
            print('✅ Successfully updated post $postId in feed');
          } else {
            print('⚠️ Post $postId not found in current feed, cannot update');
          }
        });
      }
    } catch (e) {
      print('❌ Error updating post $postId: $e');

      // If the error is due to HTML warnings mixed with JSON, try a different approach
      if (e.toString().contains('HTML without JSON') || e.toString().contains('invalid response format')) {
        print('🔄 Attempting to refresh entire feed due to API response format issues');
        try {
          await _loadData();
          print('✅ Successfully refreshed feed as fallback');
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
        print('Added new post to feed: ${newPost.content}');
      }
    } catch (e) {
      print('Error fetching new post $postId: $e');
      // If fetching fails, show a message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Post created but could not load details: ${e.toString()}'),
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
    print('Removed deleted post from feed: $postId');
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final userId = await _authService.getStoredUserId();
      if (userId != null) {
        // Load user information
        setState(() {
          _currentUserId = userId;
        });

        print('Attempting to fetch posts from timeline API...');
        try {
          _posts = await PostService().fetchPostsForUser(userId: userId).timeout(const Duration(seconds: 15));
          print('Timeline API returned ${_posts.length} posts');
        } catch (timelineError) {
          print('Timeline API Error: $timelineError');
          print('No posts available due to API error');
          _posts = [];
        }

        // If no posts returned from API, show empty state
        if (_posts.isEmpty) {
          print('No posts returned from timeline API, showing empty state');
          _posts = [];
        }
      } else {
        _posts = [];
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        CustomSnackBar.show(context, 'Error loading data: $e');
      }
      print('No posts available due to error');
      _posts = [];
    } finally {
      setState(() {
        _isLoading = false;
      });
      print('Final posts count: ${_posts.length}');
    }
  }

  Future<void> _refreshData() async {
    print('🔄 [HomeScreen] _refreshData() called!');
    try {
      final userId = await _authService.getStoredUserId();
      if (userId != null) {
        print('🔄 [HomeScreen] Refreshing posts from API for user: $userId');
        final newPosts = await PostService().fetchPostsForUser(userId: userId).timeout(const Duration(seconds: 15));

        print('🔄 [HomeScreen] Got ${newPosts.length} posts from API');

        if (mounted) {
          setState(() {
            _posts = newPosts;
          });
          print('✅ [HomeScreen] setState called, posts updated');

          // Show success feedback
          if (newPosts.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Refreshed! Found ${newPosts.length} posts'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Refreshed! No new posts found'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          print('⚠️ [HomeScreen] Widget not mounted, cannot update state');
        }
        print('✅ [HomeScreen] Refresh completed, got ${_posts.length} posts');
      } else {
        print('❌ [HomeScreen] No user ID found for refresh');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in to refresh posts'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [HomeScreen] Error refreshing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: ${e.toString()}'),
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

  void displayInAppNotification(String title, String body) {
    setState(() {
      _inAppNotificationTitle = title;
      _inAppNotificationBody = body;
      _showInAppNotification = true;
    });

    // Auto-hide after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showInAppNotification = false;
        });
      }
    });
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
        print('✅ Successfully removed comment $commentId from post $postId');
      } else {
        print('⚠️ Post $postId not found in current feed, cannot remove comment');
      }
    });
  }

  // Check for app updates
  Future<void> _checkForUpdates() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-updates are only available on Android')),
      );
      return;
    }

    try {
      final updateInfo = await AutoUpdateService.checkForUpdates();

      if (updateInfo != null && updateInfo.isAvailable) {
        // Show update dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => UpdateDialog(
              currentVersion: '1.0.0',
              latestVersion: updateInfo.version,
              releaseNotes: updateInfo.releaseNotes,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No updates available')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking for updates: $e')),
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

      print('🔄 Adding comment $commentId to post $postId');
      print('🔄 User ID: $userId');

      // Try to fetch the new comment data from the API
      try {
        const url = ApiConstants.getComment;
        final body = {'commentID': commentId, 'userID': userId};

        print('🔄 Making request to: $url');
        print('🔄 Request body: $body');

        final response = await http.post(
          Uri.parse(url),
          body: body,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Flutter Mobile App',
          },
        ).timeout(const Duration(seconds: 10));

        print('🔄 Response status: ${response.statusCode}');
        print('🔄 Response headers: ${response.headers}');
        print('🔄 Response body: ${response.body}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('🔄 Parsed data: $data');

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
                  print('✅ Successfully added comment $commentId to post $postId at top');
                } else {
                  print('⚠️ Post $postId not found in current feed, cannot add comment');
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
      print('🔄 Falling back to updating entire post $postId');
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

  @override
  Widget build(BuildContext context) {
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
                print('Post created with ID: $postId, fetching post details...');
                await _fetchAndAddPost(postId);
              }
            },
            onFriendsPressed: () {},
            onChatPressed: _openChatListModal,
            onNotificationsPressed: () {},
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
                  print('🔄 [HomeScreen] RefreshIndicator onRefresh called (empty state)!');
                  await _refreshData();
                },
                color: Colors.white, // White refresh indicator to match theme
                backgroundColor: Colors.transparent, // Transparent background
                strokeWidth: 2.0, // Thinner stroke for better appearance
                displacement: 40.0, // Position the indicator lower
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), // Always allow scrolling for refresh
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height - 200, // Ensure enough height for refresh
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 80.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('No posts to display', style: TextStyle(color: AppColors.getSecondaryTextColor(context), fontSize: 18)),
                            const SizedBox(height: 10),
                            Text('Pull down to refresh', style: TextStyle(color: AppColors.getHintColor(context), fontSize: 14)),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                print('🧪 [Test] Manual SnackBar test');
                                _scaffoldMessengerKey.currentState?.showSnackBar(
                                  const SnackBar(
                                    content: Text('🧪 Test SnackBar'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 3),
                                    behavior: SnackBarBehavior.fixed,
                                  ),
                                );
                              },
                              child: const Text('Test SnackBar'),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () {
                                print('🧪 [Test] Manual notification test');
                                final notificationService = NotificationService();
                                notificationService
                                    .showNotification(
                                  title: 'Test Notification',
                                  body: 'This is a test notification',
                                  payload: 'test',
                                )
                                    .then((_) {
                                  print('🧪 [Test] Manual notification completed');
                                }).catchError((error) {
                                  print('🧪 [Test] Manual notification error: $error');
                                });
                              },
                              child: const Text('Test Notification'),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () {
                                print('🧪 [Test] Manual refresh test');
                                _refreshData();
                              },
                              child: const Text('Test Refresh'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              RefreshIndicator(
                onRefresh: () async {
                  print('🔄 [HomeScreen] RefreshIndicator onRefresh called!');
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
                      ],
                    ),
                  ),
                ),
              ),
            if (_showInAppNotification)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                    child: AnimatedOpacity(
                      opacity: _showInAppNotification ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(33, 150, 243, 1.0),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications, color: AppColors.getIconColor(context), size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _inAppNotificationTitle,
                                      style: TextStyle(
                                        color: AppColors.getSecondaryTextColor(context),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _inAppNotificationBody,
                                      style: TextStyle(
                                        color: AppColors.getSecondaryTextColor(context),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showInAppNotification = false;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                  child: Icon(Icons.close, color: AppColors.getIconColor(context), size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          // Search form overlay
          if (_showSearchForm)
            SearchForm(
              onClose: () {
                setState(() {
                  _showSearchForm = false;
                });
              },
              onSearch: (query) {
                // TODO: Implement search functionality
                print('Search query: $query');
                setState(() {
                  _showSearchForm = false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
