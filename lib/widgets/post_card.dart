import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/post.dart';

import '../widgets/comment_card.dart';
import '../services/comment_service.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'unified_menu.dart';
import '../services/websocket_service.dart';
import '../screens/create_post_screen.dart';
import '../widgets/app_colors.dart';

/// Centralized styling for the PostCard widget - matches web platform exactly
class PostCardStyles {
  // Colors - match web platform's CSS variables
  static const Color lightCardBackgroundColor = Color(0x66FFFFFF); // White with 40% opacity for light mode
  static const Color darkCardBackgroundColor = Color(0x66000000); // Black with 40% opacity for dark mode
  static const Color lightCardBorderColor = Colors.transparent; // No border in web
  static const Color darkCardBorderColor = Colors.transparent;
  static const Color lightTextColor = Colors.black; // Black text for light mode
  static const Color darkTextColor = Colors.white; // White text for dark mode
  static const Color lightHintColor = Color(0x66000000); // Black with 40% opacity for light mode
  static const Color darkHintColor = Color(0x99FFFFFF); // White with 60% opacity for dark mode
  static const Color lightAvatarBorderColor = Colors.black;
  static const Color darkAvatarBorderColor = Colors.white;
  
  // Sizes - match web platform exactly
  static const double cardBorderRadius = 20.0; // border-radius: 20px
  static const double avatarSize = 70.0; // width: 70px, height: 70px
  static const double avatarBorderWidth = 0.0; // No border in web
  static const double imageMaxHeight = 300.0;
  static const double iconSize = 20.0;
  static const double fontSize = 16.0;
  static const double smallFontSize = 14.0;
  
  // Padding and margins - match web platform exactly
  static const EdgeInsets cardPadding = EdgeInsets.all(0.0); // No padding on card itself
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0); // padding: 10px 20px
  static const EdgeInsets headerPadding = EdgeInsets.all(0.0); // No padding in web
  static const EdgeInsets imagePadding = EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0); // margin: 5px 10px
  static const EdgeInsets actionsPadding = EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0);
  static const EdgeInsets commentSectionPadding = EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0); // padding: 0 10px
  static const EdgeInsets avatarPadding = EdgeInsets.all(10.0); // margin: 10px
  static const EdgeInsets textPadding = EdgeInsets.symmetric(vertical: 4.0);
  
  // Border radius - match web platform exactly
  static const double cardRadius = 20.0; // border-radius: 20px
  static const double avatarRadius = 10.0; // border-radius: 10px
  static const double imageRadius = 10.0; // border-radius: 10px
  static const double buttonRadius = 10.0; // border-radius: 10px
  static const double commentRadius = 10.0; // border-radius: 10px
  
  // Shadows and effects - match web platform exactly
  static const double blurSigma = 5.0; // backdrop-filter: blur(5px)
  static const double shadowBlurRadius = 0.0; // No shadow in web
  static const Offset shadowOffset = Offset(0, 0);
  static const double shadowOpacity = 0.0;
  static const double cardBorderWidth = 0.0; // No border in web
  
  // Text styles - match web platform exactly
  static TextStyle getAuthorTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.normal, // No bold in web
      color: getTextColor(context),
    );
  }
  
  static TextStyle getContentTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 16, // Default font size
      color: getTextColor(context),
    );
  }
  
  static TextStyle getTimestampTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 12, // font-size: 12px
      color: getHintColor(context),
    );
  }
  
  static TextStyle getStatsTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 14,
      color: getTextColor(context),
      fontWeight: FontWeight.normal,
    );
  }
  
  static TextStyle getActionButtonTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      color: getTextColor(context),
    );
  }
  
  // Theme-aware color getters - match web platform exactly
  static Color getCardBackgroundColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.light 
        ? lightCardBackgroundColor 
        : darkCardBackgroundColor;
  }
  
  static Color getCardBorderColor(BuildContext context) {
    return Colors.transparent; // No border in web
  }
  
  static Color getTextColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.light 
        ? lightTextColor 
        : darkTextColor;
  }
  
  static Color getHintColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.light 
        ? lightHintColor 
        : darkHintColor;
  }
  
  static Color getAvatarBorderColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.light 
        ? lightAvatarBorderColor 
        : darkAvatarBorderColor;
  }
}

