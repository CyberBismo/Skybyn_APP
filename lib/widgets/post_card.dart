import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../widgets/comment_card.dart';
import '../services/comment_service.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/realtime_service.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'post_menu.dart';
import '../screens/create_post_screen.dart';

/// Centralized styling for the PostCard widget
class PostCardStyles {
  // Colors
  static const Color lightCardBackgroundColor = Color(0x33FFFFFF); // White with 20% opacity
  static const Color darkCardBackgroundColor = Color(0x4D000000); // Black with 30% opacity
  static const Color lightCardBorderColor = Color(0x00000000); // Black with 0% opacity
  static const Color darkCardBorderColor = Color(0x26FFFFFF); // White with 15% opacity
  static const Color lightTextColor = Colors.white;
  static const Color darkTextColor = Colors.white;
  static const Color lightHintColor = Color(0x99FFFFFF); // White with 60% opacity
  static const Color darkHintColor = Color(0x99FFFFFF); // White with 60% opacity
  static const Color lightAvatarBorderColor = Colors.white;
  static const Color darkAvatarBorderColor = Color(0xCC000000); // Black with 80% opacity
  
  // Sizes
  static const double cardBorderRadius = 18.0;
  static const double avatarSize = 60.0;
  static const double avatarBorderWidth = 2.0;
  static const double imageBorderRadius = 12.0;
  static const double iconSize = 20.0;
  static const double actionButtonSize = 40.0;
  
  // Padding and margins
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets headerPadding = EdgeInsets.only(bottom: 12.0);
  static const EdgeInsets contentPadding = EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0, bottom: 0);
  static const EdgeInsets imagePadding = EdgeInsets.only(top: 12.0);
  static const EdgeInsets actionsPadding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0);
  static const EdgeInsets commentSectionPadding = EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0, bottom: 8.0);
  static const EdgeInsets avatarPadding = EdgeInsets.only(right: 12.0);
  static const EdgeInsets textPadding = EdgeInsets.symmetric(vertical: 4.0);
  
  // Border radius
  static const double cardRadius = 18.0;
  static const double avatarRadius = 12.0;
  static const double imageRadius = 16.0;
  static const double buttonRadius = 20.0;
  
  // Shadows and effects
  static const double blurSigma = 16.0;
  static const double shadowBlurRadius = 12.0;
  static const Offset shadowOffset = Offset(0, 4);
  static const double shadowOpacity = 0.04;
  static const double cardBorderWidth = 1.2;
  
  // Text styles
  static const TextStyle authorTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  
  static const TextStyle contentTextStyle = TextStyle(
    fontSize: 20,
    color: Colors.white,
  );
  
  static const TextStyle timestampTextStyle = TextStyle(
    fontSize: 12,
    color: Color(0x99FFFFFF), // White with 60% opacity
  );
  
  static const TextStyle statsTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.white,
    fontWeight: FontWeight.w500,
  );
  
  static const TextStyle actionButtonTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );
  
  // Theme-aware color getters
  static Color getCardBackgroundColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBackgroundColor : lightCardBackgroundColor;
  }
  
  static Color getCardBorderColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBorderColor : lightCardBorderColor;
  }
  
  static Color getTextColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkTextColor : lightTextColor;
  }
  
  static Color getHintColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkHintColor : lightHintColor;
  }
  
  static Color getAvatarBorderColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkAvatarBorderColor : lightAvatarBorderColor;
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
    Key? key,
    required this.post,
    this.currentUserId,
    this.onPostDeleted,
    this.onPostUpdated,
    this.onInputFocused,
    this.onInputUnfocused,
  }) : super(key: key);

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

      print('🔄 Posting comment: "${commentText}" to post ${_currentPost.id}');

      await _commentService.postComment(
        postId: _currentPost.id,
        userId: userId,
        content: commentText,
        onSuccess: (String commentId) async {
          // Send WebSocket message to notify other clients
          if (commentId.isNotEmpty) {
            RealtimeService().sendNewComment(_currentPost.id, commentId);
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
          SnackBar(
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
      RealtimeService().sendDeleteComment(_currentPost.id, commentId);

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
      RealtimeService().sendDeletePost(_currentPost.id);

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
          SnackBar(content: Text('Post link copied to clipboard!')),
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
        SnackBar(content: Text('Post link copied to clipboard!')),
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
                SnackBar(content: Text('Post reported successfully')),
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
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          decoration: BoxDecoration(
            color: cardBackgroundColor,
            borderRadius: BorderRadius.circular(PostCardStyles.cardRadius),
            border: Border.all(color: cardBorderColor, width: PostCardStyles.cardBorderWidth),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(PostCardStyles.shadowOpacity),
                blurRadius: PostCardStyles.shadowBlurRadius,
                offset: PostCardStyles.shadowOffset,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PostCardStyles.cardRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: PostCardStyles.blurSigma, sigmaY: PostCardStyles.blurSigma),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Container(
                            width: PostCardStyles.avatarSize,
                            height: PostCardStyles.avatarSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(PostCardStyles.avatarRadius),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(PostCardStyles.avatarRadius),
                              child: avatarWidget
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentPost.author,
                                  style: PostCardStyles.authorTextStyle,
                                ),
                                Text(
                                  _formatTimestamp(_currentPost.createdAt),
                                  style: PostCardStyles.timestampTextStyle,
                                ),
                              ],
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              print('🔍 PostCard Debug: postId=${_currentPost.id}, postUserId=${_currentPost.userId}, currentUserId=$_currentUserId');
                              if (_currentPost.userId == null) {
                                print('❌ PostCard: userId is null, hiding menu');
                                return const SizedBox.shrink();
                              }
                              if (_currentUserId == null) {
                                print('❌ PostCard: currentUserId is null, hiding menu');
                                return const SizedBox.shrink();
                              }
                              print('✅ PostCard: Showing menu, isAuthor=${_currentUserId == _currentPost.userId}');
                              return PostMenu.createMenuButton(
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
                        ],
                      ),
                    ),
                    Padding(
                      padding: PostCardStyles.contentPadding,
                      child: Text(
                        _currentPost.content,
                        style: PostCardStyles.contentTextStyle,
                      ),
                    ),
                    if (imageWidget != null)
                      Padding(
                        padding: PostCardStyles.imagePadding,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(PostCardStyles.imageRadius),
                          child: imageWidget,
                        ),
                      ),
                    Padding(
                      padding: PostCardStyles.actionsPadding,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
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
                              Text('${_currentPost.likes}', style: PostCardStyles.statsTextStyle),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _toggleComments,
                                child: Icon(Icons.comment, color: textColor, size: PostCardStyles.iconSize),
                              ),
                              const SizedBox(width: 4),
                              Text('${_currentPost.comments}', style: PostCardStyles.statsTextStyle),
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
        ),
      ],
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
      padding: EdgeInsets.only(
        bottom: 16.0,
        left: 16.0,
        right: 16.0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40.0,
              child: TextField(
                controller: _commentController,
                focusNode: _commentFocusNode,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(color: hintColor),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 0),
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
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
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
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
                        ),
                        style: TextStyle(color: Colors.white),
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
                        color: Colors.white,
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