import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../models/post.dart';
import '../widgets/background_gradient.dart';
import '../widgets/post_card.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/app_colors.dart';
import '../widgets/global_search_overlay.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import 'create_post_screen.dart';
import '../config/constants.dart';
import '../utils/translation_keys.dart';
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }


  Future<void> _loadProfile() async {
    try {
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
        // Check friendship status if viewing another user's profile
        if (profileUserId != null && currentUserId != null && profileUserId != currentUserId) {
          _checkFriendshipStatus();
        }
      }
    } catch (e, stackTrace) {
      setState(() {
        isLoading = false;
        userData = null;
      });
    }
  }

  Future<void> _loadUserPosts() async {
    if (userData == null) return;

    // User.toJson() uses 'id' as the key, not 'userID'
    // Try multiple sources: userData['id'], userData['userID'], or the profileUserId we stored
    final targetUserId = userData!['id']?.toString() ?? 
                        userData!['userID']?.toString() ?? 
                        profileUserId?.toString();
    if (targetUserId == null || targetUserId.isEmpty) {
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
      // The API endpoint (user-timeline.php) should already filter by user
      // Trust the API response, but log for debugging
      for (final post in posts) {
        if (post.userId != null && post.userId != targetUserId) {
        }
      }
      
      // Use all posts from API - the endpoint is user-specific
      setState(() {
        userPosts = posts;
        isLoadingPosts = false;
      });
    } catch (e, stackTrace) {
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

  bool get isOwnProfile =>
      userData != null &&
      currentUserId != null &&
      (userData!['id']?.toString() ?? userData!['userID']?.toString()) == currentUserId;

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Chat button
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
                online: userData!['online'] == 1 || userData!['online'] == true,
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(friend: friend),
                ),
              );
            } else {
            }
          },
        ),
        const SizedBox(width: 12),
        // Friend Actions button
        _buildActionButton(
          icon: Icons.people,
          label: TranslationService().translate(TranslationKeys.friends),
          onTap: () {
            _showFriendActionsMenu();
          },
        ),
        const SizedBox(width: 12),
        // Report button
        _buildActionButton(
          icon: Icons.report,
          label: TranslationService().translate(TranslationKeys.report),
          color: Colors.red,
          onTap: () {
            _reportUser();
          },
        ),
        const SizedBox(width: 12),
        // Share button
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

  void _showFriendActionsMenu() {
    // Refresh status before showing menu
    _checkFriendshipStatus().then((_) {
      _showFriendActionsMenuInternal();
    });
  }

  void _showFriendActionsMenuInternal() {
    final status = _friendshipStatus ?? 'none';
    // Build menu items based on status
    List<PopupMenuEntry<String>> menuItems = [];
    
    // Handle blocked status (user has blocked you)
    if (status == 'blocked') {
      // User has blocked you - show nothing or disabled state
      menuItems.add(
        PopupMenuItem(
          enabled: false,
          child: Row(
            children: [
              const Icon(Icons.block, size: 18, color: Colors.grey),
              const SizedBox(width: 12),
              const Text('This user has blocked you', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    } else if (status == 'friends') {
      // Friends - show unfriend and block options
      menuItems.add(
        PopupMenuItem(
          value: 'unfriend',
          child: Row(
            children: [
              const Icon(Icons.person_remove, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              Text(TranslationService().translate(TranslationKeys.removeFriend), style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      menuItems.add(
        const PopupMenuDivider(),
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
    } else if (status == 'sent') {
      // Sent request - show cancel and block options
      menuItems.add(
        PopupMenuItem(
          value: 'cancel',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              Text('${TranslationService().translate(TranslationKeys.cancel)} ${TranslationService().translate(TranslationKeys.friendRequest)}', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      menuItems.add(
        const PopupMenuDivider(),
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
    } else if (status == 'received') {
      // Received request - show accept, ignore, and block options
      menuItems.add(
        PopupMenuItem(
          value: 'accept',
          child: Row(
            children: [
              const Icon(Icons.person_add, size: 18, color: Colors.green),
              const SizedBox(width: 12),
              Text(TranslationService().translate(TranslationKeys.acceptFriend), style: const TextStyle(color: Colors.green)),
            ],
          ),
        ),
      );
      menuItems.add(
        PopupMenuItem(
          value: 'ignore',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              Text(TranslationService().translate(TranslationKeys.declineFriend), style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      menuItems.add(
        const PopupMenuDivider(),
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
    } else if (status == 'block' || status == 'unblock') {
      // User is blocked - show unblock option
      menuItems.add(
        PopupMenuItem(
          value: 'unblock',
          child: Row(
            children: [
              const Icon(Icons.person_off, size: 18, color: Colors.orange),
              const SizedBox(width: 12),
              Text(TranslationService().translate(TranslationKeys.unblockUser), style: const TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      );
    } else {
      // No friendship exists - show send request and block options
      if (!_isSendingRequest) {
        menuItems.add(
          PopupMenuItem(
            value: 'send',
            child: Row(
              children: [
                const Icon(Icons.person_add, size: 18, color: Colors.white),
                const SizedBox(width: 12),
                const Text('Send Friend Request', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
        menuItems.add(
          const PopupMenuDivider(),
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
    }
    
    if (menuItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No friend actions available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Show popup menu
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width / 2 - 150,
        MediaQuery.of(context).size.height / 2,
        MediaQuery.of(context).size.width / 2 - 150,
        MediaQuery.of(context).size.height / 2,
      ),
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: menuItems,
    ).then((value) {
      if (value != null) {
        if (value == 'send') {
          _sendFriendRequest();
        } else {
          _sendFriendAction(value);
        }
      }
    });
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
      return IconButton(
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
        PopupMenuItem(
          value: 'unfriend',
          child: Row(
            children: [
              const Icon(Icons.person_remove, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Unfriend', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else if (status == 'sent') {
      menuItems.add(
        PopupMenuItem(
          value: 'cancel',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Cancel Request', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else if (status == 'received') {
      menuItems.add(
        PopupMenuItem(
          value: 'accept',
          child: Row(
            children: [
              const Icon(Icons.person_add, size: 18, color: Colors.green),
              const SizedBox(width: 12),
              const Text('Accept', style: TextStyle(color: Colors.green)),
            ],
          ),
        ),
      );
      menuItems.add(
        PopupMenuItem(
          value: 'ignore',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Ignore', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else if (status == 'block' || status == 'unblock') {
      menuItems.add(
        PopupMenuItem(
          value: 'unblock',
          child: Row(
            children: [
              const Icon(Icons.person_off, size: 18, color: Colors.orange),
              const SizedBox(width: 12),
              const Text('Unblock', style: TextStyle(color: Colors.orange)),
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
                        height: 200,
                        child: const ProfileBackgroundSkeleton(),
                      ),
                      // Avatar and Username Skeleton (overlapping wallpaper by 30dp)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 170, // 200 - 30 = 170 (30dp overlap)
                        child: Column(
                          children: [
                            const ProfileAvatarSkeleton(),
                            const SizedBox(height: 16),
                            SkeletonLoader(
                              child: Container(
                                height: 24,
                                width: 150,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SkeletonLoader(
                              child: Container(
                                height: 16,
                                width: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Spacer to account for the avatar height that extends below the wallpaper
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 120 + 16 + 24 + 6 + 24, // avatar height + username padding + text heights + spacing
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
          else if (userData != null)
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
                          height: 200,
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
                        // --- Avatar and Friend Action Buttons Section (overlapping wallpaper by 30dp) ---
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 170, // 200 - 30 = 170 (30dp overlap)
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Avatar (centered) - FIRST so it's below the button
                              Center(
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
                                            imageUrl: UrlHelper.convertUrl(avatarUrl),
                                            fit: BoxFit.cover,
                                            httpHeaders: const {},
                                            placeholder: (context, url) => Image.asset(
                                                'assets/images/icon.png',
                                                fit: BoxFit.cover),
                                            errorWidget: (context, url, error) {
                                              // Handle all errors including 404 (HttpExceptionWithStatus)
                                              return Image.asset(
                                                'assets/images/icon.png',
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          )
                                        : Image.asset('assets/images/icon.png',
                                            fit: BoxFit.cover),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Username (below avatar)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 300, // Below avatar (170 + 120 + 10 spacing)
                          child: Column(
                            children: [
                              Text(
                                userData!['username'] ?? '',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.getTextColor(context),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '@${userData!['username']}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.getSecondaryTextColor(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Spacer to account for the avatar and username that extend below the wallpaper
                  // Avatar starts at 170, height 120, so extends to 290
                  // Username starts at 300, height ~50 (24 + 6 + 24), so extends to ~350
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 350 - 200, // Total height (350) minus wallpaper height (200) = 150
                    ),
                  ),
                  // Action buttons navigation (outside Stack to ensure they're clickable)
                  if (profileUserId != null && 
                      currentUserId != null && 
                      profileUserId != currentUserId)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 16),
                        child: _buildActionButtons(),
                      ),
                    ),
                  // --- Post Feed ---
                  if (isLoadingPosts)
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
            )
          else
            // Show error/empty state when profile failed to load
            CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: appBarHeight + MediaQuery.of(context).padding.top,
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        const SizedBox(height: 16),
                        TranslatedText(
                          TranslationKeys.errorOccurred,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _loadProfile();
                          },
                          child: TranslatedText(
                            TranslationKeys.tryAgain,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