class PostCard extends StatefulWidget {
  final Post post;
  final String? currentUserId;
  final Function(String)? onPostDeleted;
  final Function(String)? onPostUpdated;
  final VoidCallback? onInputFocused;
  final VoidCallback? onInputUnfocused;

  const PostCard({
    super.key,
    required this.post,
    this.currentUserId,
    this.onPostDeleted,
    this.onPostUpdated,
    this.onInputFocused,
    this.onInputUnfocused,
  });

  @override
  _PostCardState createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _currentPost;
  late String _currentUserId;
  bool _showComments = false;
  bool _isLiked = false;
  bool _isKeyboardVisible = false;
  OverlayEntry? _overlayEntry;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final FocusNode _popupMenuFocusNode = FocusNode();
  final CommentService _commentService = CommentService();
  final AuthService _authService = AuthService();
  final PostService _postService = PostService();
  String? _currentUsername;
  bool _isFetchingDetails = false;
  
  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _currentUserId = widget.currentUserId ?? '';
    _isLiked = _currentPost.isLiked;
    
    // Listen to keyboard visibility changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _commentFocusNode.addListener(_onFocusChange);
      }
    });
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isKeyboardVisible = _commentFocusNode.hasFocus;
      });
      
      // Call the appropriate callback
      if (_commentFocusNode.hasFocus) {
        widget.onInputFocused?.call();
        // Show floating input when focused
        _showFloatingInput();
      } else {
        widget.onInputUnfocused?.call();
        // Hide floating input when focus is lost
        _hideFloatingInput();
      }
    }
  }

  Future<void> _loadCurrentUserId() async {
    final username = await _authService.getStoredUsername();
    setState(() {
      _currentUsername = username;
    });
    print('DEBUG: Loaded user ID: $_currentUserId, username: $_currentUsername');
  }

  Future<void> _toggleComments() async {
    setState(() {
      _showComments = !_showComments;
    });

    // Fetch full post details only when opening the comment section
    // and only if they haven't been fetched already.
    if (_showComments && _currentPost.commentsList.isEmpty && _currentPost.comments > 0) {
      setState(() {
        _isFetchingDetails = true;
      });
      try {
        final userId = await _authService.getStoredUserId();
        if (userId == null) throw Exception('User not logged in');
        final updatedPost = await _postService.fetchPost(postId: _currentPost.id, userId: userId);
        setState(() {
          _currentPost = updatedPost;
        });
      } catch (e) {
        print('Failed to fetch post details: $e');
        // Optionally, hide comments section on error
        setState(() {
          _showComments = false;
        });
      } finally {
        setState(() {
          _isFetchingDetails = false;
        });
      }
    }
  }

  Future<void> _postComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) {
      return;
    }

    // Show a loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      print('🔄 Posting comment: "$commentText" to post ${_currentPost.id}');

      await _commentService.postComment(
        postId: _currentPost.id,
        userId: userId,
        content: commentText,
        onSuccess: (String commentId) async {
          // Send WebSocket message to notify other clients
          if (commentId.isNotEmpty) {
            WebSocketService().sendNewComment(_currentPost.id, commentId);
          }
          
          // Hide loading indicator
          Navigator.pop(context);
          
          // Clear the text field
          _commentController.clear();
          
          // If we have a valid comment ID, try to fetch it immediately
          if (commentId.isNotEmpty) {
            // Try to fetch the new comment and add it to the UI immediately
            try {
              print('🔄 Fetching comment $commentId for immediate display...');
              final newComment = await _commentService.getComment(
                commentId: commentId,
                userId: userId,
              );
              
              print('✅ Successfully fetched comment: ${newComment.content}');
              
              if (mounted) {
                setState(() {
                  // Add the new comment to the end of the list (oldest position) since we reversed the order
                  _currentPost = _currentPost.copyWith(
                    comments: _currentPost.comments + 1,
                    commentsList: [..._currentPost.commentsList, newComment],
                  );
                  // Don't change the comment display state - keep it as it was
                });
                print('✅ Comment added to UI immediately: ${newComment.content}');
              }
            } catch (e) {
              print('❌ Failed to fetch new comment for immediate display: $e');
              // Fallback: refresh the entire post
              _refreshPostAsFallback(userId);
            }
          } else {
            print('⚠️ No comment ID provided, refreshing entire post');
            // No comment ID available, refresh the entire post
            _refreshPostAsFallback(userId);
          }
        },
      );

    } catch (e) {
      // Hide loading indicator
      Navigator.pop(context);
      
      print('❌ Failed to post comment: $e');
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to post comment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshPostAsFallback(String userId) async {
    try {
      print('🔄 Falling back to refresh entire post...');
      final updatedPost = await _postService.fetchPost(postId: _currentPost.id, userId: userId);
      if (mounted) {
        setState(() {
          _currentPost = updatedPost;
          // Don't change the comment display state - keep it as it was
        });
        print('✅ Post refreshed successfully as fallback');
      }
    } catch (refreshError) {
      print('❌ Failed to refresh post as fallback: $refreshError');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted but could not load details'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _commentService.deleteComment(commentId: commentId, userId: userId);

      // Send WebSocket message to notify other clients
              WebSocketService().sendDeleteComment(_currentPost.id, commentId);

      Navigator.pop(context); // Dismiss loading indicator

      final updatedPost = await _postService.fetchPost(postId: _currentPost.id, userId: userId);
      if(mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete comment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Post',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this post?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deletePost();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _postService.deletePost(postId: _currentPost.id, userId: userId);

      // Send WebSocket message to notify other clients
              WebSocketService().sendDeletePost(_currentPost.id);

      Navigator.pop(context); // Dismiss loading indicator

      if (mounted) {
        // Notify parent widget that post was deleted
        widget.onPostDeleted?.call(_currentPost.id);
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onMenuSelected(String value) async {
    switch (value) {
      case 'share':
        // Implement share logic (copy link to clipboard for now)
        final postUrl = 'https://skybyn.com/post/${_currentPost.id}';
        await Clipboard.setData(ClipboardData(text: postUrl));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post link copied to clipboard!')),
        );
        break;
      case 'view_comments':
        if (!_showComments) {
          await _toggleComments();
        }
        break;
      case 'delete':
        // Show confirmation dialog before deleting
        _showDeleteDialog();
        break;
    }
  }

  void _onShare() async {
    // Implement share logic (copy link to clipboard for now)
    final postUrl = 'https://skybyn.com/post/${_currentPost.id}';
    await Clipboard.setData(ClipboardData(text: postUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post link copied to clipboard!')),
      );
    }
  }

  void _onReport() {
    // Show report dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Report Post',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to report this post?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement actual report functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Post reported successfully')),
              );
            },
            child: const Text(
              'Report',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _onEdit() async {
    // Show edit post modal
    final result = await showModalBottomSheet<String>(
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
            child: CreatePostScreen(
              isEditing: true,
              postToEdit: _currentPost,
            ),
          ),
        ),
      ),
    );
    
    // Handle the result
    if (result == 'updated' && widget.onPostUpdated != null) {
      widget.onPostUpdated!(_currentPost.id);
    }
  }



  Future<void> _toggleLike() async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      // Optimistically update the UI
      setState(() {
        _currentPost = Post(
          id: _currentPost.id,
          author: _currentPost.author,
          avatar: _currentPost.avatar,
          content: _currentPost.content,
          image: _currentPost.image,
          likes: _currentPost.isLiked ? _currentPost.likes - 1 : _currentPost.likes + 1,
          comments: _currentPost.comments,
          commentsList: _currentPost.commentsList,
          createdAt: _currentPost.createdAt,
          isLiked: !_currentPost.isLiked,
        );
      });

      // TODO: Implement actual like/unlike API call
      // await _postService.toggleLike(postId: _currentPost.id, userId: userId);
    } catch (e) {
      // Revert the optimistic update on error
      setState(() {
        _currentPost = Post(
          id: _currentPost.id,
          author: _currentPost.author,
          avatar: _currentPost.avatar,
          content: _currentPost.content,
          image: _currentPost.image,
          likes: _currentPost.isLiked ? _currentPost.likes + 1 : _currentPost.likes - 1,
          comments: _currentPost.comments,
          commentsList: _currentPost.commentsList,
          createdAt: _currentPost.createdAt,
          isLiked: !_currentPost.isLiked,
        );
      });
      print('Failed to toggle like: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if keyboard is actually hidden and reposition floating input if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      print('DEBUG: Build callback - bottomInset: $bottomInset, _isKeyboardVisible: $_isKeyboardVisible, hasFocus: ${_commentFocusNode.hasFocus}');
      
      if (bottomInset == 0 && _isKeyboardVisible) {
        // Keyboard was dismissed, hide floating input
        setState(() {
          _isKeyboardVisible = false;
        });
        print('DEBUG: Keyboard dismissed, setting _isKeyboardVisible to false');
        _hideFloatingInput();
      } else if (bottomInset > 0 && !_isKeyboardVisible && _commentFocusNode.hasFocus) {
        // Keyboard appeared, show floating input
        setState(() {
          _isKeyboardVisible = true;
        });
        print('DEBUG: Keyboard appeared, setting _isKeyboardVisible to true');
        _showFloatingInput();
      }
    });
    
    print('DEBUG: Build called - viewInsets.bottom: ${MediaQuery.of(context).viewInsets.bottom}');
    print('DEBUG: Build called - hasFocus: ${_commentFocusNode.hasFocus}');
    print('DEBUG: Build called - _isKeyboardVisible: $_isKeyboardVisible');
    
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Define theme-aware colors using centralized styles
    final cardBackgroundColor = PostCardStyles.getCardBackgroundColor(context);
    final cardBorderColor = PostCardStyles.getCardBorderColor(context);
    final textColor = PostCardStyles.getTextColor(context);
    final hintColor = PostCardStyles.getHintColor(context);
    final avatarBorderColor = PostCardStyles.getAvatarBorderColor(context);

    Widget avatarWidget;
    if (_currentPost.avatar != null && _currentPost.avatar!.isNotEmpty) {
      if (_currentPost.avatar!.startsWith('http')) {
        avatarWidget = CachedNetworkImage(
          imageUrl: _currentPost.avatar!,
          width: PostCardStyles.avatarSize,
          height: PostCardStyles.avatarSize,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey[800]),
          errorWidget: (context, url, error) =>
              Image.asset('assets/images/logo.png', width: PostCardStyles.avatarSize, height: PostCardStyles.avatarSize, fit: BoxFit.cover),
        );
      } else {
        avatarWidget = Image.asset(
          _currentPost.avatar!,
          width: PostCardStyles.avatarSize,
          height: PostCardStyles.avatarSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Image.asset('assets/images/logo.png', width: PostCardStyles.avatarSize, height: PostCardStyles.avatarSize, fit: BoxFit.cover),
        );
      }
    } else {
      avatarWidget = Image.asset('assets/images/logo.png', width: PostCardStyles.avatarSize, height: PostCardStyles.avatarSize, fit: BoxFit.cover);
    }

    Widget? imageWidget;
    if (_currentPost.image != null && _currentPost.image!.isNotEmpty) {
      if (_currentPost.image!.startsWith('http')) {
        imageWidget = CachedNetworkImage(
          imageUrl: _currentPost.image!,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 200,
            color: Colors.grey[800],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            height: 200,
            color: Colors.grey[800],
            child: const Center(child: Icon(Icons.error, color: Colors.white)),
          ),
        );
      } else {
        imageWidget = Image.asset(
          _currentPost.image!,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 200,
            color: Colors.grey[800],
            child: const Center(child: Icon(Icons.error, color: Colors.white)),
          ),
        );
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10.0), // margin-bottom: 10px
      padding: const EdgeInsets.only(bottom: 2.0), // padding-bottom: 2px
      child: Container(
        decoration: BoxDecoration(
          color: PostCardStyles.getCardBackgroundColor(context), // background: rgba(var(--mode),.7)
          borderRadius: BorderRadius.circular(PostCardStyles.cardRadius), // border-radius: 20px
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PostCardStyles.cardRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: PostCardStyles.blurSigma, sigmaY: PostCardStyles.blurSigma), // backdrop-filter: blur(5px)
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section - match web platform's post_header exactly
                SizedBox(
                  child: Row(
                    children: [
                      // User details - 70% width like web platform's post_details
                      Expanded(
                        flex: 7,
                        child: SizedBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // User avatar and name row
                              SizedBox(
                                height: 70.0, // height: 70px
                                child: Row(
                                  children: [
                                    // User avatar - match web platform's post_user_image exactly
                                    SizedBox(
                                      width: PostCardStyles.avatarSize,
                                      height: PostCardStyles.avatarSize,
                                      child: Container(
                                        margin: PostCardStyles.avatarPadding, // margin: 10px
                                        decoration: BoxDecoration(
                                          color: AppColors.avatarBackgroundColor,
                                          borderRadius: BorderRadius.circular(PostCardStyles.avatarRadius), // border-radius: 10px
                                          border: Border.all(color: PostCardStyles.getAvatarBorderColor(context), width: PostCardStyles.avatarBorderWidth),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(PostCardStyles.avatarRadius),
                                          child: avatarWidget,
                                        ),
                                      ),
                                    ),
                                    // User name - match web platform's post_user_name exactly
                                    Expanded(
                                      child: SizedBox(
                                        height: 70.0, // height: 70px
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _currentPost.author,
                                            style: PostCardStyles.getAuthorTextStyle(context),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Date - now part of the header
                              Transform.translate(
                                offset: const Offset(0, -10), // Move date 10px up
                                child: Container(
                                  margin: const EdgeInsets.only(left: 70.0), // margin-left: 70px
                                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 0.0),
                                  child: Text(
                                    _formatTimestamp(_currentPost.createdAt),
                                    style: PostCardStyles.getTimestampTextStyle(context), // font-size: 12px
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Actions section - 30% width like web platform's post_actions
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 75.0, // height: 50px
                          padding: const EdgeInsets.all(20.0), // padding: 20px
                          child: Builder(
                            builder: (context) {
                              print('🔍 PostCard Debug: postId=${_currentPost.id}, postUserId=${_currentPost.userId}, currentUserId=$_currentUserId');
                              if (_currentPost.userId == null) {
                                print('❌ PostCard: userId is null, hiding menu');
                                return const SizedBox.shrink();
                              }
                              print('✅ PostCard: Showing menu, isAuthor=${_currentUserId == _currentPost.userId}');
                              return UnifiedMenu.createPostMenuButton(
                                context: context,
                                postId: _currentPost.id,
                                currentUserId: _currentUserId,
                                postUserId: _currentPost.userId!,
                                onDelete: _showDeleteDialog,
                                onEdit: _onEdit,
                                onShare: _onShare,
                                onReport: _onReport,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content section - match web platform's post_content exactly
                Container(
                  padding: PostCardStyles.contentPadding, // padding: 10px 20px
                  child: Text(
                    _currentPost.content,
                    style: PostCardStyles.getContentTextStyle(context),
                    textAlign: TextAlign.left,
                  ),
                ),
                // Image section - match web platform's post_uploads exactly
                if (imageWidget != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0), // margin: 5px 10px
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(PostCardStyles.imageRadius), // border-radius: 10px
                      child: imageWidget,
                    ),
                  ),
                
                // Actions section - match web platform's styling exactly
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Like button
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _toggleLike,
                            child: Icon(
                              _currentPost.isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _currentPost.isLiked ? Colors.red : textColor,
                              size: PostCardStyles.iconSize,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_currentPost.likes}', 
                            style: TextStyle(
                              fontSize: PostCardStyles.smallFontSize, 
                              color: textColor
                            )
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // Comment button
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _toggleComments,
                            child: Icon(
                              Icons.comment, 
                              color: textColor, 
                              size: PostCardStyles.iconSize
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_currentPost.comments}', 
                            style: TextStyle(
                              fontSize: PostCardStyles.smallFontSize, 
                              color: textColor
                            )
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Comment Input Field (always visible)
                _buildCommentInputField(textColor: textColor, hintColor: hintColor),
                // Show last comment if comments are not expanded and list is not empty
                if (!_showComments && _currentPost.commentsList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
                    child: CommentCard(
                      comment: _currentPost.commentsList.first,
                      currentUserId: _currentUserId,
                      onDelete: () => _deleteComment(_currentPost.commentsList.first.id),
                    ),
                  ),
                // Collapsible list of comments
                if (_showComments) _buildCommentSection(),
                if (_currentPost.commentsList.length > 3)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showAllCommentsPopup,
                        child: Text('Expand', style: TextStyle(color: textColor)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }

  void _showAllCommentsPopup() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black.withOpacity(0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('All Comments', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Scrollbar(
                    child: ListView.builder(
                      itemCount: _currentPost.commentsList.length,
                      itemBuilder: (context, index) {
                        final comment = _currentPost.commentsList[index];
                        return CommentCard(
                          comment: comment,
                          currentUserId: _currentUserId,
                          onDelete: () => _deleteComment(comment.id),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentInputField({
    required Color textColor,
    required Color hintColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 0.0, // Removed bottom padding
        left: 16.0,
        right: 16.0,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40.0,
              child: TextField(
                controller: _commentController,
                focusNode: _commentFocusNode,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(color: hintColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                ),
                style: TextStyle(color: textColor),
                onTap: () {
                  // Ensure any other context menus are closed
                  _popupMenuFocusNode.unfocus();
                  // Show floating input when tapped
                  _showFloatingInput();
                },
                onSubmitted: (_) {
                  _postComment();
                },
              ),
            ),
          ),
          IconButton(
            onPressed: _postComment,
            icon: Icon(
              Icons.send,
              color: textColor,
              size: PostCardStyles.iconSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentSection() {
    return Padding(
      padding: PostCardStyles.commentSectionPadding,
      child: Column(
        children: [
          if (_currentPost.commentsList.isNotEmpty)
            ..._currentPost.commentsList.map((comment) => CommentCard(
              comment: comment,
              currentUserId: _currentUserId,
              onDelete: () => _deleteComment(comment.id),
            )),
        ],
      ),
    );
  }

  void _showFloatingInput() {
    _hideFloatingInput(); // Remove any existing overlay
    
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final bottomPosition = _isKeyboardVisible 
          ? keyboardHeight + 20.0 // 20px above keyboard
          : -100.0; // Move off-screen when keyboard is hidden
        
        print('DEBUG: Floating input positioning - _isKeyboardVisible: $_isKeyboardVisible, keyboardHeight: $keyboardHeight, bottomPosition: $bottomPosition');
        
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          left: 0,
          right: 0,
          bottom: bottomPosition,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              decoration: BoxDecoration(
                color: PostCardStyles.getCardBackgroundColor(context),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: PostCardStyles.getCardBorderColor(context)),
                boxShadow: [
                  BoxShadow(
                    color: PostCardStyles.getCardBackgroundColor(context).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(color: PostCardStyles.getHintColor(context)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
                        ),
                        style: TextStyle(color: PostCardStyles.getTextColor(context)),
                        onTap: () {
                          // Ensure any other context menus are closed
                          _popupMenuFocusNode.unfocus();
                        },
                        onSubmitted: (_) {
                          _postComment();
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: _postComment,
                      icon: Icon(
                        Icons.send,
                        color: PostCardStyles.getTextColor(context),
                        size: PostCardStyles.iconSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideFloatingInput() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideFloatingInput();
    _commentFocusNode.removeListener(_onFocusChange);
    _commentFocusNode.dispose();
    _popupMenuFocusNode.dispose();
    _commentController.dispose();
    super.dispose();
  }
} 