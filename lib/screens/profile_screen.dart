import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../models/post.dart';
import '../widgets/background_gradient.dart';
import '../widgets/post_card.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/chat_list_modal.dart';
import '../widgets/search_form.dart';
import '../widgets/app_colors.dart';
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
  bool isLoading = true;
  List<Post> userPosts = [];
  bool isLoadingPosts = false;

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
    final profile = await authService.fetchAnyUserProfile(
      userId: userId,
      username: username,
    );
    setState(() {
      userData = profile?.toJson();
      isLoading = false;
    });

    // Load user posts after profile is loaded
    if (userData != null) {
      _loadUserPosts();
    }
  }

  Future<void> _loadUserPosts() async {
    if (userData == null) return;

    setState(() => isLoadingPosts = true);
    try {
      final postService = PostService();
      final posts = await postService.fetchUserTimeline(
        userId: userData!['userID'],
        currentUserId: currentUserId,
      );
      setState(() {
        userPosts = posts;
        isLoadingPosts = false;
      });
    } catch (e) {
      print('Error loading user posts: $e');
      setState(() {
        userPosts = [];
        isLoadingPosts = false;
      });
    }
  }

  bool get isOwnProfile =>
      userData != null &&
      currentUserId != null &&
      userData!['userID'] == currentUserId;

  Future<void> _sendFriendAction(String action) async {
    if (currentUserId == null || userData == null) return;
    final response = await http.post(
      Uri.parse(ApiConstants.friend),
      body: {
        'userID': currentUserId!,
        'friendID': userData!['userID'],
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
        onLogout: () {},
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
            CustomScrollView(
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
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: TranslatedText(
                          TranslationKeys.noPostsYet,
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: PostCard(
                          post: userPosts[index],
                          currentUserId: currentUserId,
                          onPostDeleted: (postId) {
                            setState(() {
                              userPosts
                                  .removeWhere((post) => post.id == postId);
                            });
                          },
                          onPostUpdated: (postId) {
                            // Refresh the specific post or reload all posts
                            _loadUserPosts();
                          },
                        ),
                      ),
                      childCount: userPosts.length,
                    ),
                  ),
                const SliverToBoxAdapter(
                  child:
                      SizedBox(height: 130), // Restore space for bottom nav bar
                ),
              ],
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
    );
  }
}
