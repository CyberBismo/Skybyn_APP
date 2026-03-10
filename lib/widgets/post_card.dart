import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/post.dart';

import '../widgets/comment_card.dart';
import '../services/comment_service.dart';
import '../services/auth_service.dart';
import '../models/comment.dart';
import '../services/post_service.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'unified_menu.dart';
import '../services/websocket_service.dart';
import 'create_post_widget.dart';
import '../widgets/app_colors.dart';
import '../config/constants.dart';

import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../screens/profile_screen.dart';

/// Centralized styling for the PostCard widget - matches web platform exactly
class PostCardStyles {
  // Colors - match web platform's CSS variables
  static const Color lightCardBackgroundColor =
      Color.fromRGBO(0, 0, 0, 0.12); // White with 40% opacity for light mode
  static const Color darkCardBackgroundColor =
      Color.fromRGBO(0, 0, 0, 0.40); // Black with 40% opacity for dark mode
  static const Color lightCardBorderColor =
      Colors.transparent; // No border in web
  static const Color darkCardBorderColor = Colors.transparent;
  static const Color lightTextColor =
      Colors.white; // White text fRor light mode
  static const Color darkTextColor = Colors.white; // White text for dark mode
  static const Color lightHintColor = Colors.white; // White for light mode
  static const Color darkHintColor = Colors.white; // White for dark mode
  static const Color lightAvatarBorderColor = Colors.white;
  static const Color darkAvatarBorderColor = Colors.white;

  // Sizes - match web platform exactly
  static const double cardBorderRadius = 20.0; // border-radius: 20px
  static const double avatarSize = 50.0; // width: 70px, height: 70px
  static const double avatarBorderWidth = 0.0; // No border in web
  static const double imageMaxHeight = 300.0;
  static const double iconSize = 20.0;
  static const double fontSize = 16.0;
  static const double smallFontSize = 14.0;

