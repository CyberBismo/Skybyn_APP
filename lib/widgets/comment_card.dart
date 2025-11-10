import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../services/theme_service.dart';
import 'unified_menu.dart';
import 'app_colors.dart';
import '../config/constants.dart';

/// Centralized styling for the CommentCard widget
class CommentCardStyles {
  // Sizes
  static const double borderRadius = 10.0;
  static const double avatarSize = 32.0;
  static const double avatarBorderWidth = 1.0;
  static const double iconSize = 16.0;
  static const double fontSize = 14.0;
  static const double smallFontSize = 12.0;
  
  // Padding and margins
  static const EdgeInsets cardPadding = EdgeInsets.all(12.0);
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(vertical: 4.0);
  static const EdgeInsets actionPadding = EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0);
  
  // Border radius
  static const double cardRadius = 10.0;
  
  // Shadows and effects
  static const double blurSigma = 8.0;
  static const double elevation = 0.0;
  
  // Animation
  static const Duration likeAnimationDuration = Duration(milliseconds: 150);
  static const Curve likeAnimationCurve = Curves.easeInOut;
}

class CommentCard extends StatelessWidget {
  final Comment comment;
  final String? currentUserId;
  final VoidCallback? onDelete;
  final Color? textColor;

  const CommentCard({
    super.key,
    required this.comment,
    this.currentUserId,
    this.onDelete,
    this.textColor,
  });

  /// Clean comment content by replacing HTML <br /> tags with newlines and decoding HTML entities
  /// This handles both new API format (plain text with \n) and old format (HTML <br /> tags)
  static String _cleanCommentContent(String content) {
    // First, decode HTML entities
    String cleaned = _decodeHtmlEntities(content);
    
    // Then replace various forms of <br> tags with newlines
    cleaned = cleaned
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<br\s+/>', caseSensitive: false), '\n');
    
    return cleaned;
  }

