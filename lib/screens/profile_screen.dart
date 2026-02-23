import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../models/post.dart';
import '../models/user.dart';
import '../widgets/background_gradient.dart';
import '../widgets/post_card.dart';
import '../widgets/header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/app_colors.dart';
import '../widgets/global_search_overlay.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import 'create_post_screen.dart';
import '../config/constants.dart';

import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../widgets/skeleton_loader.dart';
import 'chat_screen.dart';
import 'package:share_plus/share_plus.dart';
import '../models/friend.dart';

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
  final GlobalKey _notificationButtonKey = GlobalKey();
  String? _friendshipStatus; // 'none', 'sent', 'received', 'friends', 'blocked'
  bool _isSendingRequest = false;
  String? _errorMessage; // Store error message to show in popup

  bool get isOwnProfile => profileUserId != null && currentUserId != null && profileUserId == currentUserId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }


  Future<void> _loadProfile() async {
    try {
      setState(() {
        isLoading = true;
        _errorMessage = null; // Clear previous error
      });
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
      
      // Check if viewing own profile
      final isOwnProfile = userId != null && currentUserId != null && userId == currentUserId;
      
      // Create default userData structure with available info
      Map<String, dynamic> defaultUserData = {
        'id': userId ?? '',
        'userID': userId ?? '',
        'username': username ?? 'Unknown User',
        'avatar': '',
        'wallpaper': '',
        'online': '0',
      };
      
      User? profile;
      
      // If viewing own profile, try to load from cache first (works offline)
      if (isOwnProfile) {
        print('[SKYBYN] 📦 [Profile] Loading own profile - checking cache first');
        developer.log('📦 [Profile] Loading own profile - checking cache first', name: 'Profile API');
        
        try {
          final cachedProfile = await authService.getStoredUserProfile();
          if (cachedProfile != null) {
            print('[SKYBYN] ✅ [Profile] Using cached profile data (offline support)');
            developer.log('✅ [Profile] Using cached profile data (offline support)', name: 'Profile API');
            profile = cachedProfile;
            
            // Update UI immediately with cached data
            setState(() {
              if (profile != null) {
                userData = profile.toJson();
                // Ensure userData has the id field set
                if (userData!['id'] == null || userData!['id'].toString().isEmpty) {
                  if (profileUserId != null) {
                    userData!['id'] = profileUserId;
                    userData!['userID'] = profileUserId;
                  }
                }
              }
              isLoading = false;
              _errorMessage = null;
            });
            
            // Try to refresh from API in background (non-blocking)
            // This keeps the cache updated but doesn't block the UI
            _refreshProfileFromAPI(authService, userId, username).catchError((e) {
              // Silently fail - we already have cached data
              print('[SKYBYN] ⚠️ [Profile] Background refresh failed (using cached data): $e');
            });
            
            // Load posts and return early (we have the profile data)
            if (userData != null) {
              _loadUserPosts();
            }
            return; // Exit early - we have cached data
          } else {
            print('[SKYBYN] ⚠️ [Profile] No cached profile found, fetching from API');
            developer.log('⚠️ [Profile] No cached profile found, fetching from API', name: 'Profile API');
          }
        } catch (e) {
          print('[SKYBYN] ⚠️ [Profile] Error loading cached profile: $e');
          developer.log('⚠️ [Profile] Error loading cached profile: $e', name: 'Profile API');
          // Continue to API fetch if cache fails
        }
      }
      
      // If not own profile, or cache failed, or no cache available - fetch from API
      // Log API request details
      final apiUrl = ApiConstants.profile;
      final requestParams = <String, String>{};
      if (userId != null) {
        requestParams['userID'] = userId;
      } else if (username != null) {
        requestParams['username'] = username;
      }
      
      print('[SKYBYN] ═══════════════════════════════════════════════════════');
      print('[SKYBYN] 📤 [Profile] Sending request to API');
      print('[SKYBYN]    URL: $apiUrl');
      print('[SKYBYN]    Parameters: ${jsonEncode(requestParams)}');
      print('[SKYBYN]    Method: POST');
      if (isOwnProfile) {
        print('[SKYBYN]    Note: Refreshing own profile from API (cache was missing)');
      }
      developer.log('📤 [Profile] Sending request to API', name: 'Profile API');
      developer.log('   URL: $apiUrl', name: 'Profile API');
      developer.log('   Parameters: ${jsonEncode(requestParams)}', name: 'Profile API');
      developer.log('   Method: POST', name: 'Profile API');
      
      profile = await authService.fetchAnyUserProfile(
        userId: userId,
        username: username,
      );
      
      // Log API response
      if (profile != null) {
        final profileJson = profile.toJson();
        print('[SKYBYN] 📥 [Profile] API Response received');
        print('[SKYBYN]    Status: Success');
        print('[SKYBYN]    User ID: ${profileJson['id'] ?? profileJson['userID']}');
        print('[SKYBYN]    Username: ${profileJson['username']}');
        print('[SKYBYN]    Has Avatar: ${profileJson['avatar'] != null && profileJson['avatar'].toString().isNotEmpty}');
        print('[SKYBYN]    Has Wallpaper: ${profileJson['wallpaper'] != null && profileJson['wallpaper'].toString().isNotEmpty}');
        print('[SKYBYN]    Online: ${profileJson['online']}');
        print('[SKYBYN]    Full Response: ${jsonEncode(profileJson)}');
        developer.log('📥 [Profile] API Response received', name: 'Profile API');
        developer.log('   Status: Success', name: 'Profile API');
        developer.log('   User ID: ${profileJson['id'] ?? profileJson['userID']}', name: 'Profile API');
        developer.log('   Username: ${profileJson['username']}', name: 'Profile API');
        developer.log('   Has Avatar: ${profileJson['avatar'] != null && profileJson['avatar'].toString().isNotEmpty}', name: 'Profile API');
        developer.log('   Has Wallpaper: ${profileJson['wallpaper'] != null && profileJson['wallpaper'].toString().isNotEmpty}', name: 'Profile API');
        developer.log('   Online: ${profileJson['online']}', name: 'Profile API');
        developer.log('   Full Response: ${jsonEncode(profileJson)}', name: 'Profile API');
      } else {
        print('[SKYBYN] 📥 [Profile] API Response received');
        print('[SKYBYN]    Status: Failed (null response)');
        print('[SKYBYN]    Error: Profile data is null');
        developer.log('📥 [Profile] API Response received', name: 'Profile API');
        developer.log('   Status: Failed (null response)', name: 'Profile API');
        developer.log('   Error: Profile data is null', name: 'Profile API');
      }
      print('[SKYBYN] ═══════════════════════════════════════════════════════');
      developer.log('═══════════════════════════════════════════════════════', name: 'Profile API');
      
      setState(() {
        if (profile != null) {
          userData = profile.toJson();
          // Ensure userData has the id field set
            if (userData!['id'] == null || userData!['id'].toString().isEmpty) {
              if (profileUserId != null) {
                userData!['id'] = profileUserId;
                userData!['userID'] = profileUserId; // Also set for compatibility
              }
            } else if (profileUserId == null) {
              // Update profileUserId from loaded data if we didn't have it initially (e.g. navigated by username)
              profileUserId = userData!['id'].toString();
            }
          _errorMessage = null; // Clear any previous error
        } else {
          // Use default data if profile fetch failed
          userData = defaultUserData;
          _errorMessage = 'Failed to load profile data. Please try again.';
        }
        isLoading = false;
      });

      // Show error popup if profile fetch failed (after widget rebuilds)
      if (_errorMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showErrorPopup(_errorMessage!);
          }
        });
      }

      // Load user posts after profile is loaded (even if profile fetch failed)
      if (userData != null) {
        _loadUserPosts();
        // Check friendship status if viewing another user's profile
        if (profileUserId != null && currentUserId != null && profileUserId != currentUserId) {
          _checkFriendshipStatus();
        }
      }
    } catch (e) {
      // On error, use default userData and show error in popup
      final errorMsg = e.toString();
      print('[SKYBYN] ❌ [Profile] Error loading profile: $errorMsg');
      developer.log('❌ [Profile] Error loading profile: $errorMsg', name: 'Profile API');
      
      setState(() {
        isLoading = false;
        // Create default userData with available info
        userData = {
          'id': profileUserId ?? widget.userId ?? '',
          'userID': profileUserId ?? widget.userId ?? '',
          'username': widget.username ?? 'Unknown User',
          'avatar': '',
          'wallpaper': '',
          'online': '0',
        };
        _errorMessage = errorMsg;
      });
      
      // Show error popup after widget rebuilds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorPopup(errorMsg);
        }
      });
      
      // Still try to load posts (they might work even if profile failed)
      if (userData != null) {
        _loadUserPosts();
      }
    }
  }
  
  /// Refresh profile from API in background (non-blocking)
  /// Used to update cache when viewing own profile
  Future<void> _refreshProfileFromAPI(AuthService authService, String? userId, String? username) async {
    try {
      final requestParams = <String, String>{};
      if (userId != null) {
        requestParams['userID'] = userId;
      } else if (username != null) {
        requestParams['username'] = username;
      }
      
      print('[SKYBYN] 🔄 [Profile] Background refresh: Fetching from API');
      developer.log('🔄 [Profile] Background refresh: Fetching from API', name: 'Profile API');
      
      final profile = await authService.fetchAnyUserProfile(
        userId: userId,
        username: username,
      );
      
      if (profile != null && mounted) {
        print('[SKYBYN] ✅ [Profile] Background refresh: Profile updated');
        developer.log('✅ [Profile] Background refresh: Profile updated', name: 'Profile API');
        
        // Update UI with fresh data if still viewing the same profile
        if (profileUserId == userId) {
          setState(() {
            userData = profile.toJson();
            // Ensure userData has the id field set
            if (userData!['id'] == null || userData!['id'].toString().isEmpty) {
              if (profileUserId != null) {
                userData!['id'] = profileUserId;
                userData!['userID'] = profileUserId;
              }
            }
            _errorMessage = null;
          });
        }
      } else {
        print('[SKYBYN] ⚠️ [Profile] Background refresh: Failed (keeping cached data)');
        developer.log('⚠️ [Profile] Background refresh: Failed (keeping cached data)', name: 'Profile API');
      }
    } catch (e) {
      print('[SKYBYN] ⚠️ [Profile] Background refresh error: $e');
      developer.log('⚠️ [Profile] Background refresh error: $e', name: 'Profile API');
      // Silently fail - we already have cached data displayed
    }
  }
  
  void _showErrorPopup(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Error',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _loadProfile(); // Retry loading
              },
              child: const Text(
                'Retry',
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadUserPosts() async {
    if (userData == null) return;

    // User.toJson() uses 'id' as the key, not 'userID'
    // Try multiple sources: userData['id'], userData['userID'], or the profileUserId we stored
    final targetUserId = userData!['id']?.toString() ?? 
                        userData!['userID']?.toString() ?? 
                        profileUserId?.toString();
    if (targetUserId == null || targetUserId.isEmpty) {
      print('[SKYBYN] ⚠️ [Profile Posts] Cannot load posts: targetUserId is null or empty');
      developer.log('⚠️ [Profile Posts] Cannot load posts: targetUserId is null or empty', name: 'Profile Posts API');
      setState(() {
        userPosts = [];
        isLoadingPosts = false;
      });
      return;
    }
    
    setState(() => isLoadingPosts = true);
    
    // Log API request details
    final apiUrl = ApiConstants.userTimeline;
    final requestParams = {
      'userID': targetUserId,
      if (currentUserId != null) 'currentUserId': currentUserId!,
    };
    
    print('[SKYBYN] ═══════════════════════════════════════════════════════');
    print('[SKYBYN] 📤 [Profile Posts] Sending request to API');
    print('[SKYBYN]    URL: $apiUrl');
    print('[SKYBYN]    Parameters: ${jsonEncode(requestParams)}');
    print('[SKYBYN]    Method: POST');
    developer.log('📤 [Profile Posts] Sending request to API', name: 'Profile Posts API');
    developer.log('   URL: $apiUrl', name: 'Profile Posts API');
    developer.log('   Parameters: ${jsonEncode(requestParams)}', name: 'Profile Posts API');
    developer.log('   Method: POST', name: 'Profile Posts API');
    
    try {
      final postService = PostService();
      // Fetch posts for the specific user whose profile is being viewed
      final posts = await postService.fetchUserTimeline(
        userId: targetUserId ?? '',
        currentUserId: currentUserId,
      );
      
      // Log API response
      print('[SKYBYN] 📥 [Profile Posts] API Response received');
      print('[SKYBYN]    Status: Success');
      print('[SKYBYN]    Posts Count: ${posts.length}');
      if (posts.isNotEmpty) {
        print('[SKYBYN]    First Post ID: ${posts.first.id}');
        print('[SKYBYN]    First Post User: ${posts.first.userId}');
        print('[SKYBYN]    First Post Content Preview: ${posts.first.content.length > 50 ? posts.first.content.substring(0, 50) + "..." : posts.first.content}');
      }
      developer.log('📥 [Profile Posts] API Response received', name: 'Profile Posts API');
      developer.log('   Status: Success', name: 'Profile Posts API');
      developer.log('   Posts Count: ${posts.length}', name: 'Profile Posts API');
      if (posts.isNotEmpty) {
        developer.log('   First Post ID: ${posts.first.id}', name: 'Profile Posts API');
        developer.log('   First Post User: ${posts.first.userId}', name: 'Profile Posts API');
        developer.log('   First Post Content Preview: ${posts.first.content.length > 50 ? posts.first.content.substring(0, 50) + "..." : posts.first.content}', name: 'Profile Posts API');
      }
      
      // The API endpoint (user-timeline.php) should already filter by user
      // Trust the API response, but log for debugging
      for (final post in posts) {
        if (post.userId != null && post.userId != targetUserId) {
          print('[SKYBYN] ⚠️ [Profile Posts] Post ${post.id} belongs to different user (${post.userId} vs $targetUserId)');
          developer.log('⚠️ [Profile Posts] Post ${post.id} belongs to different user (${post.userId} vs $targetUserId)', name: 'Profile Posts API');
        }
      }
      
      // Use all posts from API - the endpoint is user-specific
      // Patch posts with known user data if missing
      final patchedPosts = posts.map((post) {
        // Only patch if author is missing/unknown or if we want to enforce consistency
        if (post.author == 'Unknown User' || post.author.isEmpty) {
          return post.copyWith(
            author: userData?['username']?.toString() ?? post.author,
            avatar: userData?['avatar']?.toString() ?? post.avatar,
            userId: targetUserId,
          );
        }
        return post;
      }).toList();

      setState(() {
        userPosts = patchedPosts;
        isLoadingPosts = false;
      });
      
      print('[SKYBYN] ═══════════════════════════════════════════════════════');
      developer.log('═══════════════════════════════════════════════════════', name: 'Profile Posts API');
    } catch (e) {
      print('[SKYBYN] ❌ [Profile Posts] Error loading posts: $e');
      developer.log('❌ [Profile Posts] Error loading posts: $e', name: 'Profile Posts API');
      setState(() {
        userPosts = [];
        isLoadingPosts = false;
      });
    }
  }

  Future<void> _refreshUserPosts() async {
    await _loadUserPosts();
  }

  Future<void> _refreshProfile() async {
    // Refresh both profile data and posts
    await _loadProfile();
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


  Future<void> _checkFriendshipStatus() async {
    if (currentUserId == null || profileUserId == null) {
      return;
    }
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.friend),
        body: {
          'userID': currentUserId!,
          'friendID': profileUserId!,
          'action': 'status',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status']?.toString().toLowerCase() ?? 'none';
        setState(() {
          _friendshipStatus = status;
        });
      } else {
        setState(() {
          _friendshipStatus = 'none';
        });
      }
    } catch (e) {
      // Default to 'none' if check fails
      setState(() {
        _friendshipStatus = 'none';
      });
    }
  }

  Future<void> _sendFriendRequest() async {
    if (currentUserId == null || userData == null || _isSendingRequest) {
      return;
    }
    
    final friendId = userData!['id']?.toString() ?? userData!['userID']?.toString();
    if (friendId == null || friendId.isEmpty) {
      return;
    }
    setState(() {
      _isSendingRequest = true;
    });
    
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.friend),
        body: {
          'userID': currentUserId!,
          'friendID': friendId,
          'action': 'add',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['responseCode'] == 1) {
          setState(() {
            _friendshipStatus = 'sent';
            _isSendingRequest = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Friend request sent'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          setState(() {
            _isSendingRequest = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Failed to send friend request'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        setState(() {
          _isSendingRequest = false;
        });
      }
    } catch (e) {
      setState(() {
        _isSendingRequest = false;
      });
    }
  }

  Widget _buildActionButtons() {
    // If friend request received, show Accept/Decline buttons prominently
    if (_friendshipStatus == 'received') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildActionButton(
            icon: Icons.check,
            label: TranslationService().translate(TranslationKeys.acceptFriend), // Ensure this key exists or use string
            color: Colors.green,
            onTap: () => _sendFriendAction('accept'),
          ),
          const SizedBox(width: 12),
          _buildActionButton(
            icon: Icons.close,
            label: TranslationService().translate(TranslationKeys.declineFriend), // Ensure this key exists or use string
            color: Colors.red,
            onTap: () => _sendFriendAction('decline'),
          ),
          const SizedBox(width: 12),
          _buildActionButton(
            icon: Icons.chat,
            label: TranslationService().translate(TranslationKeys.chat),
            onTap: () {
              if (profileUserId != null && userData != null) {
                final friend = Friend(
                  id: profileUserId!,
                  username: userData!['username']?.toString() ?? '',
                  nickname: userData!['nickname']?.toString() ?? userData!['username']?.toString() ?? '',
                  avatar: userData!['avatar']?.toString() ?? '',
                  online: userData!['online'] == '1' || userData!['online'] == 1 || userData!['online'] == true || userData!['online'] == 'true',
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(friend: friend),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 12),
           _buildActionButton(
            icon: Icons.share,
            label: TranslationService().translate(TranslationKeys.share),
            onTap: () {
              _shareProfile();
            },
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Chat button
          _buildRedesignedActionButton(
            icon: Icons.chat_bubble_outline,
            label: TranslationService().translate(TranslationKeys.chat),
            onTap: () {
              if (profileUserId != null && userData != null) {
                final friend = Friend(
                  id: profileUserId!,
                  username: userData!['username']?.toString() ?? '',
                  nickname: userData!['nickname']?.toString() ?? userData!['username']?.toString() ?? '',
                  avatar: userData!['avatar']?.toString() ?? '',
                  online: userData!['online'] == '1' || userData!['online'] == 1 || userData!['online'] == true || userData!['online'] == 'true',
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(friend: friend),
                  ),
                );
              }
            },
          ),
          // Friend Actions button
          _buildRedesignedActionButton(
            icon: Icons.person_add_outlined,
            label: TranslationService().translate(TranslationKeys.friends),
            onTap: () {
              _showFriendActionsMenu();
            },
          ),
          // Share button
          _buildRedesignedActionButton(
            icon: Icons.ios_share_outlined,
            label: TranslationService().translate(TranslationKeys.share),
            onTap: () {
              _shareProfile();
            },
          ),
          // More/Report button
          _buildRedesignedActionButton(
            icon: Icons.more_horiz,
            label: TranslationService().translate(TranslationKeys.actions),
            onTap: () {
               _showFriendActionsMenu(); // Or report directly
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRedesignedActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color ?? Colors.white.withOpacity(0.9),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onTap();
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.white.withOpacity(0.2),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: color ?? AppColors.getIconColor(context),
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.getTextColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _reportUser() async {
    if (currentUserId == null || userData == null) {
      return;
    }
    
    final userReported = userData!['id']?.toString() ?? userData!['userID']?.toString();
    if (userReported == null || userReported.isEmpty) {
      return;
    }
    
    final reportedUsername = userData!['username']?.toString() ?? 'this user';
    
    // Show dialog with optional text input
    final reportContent = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController reportController = TextEditingController();
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text(TranslationService().translate(TranslationKeys.report)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Why are you reporting $reportedUsername? (Optional)'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reportController,
                    maxLines: 4,
                    maxLength: 255,
                    decoration: InputDecoration(
                      hintText: 'Enter reason for reporting...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[900],
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    side: BorderSide(color: Colors.grey[600]!),
                  ),
                  child: Text(
                    TranslationService().translate(TranslationKeys.cancel),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(reportController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text(
                    TranslationService().translate(TranslationKeys.report),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    
    // If user cancelled, return
    if (reportContent == null) {
      return;
    }
    
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.report),
        body: {
          'userID': currentUserId!,
          'userReported': userReported,
          'content': reportContent.isEmpty ? 'User reported from profile screen' : reportContent,
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['responseCode'] == 1) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'User reported successfully. Thank you for your report.'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Failed to report user'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error reporting user. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error reporting user. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _shareProfile() async {
    if (userData == null) return;
    
    final username = userData!['username']?.toString() ?? '';
    final profileUrl = 'https://skybyn.com/profile/$username';
    final shareText = 'Check out $username on Skybyn!\n$profileUrl';
    
    try {
      await Share.share(shareText);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error sharing profile'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildFriendActionDropdown() {
    final status = _friendshipStatus ?? 'none';
    // If user has blocked you, show blocked icon only
    if (status == 'blocked') {
      return const IconButton(
        icon: Icon(
          Icons.block,
          color: Colors.grey,
          size: 24,
        ),
        tooltip: 'This user has blocked you',
        onPressed: null, // Disabled
      );
    }
    
    // Show loading indicator if sending request
    if (_isSendingRequest) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }
    
    // Build menu items based on status
    List<PopupMenuEntry<String>> menuItems = [];
    
    if (status == 'friends') {
      menuItems.add(
        const PopupMenuItem(
          value: 'unfriend',
          child: Row(
            children: [
              Icon(Icons.person_remove, size: 18, color: Colors.white),
              SizedBox(width: 12),
              Text('Unfriend', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else if (status == 'sent') {
      menuItems.add(
        const PopupMenuItem(
          value: 'cancel',
          child: Row(
            children: [
              Icon(Icons.close, size: 18, color: Colors.white),
              SizedBox(width: 12),
              Text('Cancel Request', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else if (status == 'received') {
      menuItems.add(
        const PopupMenuItem(
          value: 'accept',
          child: Row(
            children: [
              Icon(Icons.person_add, size: 18, color: Colors.green),
              SizedBox(width: 12),
              Text('Accept', style: TextStyle(color: Colors.green)),
            ],
          ),
        ),
      );
      menuItems.add(
        const PopupMenuItem(
          value: 'ignore',
          child: Row(
            children: [
              Icon(Icons.close, size: 18, color: Colors.white),
              SizedBox(width: 12),
              Text('Ignore', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else if (status == 'block' || status == 'unblock') {
      menuItems.add(
        const PopupMenuItem(
          value: 'unblock',
          child: Row(
            children: [
              Icon(Icons.person_off, size: 18, color: Colors.orange),
              SizedBox(width: 12),
              Text('Unblock', style: TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      );
    } else {
      // No friendship exists
      menuItems.add(
        PopupMenuItem(
          value: 'send',
          child: Row(
            children: [
              const Icon(Icons.person_add, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              Text(TranslationService().translate(TranslationKeys.sendFriendRequest), style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      menuItems.add(
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              const Icon(Icons.block, size: 18, color: Colors.red),
              const SizedBox(width: 12),
              Text(TranslationService().translate(TranslationKeys.blockUser), style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      );
    }
    
    // Report option removed - now available as a dedicated button in the navigation bar
    
    // Return PopupMenuButton with 3-dot vertical icon
    return Builder(
      builder: (context) {
        return PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: AppColors.getIconColor(context),
            size: 24,
          ),
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
          iconSize: 24,
          tooltip: 'More options',
          splashRadius: 24,
          elevation: 20,
          itemBuilder: (BuildContext context) {
            // Show toast when menu opens
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dropdown menu opened'),
                duration: Duration(seconds: 1),
                backgroundColor: Colors.blue,
              ),
            );
            return menuItems;
          },
          onSelected: (String value) {
            if (value == 'send') {
              _sendFriendRequest();
            } else {
              _sendFriendAction(value);
            }
          },
        );
      },
    );
  }

  Widget _buildRelationshipStatus() {
    final relStatus = userData?['relationship']?.toString();
    
    // Calculate translated status safely
    String translatedStatus = '';
    if (relStatus != null && relStatus.isNotEmpty && relStatus.toLowerCase() != 'none' && relStatus != '0') {
      final translationKey = 'rel_$relStatus';
      translatedStatus = TranslationService().translate(translationKey);
    }

    final partner = userData?['partner'] as Map<String, dynamic>?;
    final partnerName = partner?['username']?.toString();
    final partnerAvatar = partner?['avatar']?.toString();

    return Column(
      children: [
        if (profileUserId != null && currentUserId != null && profileUserId != currentUserId && userData != null)
           _buildActionButtons(),
        
        // Profile Info Tabs (Username, Relationship)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              _buildInfoTab(Icons.alternate_email, userData?['username'] ?? 'unknown'),
              if (translatedStatus.isNotEmpty) ...[
                Divider(height: 1, color: Colors.white.withOpacity(0.05)),
                _buildInfoTab(Icons.favorite_border, translatedStatus),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTab(IconData icon, String text) {
     return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.blueAccent, size: 18),
          ),
          const SizedBox(width: 16),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubProfileThumbnail() {
    final subprofiles = userData?['subprofiles'] as List?;
    if (subprofiles == null || subprofiles.isEmpty) {
      return Container(
        color: Colors.white.withOpacity(0.05),
        child: const Center(
          child: Icon(Icons.add, color: Colors.white, size: 20),
        ),
      );
    }

    final sp = subprofiles[0] as Map<String, dynamic>;
    final avatar = sp['avatar']?.toString() ?? '';
    final type = sp['type']?.toString();

    if (avatar.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: UrlHelper.convertUrl(avatar),
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.black26),
        errorWidget: (context, url, error) => _buildSubProfileIcon(type),
      );
    }

    return _buildSubProfileIcon(type);
  }

  Widget _buildSubProfileIcon(String? type) {
    IconData icon;
    if (type == 'kid') {
      icon = Icons.child_care;
    } else if (type == 'pet') {
      icon = Icons.pets;
    } else if (type == 'vehicle') {
      icon = Icons.directions_car;
    } else {
      icon = Icons.star;
    }
    return Center(child: Icon(icon, color: Colors.white, size: 20));
  }

  void _showSubProfileDetail(Map<String, dynamic> sp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSubProfileDetailOverlay(sp),
    );
  }

  Widget _buildSubProfileDetailOverlay(Map<String, dynamic> sp) {
    final name = sp['name']?.toString() ?? sp['nickname']?.toString() ?? sp['modelname']?.toString() ?? 'Unknown';
    final type = sp['type']?.toString() ?? 'Other';
    final avatar = sp['avatar']?.toString() ?? '';
    final breed = sp['breed']?.toString() ?? sp['brand']?.toString() ?? '';
    final age = sp['age']?.toString() ?? '';

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[900]!,
            Colors.black,
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white12),
                        ),
                        child: ClipOval(
                          child: avatar.isNotEmpty 
                            ? CachedNetworkImage(imageUrl: UrlHelper.convertUrl(avatar), fit: BoxFit.cover)
                            : _buildSubProfileIcon(type),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            Text(type.toUpperCase(), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _buildDetailItem(Icons.star, "Breed/Brand", breed),
                  _buildDetailItem(Icons.cake, "Age/Year", age),
                  const SizedBox(height: 30),
                  // Gallery Implementation
                  const Text("Gallery", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  () {
                    final gallery = sp['gallery'] as List?;
                    if (gallery == null || gallery.isEmpty) {
                      return Container(
                        height: 100,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Center(child: Text("No photos available", style: TextStyle(color: Colors.white54))),
                      );
                    }
                    return SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: gallery.length,
                        itemBuilder: (context, index) {
                          final imageUrl = gallery[index].toString();
                          return GestureDetector(
                            onTap: () {
                              // Optional: Implement full screen preview
                              // _showFullScreenImage(imageUrl);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 12),
                              width: 120,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.white12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.white.withOpacity(0.05),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => const Center(
                                    child: Icon(Icons.error_outline, color: Colors.white24),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFriendActionsMenu() {
    final status = _friendshipStatus ?? 'none';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey[900]!, Colors.black],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (status == 'friends')
              _buildMenuActionItem(Icons.person_remove, 'Unfriend', Colors.white, () {
                Navigator.pop(context);
                _sendFriendAction('unfriend');
              })
            else if (status == 'sent')
              _buildMenuActionItem(Icons.close, 'Cancel Request', Colors.white, () {
                Navigator.pop(context);
                _sendFriendAction('cancel');
              })
            else if (status == 'received') ...[
              _buildMenuActionItem(Icons.person_add, 'Accept Request', Colors.greenAccent, () {
                Navigator.pop(context);
                _sendFriendAction('accept');
              }),
              _buildMenuActionItem(Icons.close, 'Ignore Request', Colors.white, () {
                Navigator.pop(context);
                _sendFriendAction('ignore');
              }),
            ] else if (status == 'block' || status == 'unblock')
              _buildMenuActionItem(Icons.person_off, 'Unblock', Colors.orangeAccent, () {
                Navigator.pop(context);
                _sendFriendAction('unblock');
              })
            else
              _buildMenuActionItem(Icons.person_add, TranslationService().translate(TranslationKeys.sendFriendRequest), Colors.white, () {
                Navigator.pop(context);
                _sendFriendRequest();
              }),
            
            _buildMenuActionItem(Icons.block, TranslationService().translate(TranslationKeys.blockUser), Colors.redAccent, () {
              Navigator.pop(context);
              _sendFriendAction('block');
            }),
            
            _buildMenuActionItem(Icons.report_problem_outlined, TranslationService().translate(TranslationKeys.report), Colors.orange, () {
               Navigator.pop(context);
               _reportUser();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuActionItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }

  Widget _buildSubProfiles() {
    final subprofiles = userData?['subprofiles'] as List?;
    if (subprofiles == null || subprofiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            TranslationService().translate(TranslationKeys.familyAndAssets) ?? 'Family & Assets',
            style: TextStyle(
              color: AppColors.getTextColor(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: subprofiles.length,
            itemBuilder: (context, index) {
              final sp = subprofiles[index] as Map<String, dynamic>;
              return GestureDetector(
                onTap: () => _showSubProfileDetail(sp),
                child: _buildSubProfileCard(sp),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubProfileCard(Map<String, dynamic> sp) {
    final type = sp['type']?.toString();
    final name = sp['name']?.toString() ?? sp['nickname']?.toString() ?? sp['modelname']?.toString() ?? 'Unknown';
    final avatar = sp['avatar']?.toString();
    
    IconData typeIcon;
    Color iconColor;
    
    if (type == 'kid') {
      typeIcon = Icons.child_care;
      iconColor = Colors.blueAccent;
    } else if (type == 'pet') {
      typeIcon = Icons.pets;
      iconColor = Colors.orangeAccent;
    } else if (type == 'vehicle') {
      typeIcon = Icons.directions_car;
      iconColor = Colors.greenAccent;
    } else {
      typeIcon = Icons.star;
      iconColor = Colors.purpleAccent;
    }

    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 12, bottom: 8, top: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          if (avatar != null && avatar.isNotEmpty)
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: UrlHelper.convertUrl(avatar),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Icon(typeIcon, color: iconColor, size: 30),
              ),
            )
          else
            Icon(typeIcon, color: iconColor, size: 40),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            type?.toUpperCase() ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _sendFriendAction(String action) async {
    if (currentUserId == null || userData == null) {
      return;
    }
    final friendId = userData!['id']?.toString() ?? userData!['userID']?.toString();
    if (friendId == null || friendId.isEmpty) {
      return;
    }
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.friend),
        body: {
          'userID': currentUserId!,
          'friendID': friendId,
          'action': action,
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['responseCode'] == 1) {
          // Refresh friendship status after action
          await _checkFriendshipStatus();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Action completed'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Action failed'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error performing action'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
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
          notificationButtonKey: _notificationButtonKey,
        ),
      ),
      body: Stack(
        children: [
          const BackgroundGradient(),
          if (isLoading)
            CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: appBarHeight + MediaQuery.of(context).padding.top,
                  ),
                ),
                // Profile Header Skeleton (Wallpaper with Avatar)
                SliverToBoxAdapter(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: MediaQuery.of(context).size.height * 0.25, // 25vh
                        child: const ProfileBackgroundSkeleton(),
                      ),
                      // Avatar and Username Skeleton (overlapping wallpaper)
                      Positioned(
                        left: 20,
                        top: MediaQuery.of(context).size.height * 0.18, // 18vh
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center, // Matches UI center alignment
                          children: [
                            const ProfileAvatarSkeleton(size: 150),
                            const SizedBox(width: 16),
                            Padding(
                              padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.07), // 7vh
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                SkeletonLoader(
                                  child: Container(
                                    height: 28,
                                    width: 150,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Spacer to account for the content that extends below the wallpaper
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: (MediaQuery.of(context).size.height * 0.18) - (MediaQuery.of(context).size.height * 0.25) + 120, 
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),
                // Post feed skeleton
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        const PostCardSkeleton(),
                      ],
                    ],
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 130),
                ),
              ],
            )
          else
            // Always show profile UI, even if there was an error
            RefreshIndicator(
              onRefresh: _refreshProfile,
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
                  // --- Static Profile Header (Wallpaper Only) ---
                  SliverToBoxAdapter(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: MediaQuery.of(context).size.height * 0.25, // 25vh
                          child: useDefaultWallpaper
                              ? Image.asset(
                                  'assets/images/background.png',
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                )
                              : CachedNetworkImage(
                                  imageUrl: UrlHelper.convertUrl(wallpaperUrl),
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Image.asset(
                                    'assets/images/background.png',
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                  errorWidget: (context, url, error) => Image.asset(
                                    'assets/images/background.png',
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                        ),
                        // --- Avatar Stack and User Info Section ---
                        Positioned(
                          left: 16,
                          top: MediaQuery.of(context).size.height * 0.18, // 18vh
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center, // Centered vertically with avatar
                            children: [
                              // Avatar Stack (Avatar + Subprofile thumbnail)
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 150,
                                    height: 150,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.black.withOpacity(0.1),
                                          width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: (avatarUrl.isNotEmpty)
                                          ? CachedNetworkImage(
                                              imageUrl: UrlHelper.convertUrl(avatarUrl),
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => Image.asset(
                                                  'assets/images/icon.png',
                                                  fit: BoxFit.cover),
                                              errorWidget: (context, url, error) => Image.asset(
                                                  'assets/images/icon.png',
                                                  fit: BoxFit.cover),
                                            )
                                          : Image.asset('assets/images/icon.png',
                                              fit: BoxFit.cover),
                                    ),
                                  ),
                                  // Sub-profile Overlap Avatar
                                   Positioned(
                                    left: 95, // Positioned at 95px margin-left in mobile web
                                    top: 95, // Positioned at 95px margin-top in mobile web
                                    child: GestureDetector(
                                      onTap: () {
                                        final subprofiles = userData?['subprofiles'] as List?;
                                        if (subprofiles != null && subprofiles.isNotEmpty) {
                                            _showSubProfileDetail(subprofiles[0]);
                                        } else if (isOwnProfile) {
                                            // _addSubProfile();
                                        }
                                      },
                                      child: Opacity(
                                        opacity: 0.5,
                                        child: Container(
                                          width: (userData?['subprofiles'] as List?)?.isNotEmpty == true ? 75 : 50,
                                          height: (userData?['subprofiles'] as List?)?.isNotEmpty == true ? 75 : 50,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.2),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.4),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: _buildSubProfileThumbnail(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                               // Username column (handle removed)
                              Padding(
                                padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.07), // 7vh
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  Text(
                                    userData?['username'] ?? 'Unknown User',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.getTextColor(context),
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.5),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                        ),
                      ],
                    ),
                  ),
                  // Spacer to account for the content that extends below the wallpaper
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: 110, // Increased for 150px avatar
                    ),
                  ),
                  // Relationship Status Section
                  SliverToBoxAdapter(
                    child: _buildRelationshipStatus(),
                  ),
                  // Sub-profiles Section
                  SliverToBoxAdapter(
                    child: _buildSubProfiles(),
                  ),
                  // Action buttons navigation (outside Stack to ensure they're clickable)
                  if (profileUserId != null && 
                      currentUserId != null && 
                      profileUserId != currentUserId &&
                      userData != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: _buildActionButtons(),
                      ),
                    ),
                  // --- Post Feed ---
                  // Show skeleton loader if loading posts OR if there was an error loading profile
                  if (isLoadingPosts || _errorMessage != null)
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          for (int i = 0; i < 3; i++) ...[
                            const PostCardSkeleton(),
                          ],
                        ],
                      ),
                    )
                  else if (userPosts.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(
                          child: TranslatedText(
                            TranslationKeys.noPostsYet,
                            style: TextStyle(color: Colors.white70, fontSize: 16),
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