  // Padding and margins - match web platform exactly
  static const EdgeInsets cardPadding =
      EdgeInsets.all(0.0); // No padding on card itself
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
      horizontal: 20.0, vertical: 10.0); // padding: 10px 20px
  static const EdgeInsets headerPadding =
      EdgeInsets.all(0.0); // No padding in web
  static const EdgeInsets imagePadding =
      EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0); // margin: 5px 10px
  static const EdgeInsets actionsPadding =
      EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0);
  static const EdgeInsets commentSectionPadding =
      EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0); // padding: 0 10px
  static const EdgeInsets avatarPadding = EdgeInsets.all(10.0); // margin: 10px
  static const EdgeInsets textPadding = EdgeInsets.symmetric(vertical: 4.0);

  // Border radius - match web platform exactly
  static const double cardRadius = 20.0; // border-radius: 20px
  static const double avatarRadius = 35.0; // border-radius: 50% (circular)
  static const double imageRadius = 10.0; // border-radius: 10px
  static const double buttonRadius = 10.0; // border-radius: 10px
  static const double commentRadius = 10.0; // border-radius: 10px

  // Shadows and effects - match web platform exactly
  static const double blurSigma = 30.0; // backdrop-filter: blur(5px)
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
    return AppColors.getTextColor(context);
  }

  static Color getHintColor(BuildContext context) {
    return AppColors.getHintColor(context);
  }

  static Color getAvatarBorderColor(BuildContext context) {
    return AppColors.getAvatarBorderColor(context);
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
        _loadCurrentUserId();

        // Subscribe to real-time updates for this post
        WebSocketService().subscribeToPost(_currentPost.id);
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
    if (mounted) {
      setState(() {
        _currentUsername = username;
      });
    }
  }

  String _cleanPostContent(String content) {
    if (content.isEmpty) return content;
    String cleaned = _decodeHtmlEntities(content);
    cleaned = cleaned
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<br\s+/>', caseSensitive: false), '\n');

    return cleaned;
  }

  String _decodeHtmlEntities(String text) {
    if (text.isEmpty) return text;

    String result = text;
    String previousResult;
    int iterations = 0;
    do {
      previousResult = result;
      result = result.replaceAllMapped(
          RegExp(r'&amp;([a-zA-Z]+);', caseSensitive: false), (match) {
        return '&${match.group(1)};';
      });
      result = result.replaceAll(
          RegExp(r'&amp;amp;', caseSensitive: false), '&amp;');
      result = result.replaceAllMapped(
          RegExp(r'&amp;#(\d+);', caseSensitive: false), (match) {
        return '&#${match.group(1)};';
      });
      result = result.replaceAllMapped(
          RegExp(r'&amp;#x([0-9a-fA-F]+);', caseSensitive: false), (match) {
        return '&#x${match.group(1)};';
      });
      iterations++;
      if (iterations > 10) break;
    } while (result != previousResult);

    result = result.replaceAll(RegExp(r'&\$1;', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'&\$[0-9]+;', caseSensitive: false), '');

    final namedEntities = {
      '&excl;': '!',
      '&quot;': '"',
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&nbsp;': ' ',
      '&NewLine;': '\n',
      '&newline;': '\n',
      '&nl;': '\n',
      '&NL;': '\n',
      '&br;': '\n',
      '&BR;': '\n',
      '&copy;': '©',
      '&reg;': '®',
      '&trade;': '™',
      '&euro;': '€',
      '&pound;': '£',
      '&yen;': '¥',
      '&cent;': '¢',
      '&sect;': '§',
      '&para;': '¶',
      '&deg;': '°',
      '&plusmn;': '±',
      '&sup2;': '²',
      '&sup3;': '³',
      '&frac14;': '¼',
      '&frac12;': '½',
      '&frac34;': '¾',
      '&times;': '×',
      '&divide;': '÷',
      '&mdash;': '—',
      '&ndash;': '–',
      '&lsquo;': ''',
      '&rsquo;': ''',
      '&ldquo;': '"',
      '&rdquo;': '"',
      '&hellip;': '…',
      '&bull;': '•',
      '&rarr;': '→',
      '&larr;': '←',
      '&uarr;': '↑',
      '&darr;': '↓',
    };

    for (final entry in namedEntities.entries) {
      result = result.replaceAll(
          RegExp(entry.key, caseSensitive: false), entry.value);
    }

    result = result.replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');

    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code != null && code >= 0 && code <= 0x10FFFF) {
        return String.fromCharCode(code);
      }
      return match.group(0) ?? '';
    });

    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      if (code != null && code >= 0 && code <= 0x10FFFF) {
        return String.fromCharCode(code);
      }
      return match.group(0) ?? '';
    });

    return result;
  }

  Future<void> _toggleComments() async {
    setState(() {
      _showComments = !_showComments;
    });

    if (_showComments &&
        _currentPost.commentsList.isEmpty &&
        _currentPost.comments > 0) {
      setState(() {
        _isFetchingDetails = true;
      });
      try {
        final userId = await _authService.getStoredUserId();
        if (userId == null) throw Exception('User not logged in');
        final updatedPost = await _postService.fetchPost(
            postId: _currentPost.id, userId: userId);
        if (mounted) {
          setState(() {
            _currentPost = updatedPost;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _showComments = false;
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isFetchingDetails = false;
          });
        }
      }
    }
  }

  Future<void> _postComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _commentService.postComment(
        postId: _currentPost.id,
        userId: userId,
        content: commentText,
        onSuccess: (String commentId) async {
          if (commentId.isNotEmpty) {
            WebSocketService().sendNewComment(_currentPost.id, commentId);
          }

          Navigator.pop(context); // Dismiss loading indicador
          _commentController.clear();

          if (commentId.isNotEmpty) {
            try {
              final newComment = await _commentService.getComment(
                commentId: commentId,
                userId: userId,
              );
              if (mounted) {
                setState(() {
                  _currentPost = _currentPost.copyWith(
                    comments: _currentPost.comments + 1,
                    commentsList: [..._currentPost.commentsList, newComment],
                  );
                });
              }
            } catch (e) {
              _refreshPostAsFallback(userId);
            }
          } else {
            _refreshPostAsFallback(userId);
          }
        },
      );
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicador
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${TranslationKeys.failedToPostComment.tr}: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshPostAsFallback(String userId) async {
    try {
      final updatedPost =
          await _postService.fetchPost(postId: _currentPost.id, userId: userId);
      if (mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (refreshError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(
                TranslationKeys.commentPostedButCouldNotLoadDetails),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const TranslatedText(
          TranslationKeys.delete,
          style: TextStyle(color: Colors.white),
        ),
        content: const TranslatedText(
          TranslationKeys.confirmDeleteComment,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(
              TranslationKeys.cancel,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performDeleteComment(commentId);
            },
            child: const TranslatedText(
              TranslationKeys.delete,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteComment(String commentId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return;

      await _commentService.deleteComment(
        commentId: commentId,
        userId: userId,
      );

      // Refresh post details to get updated comment list
      final updatedPost = await _postService.fetchPost(
        postId: _currentPost.id,
        userId: userId,
      );

      Navigator.pop(context); // Dismiss loading indicator

      if (mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editComment(Comment comment) {
    final TextEditingController controller =
        TextEditingController(text: _decodeHtmlEntities(comment.content));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const TranslatedText(
          TranslationKeys.editComment,
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(
              TranslationKeys.cancel,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty) return;
              Navigator.of(context).pop();
              await _updateComment(comment.id, content);
            },
            child: const TranslatedText(
              TranslationKeys.save,
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateComment(String commentId, String content) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _commentService.updateComment(
        commentId: commentId,
        userId: userId,
        content: content,
      );

      final updatedPost = await _postService.fetchPost(
        postId: _currentPost.id,
        userId: userId,
      );

      Navigator.pop(context); // Dismiss loading indicator

      if (mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _reportComment(Comment comment) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const TranslatedText(
          TranslationKeys.reportComment,
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TranslatedText(
              TranslationKeys.confirmReportCommentMessage,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Reason...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(
              TranslationKeys.cancel,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(context).pop();
              await _performReportComment(comment.id, reason);
            },
            child: const TranslatedText(
              TranslationKeys.report,
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performReportComment(String commentId, String reason) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _commentService.reportComment(
        commentId: commentId,
        userId: userId,
        reason: reason,
      );

      Navigator.pop(context); // Dismiss loading indicator

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                TranslatedText(TranslationKeys.commentReportedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to report comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const TranslatedText(
          TranslationKeys.deletePost,
          style: TextStyle(color: Colors.white),
        ),
        content: const TranslatedText(
          TranslationKeys.confirmDeletePostMessage,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(
              TranslationKeys.cancel,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deletePost();
            },
            child: const TranslatedText(
              TranslationKeys.delete,
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
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text(
                  '${TranslationKeys.failedToDeletePost.tr}: ${e.toString()}'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onShare() async {
    final postUrl = '${ApiConstants.webBase}/post/${_currentPost.id}';
    await Clipboard.setData(ClipboardData(text: postUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: TranslatedText(TranslationKeys.postLinkCopiedToClipboard)),
      );
    }
  }

  void _onReport() {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const TranslatedText(
          TranslationKeys.reportPost,
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TranslatedText(
              TranslationKeys.confirmReportPostMessage,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Reason...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(
              TranslationKeys.cancel,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(context).pop();
              _performReportPost(reason);
            },
            child: const TranslatedText(
              TranslationKeys.report,
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performReportPost(String reason) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _postService.reportPost(
          postId: _currentPost.id, userId: userId, reason: reason);

      Navigator.pop(context); // Dismiss loading indicator

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.postReportedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text(
                  '${TranslationKeys.failedToReportPost.tr}: ${e.toString()}'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onHide() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const TranslatedText(
          TranslationKeys.hidePost,
          style: TextStyle(color: Colors.white),
        ),
        content: const TranslatedText(
          TranslationKeys.confirmHidePostMessage,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TranslatedText(
              TranslationKeys.cancel,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performHidePost();
            },
            child: const TranslatedText(
              TranslationKeys.hide,
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performHidePost() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      await _postService.hidePost(postId: _currentPost.id, userId: userId);

      Navigator.pop(context); // Dismiss loading indicator

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(TranslationKeys.postHiddenSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
        widget.onPostDeleted?.call(_currentPost.id);
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text(
                  '${TranslationKeys.failedToHidePost.tr}: ${e.toString()}'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onEdit() async {
    final result = await CreatePostWidget.show<String>(
      context: context,
      isEditing: true,
      postToEdit: _currentPost,
    );

    if (result == 'updated' && widget.onPostUpdated != null) {
      widget.onPostUpdated!(_currentPost.id);
    }
  }

  Future<void> _toggleLike() async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) throw Exception('User not logged in');

      final wasLiked = _currentPost.isLiked;
      final originalLikes = _currentPost.likes;

      setState(() {
        _currentPost = _currentPost.copyWith(
          likes: wasLiked ? _currentPost.likes - 1 : _currentPost.likes + 1,
          isLiked: !wasLiked,
        );
      });

      try {
        await _postService.toggleLike(postId: _currentPost.id, userId: userId);
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentPost = _currentPost.copyWith(
              likes: originalLikes,
              isLiked: wasLiked,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update like: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if keyboard is actually hidden and reposition floating input if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;

      if (bottomInset == 0 && _isKeyboardVisible) {
        // Keyboard was dismissed, hide floating input
        setState(() {
          _isKeyboardVisible = false;
        });
        _hideFloatingInput();
      } else if (bottomInset > 0 &&
          !_isKeyboardVisible &&
          _commentFocusNode.hasFocus) {
        // Keyboard appeared, show floating input
        setState(() {
          _isKeyboardVisible = true;
        });
        _showFloatingInput();
      }
    });

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
          imageUrl: UrlHelper.convertUrl(_currentPost.avatar!),
          width: PostCardStyles.avatarSize,
          height: PostCardStyles.avatarSize,
          fit: BoxFit.cover,
          httpHeaders: const {},
          placeholder: (context, url) => Image.asset('assets/images/icon.png',
              width: PostCardStyles.avatarSize,
              height: PostCardStyles.avatarSize,
              fit: BoxFit.cover),
          errorWidget: (context, url, error) {
            // Handle all errors including 404 (HttpExceptionWithStatus)
            return Image.asset(
              'assets/images/icon.png',
              width: PostCardStyles.avatarSize,
              height: PostCardStyles.avatarSize,
              fit: BoxFit.cover,
            );
          },
        );
      } else {
        avatarWidget = Image.asset(
          _currentPost.avatar!,
          width: PostCardStyles.avatarSize,
          height: PostCardStyles.avatarSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Image.asset(
              'assets/images/icon.png',
              width: PostCardStyles.avatarSize,
              height: PostCardStyles.avatarSize,
              fit: BoxFit.cover),
        );
      }
    } else {
      avatarWidget = Image.asset('assets/images/icon.png',
          width: PostCardStyles.avatarSize,
          height: PostCardStyles.avatarSize,
          fit: BoxFit.cover);
    }

    Widget? imageWidget;
    if (_currentPost.image != null && _currentPost.image!.isNotEmpty) {
      if (_currentPost.image!.startsWith('http')) {
        imageWidget = CachedNetworkImage(
          imageUrl: UrlHelper.convertUrl(_currentPost.image!),
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 200,
            color: Colors.white.withOpacity(0.1),
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            height: 200,
            color: Colors.white.withOpacity(0.1),
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
            color: Colors.white.withOpacity(0.1),
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
          color: PostCardStyles.getCardBackgroundColor(
              context), // background: rgba(var(--mode),.7)
          borderRadius: BorderRadius.circular(
              PostCardStyles.cardRadius), // border-radius: 20px
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PostCardStyles.cardRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: PostCardStyles.blurSigma,
                sigmaY: PostCardStyles.blurSigma), // backdrop-filter: blur(5px)
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section - match web platform's post_header exactly
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User interaction area (Avatar + Name/Date)
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_currentPost.userId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfileScreen(
                                    userId: _currentPost.userId,
                                    username: _currentPost.author,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // User avatar
                              Container(
                                width: PostCardStyles.avatarSize,
                                height: PostCardStyles.avatarSize,
                                margin: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: AppColors.avatarBackgroundColor,
                                  borderRadius: BorderRadius.circular(
                                      PostCardStyles.avatarRadius),
                                  border: Border.all(
                                    color: PostCardStyles.getAvatarBorderColor(
                                        context),
                                    width: PostCardStyles.avatarBorderWidth,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      PostCardStyles.avatarRadius),
                                  child: avatarWidget,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // User name and Date column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _decodeHtmlEntities(_currentPost.author),
                                      style: PostCardStyles.getAuthorTextStyle(
                                          context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    ListenableBuilder(
                                      listenable: TranslationService(),
                                      builder: (context, _) => Text(
                                        _formatTimestamp(
                                            _currentPost.createdAt),
                                        style: PostCardStyles
                                            .getTimestampTextStyle(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Actions section
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Builder(
                          builder: (context) {
                            if (_currentPost.userId == null) {
                              return const SizedBox.shrink();
                            }
                            return UnifiedMenu.createPostMenuButton(
                              context: context,
                              postId: _currentPost.id,
                              currentUserId: _currentUserId,
                              postUserId: _currentPost.userId!,
                              onDelete: _showDeleteDialog,
                              onEdit: _onEdit,
                              onShare: _onShare,
                              onReport: _onReport,
                              onHide: _onHide,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Content section - match web platform's post_content exactly
                Container(
                  padding: PostCardStyles.contentPadding, // padding: 10px 20px
                  child: Text(
                    _cleanPostContent(_currentPost.content),
                    style: PostCardStyles.getContentTextStyle(context),
                    textAlign: TextAlign.left,
                    softWrap: true,
                  ),
                ),
                // Image section - match web platform's post_uploads exactly
                if (imageWidget != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                        horizontal: 10.0, vertical: 5.0), // margin: 5px 10px
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                          PostCardStyles.imageRadius), // border-radius: 10px
                      child: imageWidget,
                    ),
                  ),

                // Actions section - match web platform's styling exactly
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Like button
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _toggleLike,
                            child: Icon(
                              _currentPost.isLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color:
                                  _currentPost.isLiked ? Colors.red : textColor,
                              size: PostCardStyles.iconSize,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('${_currentPost.likes}',
                              style: TextStyle(
                                  fontSize: PostCardStyles.smallFontSize,
                                  color: textColor)),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // Comment button
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _toggleComments,
                            child: Icon(Icons.comment,
                                color: textColor,
                                size: PostCardStyles.iconSize),
                          ),
                          const SizedBox(width: 4),
                          Text('${_currentPost.comments}',
                              style: TextStyle(
                                  fontSize: PostCardStyles.smallFontSize,
                                  color: textColor)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Comment Input Field (always visible)
                _buildCommentInputField(
                    textColor: textColor, hintColor: hintColor),
                // Show last comment if comments are not expanded and list is not empty
                if (!_showComments && _currentPost.commentsList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                        top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
                    child: CommentCard(
                      comment: _currentPost.commentsList.first,
                      currentUserId: _currentUserId,
                      onDelete: () =>
                          _deleteComment(_currentPost.commentsList.first.id),
                      onEdit: () =>
                          _editComment(_currentPost.commentsList.first),
                      onReport: () =>
                          _reportComment(_currentPost.commentsList.first),
                      textColor: textColor,
                    ),
                  ),
                // Collapsible list of comments
                if (_showComments) _buildCommentSection(),
                if (_currentPost.commentsList.length > 3)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showAllCommentsPopup,
                        child: TranslatedText(
                          TranslationKeys.expand,
                          style: TextStyle(color: textColor),
                        ),
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
    final translationService = TranslationService();

    // Handle negative differences (future dates) - shouldn't happen but handle gracefully
    if (diff.isNegative) {
      return translationService.translate(TranslationKeys.justNow);
    }

    // Less than 1 minute - show "Just now"
    if (diff.inSeconds < 60) {
      return translationService.translate(TranslationKeys.justNow);
    }
    // Less than 1 hour - show minutes
    else if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes;
      return '$minutes ${translationService.translate(TranslationKeys.minutesAgo)}';
    }
    // Less than 24 hours - show hours
    else if (diff.inHours < 24) {
      final hours = diff.inHours;
      return '$hours ${translationService.translate(TranslationKeys.hoursAgo)}';
    }
    // Less than 7 days - show days
    else if (diff.inDays < 7) {
      final days = diff.inDays;
      return '$days ${translationService.translate(TranslationKeys.daysAgo)}';
    }
    // Less than 30 days - show weeks
    else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    }
    // Less than 365 days - show months
    else if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
    // More than 365 days - show years
    else {
      final years = (diff.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }

  void _showAllCommentsPopup() {
    showDialog(
      context: context,
      builder: (context) {
        final textColor = PostCardStyles.getTextColor(context);
        return Dialog(
          backgroundColor: Colors.black.withOpacity(0.95),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    const TranslatedText(
                      TranslationKeys.allComments,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
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
                          onEdit: () => _editComment(comment),
                          onReport: () => _reportComment(comment),
                          textColor: textColor,
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
              child: ListenableBuilder(
                listenable: TranslationService(),
                builder: (context, _) {
                  return TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    decoration: InputDecoration(
                      hintText: TranslationService()
                          .translate(TranslationKeys.addCommentPlaceholder),
                      hintStyle: TextStyle(color: hintColor),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 0),
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
                  );
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
                  onEdit: () => _editComment(comment),
                  onReport: () => _reportComment(comment),
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
                border: Border.all(
                    color: PostCardStyles.getCardBorderColor(context)),
                boxShadow: [
                  BoxShadow(
                    color: PostCardStyles.getCardBackgroundColor(context)
                        .withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ListenableBuilder(
                        listenable: TranslationService(),
                        builder: (context, _) {
                          return TextField(
                            controller: _commentController,
                            focusNode: _commentFocusNode,
                            decoration: InputDecoration(
                              hintText: TranslationService().translate(
                                  TranslationKeys.addCommentPlaceholder),
                              hintStyle: TextStyle(
                                  color: PostCardStyles.getHintColor(context)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8.0, horizontal: 0),
                            ),
                            style: TextStyle(
                                color: PostCardStyles.getTextColor(context)),
                            onTap: () {
                              // Ensure any other context menus are closed
                              _popupMenuFocusNode.unfocus();
                            },
                            onSubmitted: (_) {
                              _postComment();
                            },
                          );
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

    // Unsubscribe from real-time updates for this post
    WebSocketService().unsubscribeFromPost(_currentPost.id);

    _commentFocusNode.dispose();
    _popupMenuFocusNode.dispose();
    _commentController.dispose();
    super.dispose();
  }
}