  /// Decode HTML entities to their actual characters
  /// Handles named entities (&excl;, &quot;, &amp;, etc.), numeric entities (&#33;, &#34;, etc.), and hex entities (&#x21;, &#x22;, etc.)
  /// Also handles double-encoded entities (like &amp;excl; which should decode to &excl; then to !)
  static String _decodeHtmlEntities(String text) {
    if (text.isEmpty) return text;
    
    String result = text;
    
    // First, handle double-encoded entities (like &amp;excl; -> &excl;)
    // This must be done first before decoding the actual entities
    // Handle multiple levels of encoding (e.g., &amp;amp;excl; -> &amp;excl; -> &excl;)
    String previousResult;
    int iterations = 0;
    do {
      previousResult = result;
      // Handle &amp;entity; -> &entity; (use replaceAllMapped for proper capture group handling)
      result = result.replaceAllMapped(RegExp(r'&amp;([a-zA-Z]+);', caseSensitive: false), (match) {
        return '&${match.group(1)};';
      });
      // Also handle &amp;amp; -> &amp; (double-encoded ampersand)
      result = result.replaceAll(RegExp(r'&amp;amp;', caseSensitive: false), '&amp;');
      // Handle &amp;#123; -> &#123; (double-encoded numeric entities)
      result = result.replaceAllMapped(RegExp(r'&amp;#(\d+);', caseSensitive: false), (match) {
        return '&#${match.group(1)};';
      });
      // Handle &amp;#x21; -> &#x21; (double-encoded hex entities)
      result = result.replaceAllMapped(RegExp(r'&amp;#x([0-9a-fA-F]+);', caseSensitive: false), (match) {
        return '&#x${match.group(1)};';
      });
      iterations++;
      if (iterations > 10) break; // Safety limit
    } while (result != previousResult); // Keep going until no more changes
    
    // Clean up any malformed entities that might have been created (like &$1;)
    // This handles cases where regex replacement might have failed
    result = result.replaceAll(RegExp(r'&\$1;', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'&\$[0-9]+;', caseSensitive: false), '');
    
    // Common HTML named entities (including NewLine and other common ones)
    // Note: &amp; must be decoded LAST to avoid conflicts with other entities
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
    
    // Replace named entities (case-insensitive) - decode &amp; LAST
    for (final entry in namedEntities.entries) {
      result = result.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }
    
    // Decode &amp; LAST to avoid conflicts
    result = result.replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
    
    // Decode numeric entities (&#33; format)
    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code != null && code >= 0 && code <= 0x10FFFF) {
        return String.fromCharCode(code);
      }
      return match.group(0) ?? '';
    });
    
    // Decode hex entities (&#x21; format, case-insensitive)
    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      if (code != null && code >= 0 && code <= 0x10FFFF) {
        return String.fromCharCode(code);
      }
      return match.group(0) ?? '';
    });
    
    return result;
  }

  @override
  Widget build(BuildContext context) {
    // Try to get theme service first, fallback to Theme.of(context)
    ThemeService? themeService;
    try {
      themeService = Provider.of<ThemeService>(context, listen: false);
    } catch (e) {
      // Provider not available, fallback to Theme.of(context)
    }
    
    final isDarkMode = themeService?.themeMode == ThemeMode.dark || 
                       (themeService?.themeMode == ThemeMode.system && 
                        Theme.of(context).brightness == Brightness.dark);
    
    final commentTextColor = textColor ?? AppColors.getTextColor(context);
    final secondaryTextColor = AppColors.getSecondaryTextColor(context);
    final iconColor = AppColors.getIconColor(context);
    


    Widget avatarWidget;
    if (comment.avatar != null && comment.avatar!.isNotEmpty) {
      avatarWidget = CachedNetworkImage(
        imageUrl: UrlHelper.convertUrl(comment.avatar!),
        width: CommentCardStyles.avatarSize,
        height: CommentCardStyles.avatarSize,
        fit: BoxFit.cover,
        httpHeaders: const {},
        placeholder: (context, url) => Image.asset(
            'assets/images/icon.png',
            width: CommentCardStyles.avatarSize,
            height: CommentCardStyles.avatarSize,
            fit: BoxFit.cover),
        errorWidget: (context, url, error) {
          // Handle all errors including 404 (HttpExceptionWithStatus)
          return Image.asset(
            'assets/images/icon.png',
            width: CommentCardStyles.avatarSize,
            height: CommentCardStyles.avatarSize,
            fit: BoxFit.cover,
          );
        },
      );
    } else {
      avatarWidget = Image.asset(
          'assets/images/icon.png',
          width: CommentCardStyles.avatarSize,
          height: CommentCardStyles.avatarSize,
          fit: BoxFit.cover);
    }

    return Stack(
      alignment: Alignment.centerRight, // Center the menu icon vertically
      children: [
        Padding(
          padding: CommentCardStyles.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: CommentCardStyles.avatarSize,
                height: CommentCardStyles.avatarSize,
                decoration: BoxDecoration(
                  color: AppColors.avatarBackgroundColor,
                  borderRadius: BorderRadius.circular(CommentCardStyles.borderRadius),
                  border: Border.all(color: AppColors.getAvatarBorderColor(context), width: CommentCardStyles.avatarBorderWidth),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CommentCardStyles.borderRadius),
                  child: avatarWidget,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center, // Center vertically
                  children: [
                    // Username without background
                    Text(
                      comment.username,
                      style: TextStyle(
                        fontSize: CommentCardStyles.fontSize,
                        fontWeight: FontWeight.bold,
                        color: commentTextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Comment text with background
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: AppColors.getBackgroundColor(context).withOpacity(0.1), // Theme-aware background
                          borderRadius: BorderRadius.circular(CommentCardStyles.borderRadius), // Rounded corners
                        ),
                        child: Text(
                          _cleanCommentContent(comment.content),
                          style: TextStyle(
                            fontSize: CommentCardStyles.fontSize,
                            color: commentTextColor,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Comment menu button
        if (currentUserId != null && onDelete != null)
          Padding(
            padding: const EdgeInsets.only(right: 8.0), // Add horizontal padding
            child: Builder(
              builder: (context) {
                return UnifiedMenu.createCommentMenuButton(
                  context: context,
                  commentId: comment.id,
                  currentUserId: currentUserId!,
                  commentUserId: comment.userId,
                  onDelete: onDelete!,
                );
              },
            ),
          ),
      ],
    );
  }
} 