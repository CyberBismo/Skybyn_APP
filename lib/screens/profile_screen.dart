import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../models/post.dart';
import '../widgets/background_gradient.dart';
import '../widgets/post_card.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/chat_list_modal.dart';
import '../widgets/app_colors.dart';
import '../widgets/global_search_overlay.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import 'create_post_screen.dart';
import '../config/constants.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  final String? username;

  const ProfileScreen({super.key, this.userId, this.username});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showSearchForm = false;
  Map<String, dynamic>? userData;
  String? currentUserId;
  String? profileUserId; // Store the userId used to fetch the profile
  bool isLoading = true;
  List<Post> userPosts = [];
  bool isLoadingPosts = false;
  String? _focusedPostId; // Track which post has focused input

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => isLoading = true);
    final authService = AuthService();
    currentUserId = await authService.getStoredUserId();
    String? userId = widget.userId;
    String? username = widget.username;
    // If neither is provided, use current user
    if (userId == null && username == null) {
      userId = currentUserId;
      username = await authService.getStoredUsername();
    }
    
    // Store the userId we're using to fetch the profile
    profileUserId = userId;
    
    final profile = await authService.fetchAnyUserProfile(
      userId: userId,
      username: username,
    );
    setState(() {
      userData = profile?.toJson();
      // Ensure userData has the id field set
      if (userData != null && (userData!['id'] == null || userData!['id'].toString().isEmpty)) {
        if (profileUserId != null) {
          userData!['id'] = profileUserId;
          userData!['userID'] = profileUserId; // Also set for compatibility
        }
      }
      isLoading = false;
    });

    // Load user posts after profile is loaded
    if (userData != null) {
      _loadUserPosts();
    }
  }

  Future<void> _loadUserPosts() async {
    if (userData == null) return;

    // User.toJson() uses 'id' as the key, not 'userID'
    // Try multiple sources: userData['id'], userData['userID'], or the profileUserId we stored
    final targetUserId = userData!['id']?.toString() ?? 
                        userData!['userID']?.toString() ?? 
                        profileUserId?.toString();
    print('🔍 [ProfileScreen] Loading posts for user: $targetUserId');
    print('🔍 [ProfileScreen] userData keys: ${userData!.keys.toList()}');
    print('🔍 [ProfileScreen] userData[id]: ${userData!['id']}');
    print('🔍 [ProfileScreen] userData[userID]: ${userData!['userID']}');
    print('🔍 [ProfileScreen] profileUserId: $profileUserId');
    
    if (targetUserId == null || targetUserId.isEmpty) {
      print('❌ [ProfileScreen] No valid user ID found in userData or profileUserId');
      setState(() {
        userPosts = [];
        isLoadingPosts = false;
      });
      return;
    }
    
    setState(() => isLoadingPosts = true);
    try {
      final postService = PostService();
      // Fetch posts for the specific user whose profile is being viewed
      final posts = await postService.fetchUserTimeline(
        userId: targetUserId ?? '',
        currentUserId: currentUserId,
      );
      
      print('🔍 [ProfileScreen] Received ${posts.length} posts from API');
      
      // The API endpoint (user-timeline.php) should already filter by user
      // Trust the API response, but log for debugging
      for (final post in posts) {
        if (post.userId != null && post.userId != targetUserId) {
          print('⚠️ [ProfileScreen] Post ${post.id} userId mismatch: ${post.userId} != $targetUserId (including anyway - API should filter)');
        }
      }
      
      // Use all posts from API - the endpoint is user-specific
      setState(() {
        userPosts = posts;
        isLoadingPosts = false;
      });
      
      print('🔍 [ProfileScreen] Set ${userPosts.length} posts to display');
    } catch (e, stackTrace) {
      print('❌ [ProfileScreen] Error loading user posts: $e');
      print('❌ [ProfileScreen] Stack trace: $stackTrace');
      setState(() {
        userPosts = [];
        isLoadingPosts = false;
      });
    }
  }

  Future<void> _refreshUserPosts() async {
    await _loadUserPosts();
  }

  void _onPostInputFocused(String postId) {
    setState(() {
      _focusedPostId = postId;
    });
  }

  void _onPostInputUnfocused(String postId) {
    setState(() {
      if (_focusedPostId == postId) {
        _focusedPostId = null;
      }
    });
  }

  bool get isOwnProfile =>
      userData != null &&
      currentUserId != null &&
      (userData!['id']?.toString() ?? userData!['userID']?.toString()) == currentUserId;

  Future<void> _sendFriendAction(String action) async {
    if (currentUserId == null || userData == null) return;
    final friendId = userData!['id']?.toString() ?? userData!['userID']?.toString();
    if (friendId == null || friendId.isEmpty) return;
    final response = await http.post(
      Uri.parse(ApiConstants.friend),
      body: {
        'userID': currentUserId!,
        'friendID': friendId,
        'action': action,
      },
    );
    // Optionally handle response
    if (response.statusCode == 200) {
      // You can show a snackbar or update UI
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarHeight = AppBarConfig.getAppBarHeight(context);

    // Define wallpaper logic safely here
    final String wallpaperUrl = userData?['wallpaper'] as String? ?? '';
    final String avatarUrl = userData?['avatar'] as String? ?? '';
    final bool useDefaultWallpaper =
        wallpaperUrl.isEmpty || wallpaperUrl == avatarUrl;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
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
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS
              ? 8.0
              : 8.0 + MediaQuery.of(context).padding.bottom,
        ),
        child: CustomBottomNavigationBar(
          onStarPressed: () {},
          onAddPressed: () async {
            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                builder: (context, scrollController) => Container(
                  margin: const EdgeInsets.only(top: 100),
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: const CreatePostScreen(),
                ),
              ),
            );
          },
          onFriendsPressed: () {},
          onChatPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const ChatListModal(),
            );
          },
          onNotificationsPressed: () {},
        ),
      ),
      body: Stack(
        children: [
          const BackgroundGradient(),
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (userData != null)
            RefreshIndicator(
              onRefresh: _refreshUserPosts,
              color: Colors.white,
              backgroundColor: Colors.transparent,
              strokeWidth: 2.0,
              displacement: 40.0,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: appBarHeight + MediaQuery.of(context).padding.top,
                    ),
                  ),
                  // --- Static Profile Header ---
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 250,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // --- GUARANTEED CORRECT WALLPAPER ---
                          Positioned.fill(
                            child: useDefaultWallpaper
                                ? const SizedBox.shrink()
                                : CachedNetworkImage(
                                    imageUrl: wallpaperUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.black),
                                    errorWidget: (context, url, error) =>
                                        const SizedBox.shrink(),
                                  ),
                          ),
                          // --- Avatar ---
                          Positioned(
                            top: 20,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: AppColors.getIconColor(context),
                                    width: 3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: (avatarUrl.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: avatarUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Image.asset(
                                            'assets/images/icon.png',
                                            fit: BoxFit.cover),
                                        errorWidget: (context, url, error) =>
                                            Image.asset('assets/images/icon.png',
                                                fit: BoxFit.cover),
                                      )
                                    : Image.asset('assets/images/icon.png',
                                        fit: BoxFit.cover),
                              ),
                            ),
                          ),
                          // --- Text ---
                          Positioned(
                            top: 20 + 120 + 12,
                            child: Column(
                              children: [
                                Text(
                                  userData!['username'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                          blurRadius: 4,
                                          color: Colors.black54,
                                          offset: Offset(1, 1))
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '@${userData!['username']}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // --- Post Feed ---
                  if (isLoadingPosts)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (userPosts.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: TranslatedText(
                            TranslationKeys.noPostsYet,
                            style: const TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10.0, right: 10.0),
                        child: Column(
                          children: [
                            for (final post in userPosts) ...[
                              const SizedBox(height: 10),
                              PostCard(
                                key: ValueKey(post.id),
                                post: post,
                                currentUserId: currentUserId,
                                onPostDeleted: (postId) {
                                  setState(() {
                                    userPosts
                                        .removeWhere((p) => p.id == postId);
                                  });
                                },
                                onPostUpdated: (postId) {
                                  // Refresh the specific post or reload all posts
                                  _loadUserPosts();
                                },
                                onInputFocused: () => _onPostInputFocused(post.id),
                                onInputUnfocused: () => _onPostInputUnfocused(post.id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child:
                        SizedBox(height: 130), // Restore space for bottom nav bar
                  ),
                ],
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
        ],
      ),
    );
  }
}
