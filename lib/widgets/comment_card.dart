import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/comment.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'comment_menu.dart';

/// Centralized styling for the CommentCard widget
class CommentCardStyles {
  // Colors
  static const Color lightBackgroundColor = Color(0x4D000000); // Black with 30% opacity
  static const Color darkBackgroundColor = Color(0x4D000000); // Black with 30% opacity
  static const Color lightTextColor = Colors.white;
  static const Color darkTextColor = Colors.white;
  static const Color lightSecondaryTextColor = Color(0xB3FFFFFF); // White with 70% opacity
  static const Color darkSecondaryTextColor = Color(0xB3FFFFFF); // White with 70% opacity
  static const Color lightIconColor = Color(0xB3FFFFFF); // White with 70% opacity
  static const Color darkIconColor = Color(0xB3FFFFFF); // White with 70% opacity
  static const Color avatarBorderColor = Colors.white;
  static const Color avatarBackgroundColor = Colors.black;
  
  // Sizes
  static const double avatarSize = 32.0;
  static const double avatarBorderWidth = 0.5;
  static const double iconSize = 16.0;
  static const double fontSize = 14.0;
  static const double secondaryFontSize = 12.0;
  
  // Padding and margins
  static const EdgeInsets cardPadding = EdgeInsets.all(8.0);
  static const EdgeInsets contentPadding = EdgeInsets.only(left: 8.0);
  static const EdgeInsets textPadding = EdgeInsets.symmetric(vertical: 2.0);
  static const EdgeInsets actionsPadding = EdgeInsets.only(top: 4.0);
  
  // Border radius
  static const double cardRadius = 8.0;
  static const double avatarRadius = 8.0;
  
  // Text styles
  static const TextStyle authorTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  
  static const TextStyle commentTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.white,
  );
  
  static const TextStyle timestampTextStyle = TextStyle(
    fontSize: 12,
    color: Color(0xB3FFFFFF), // White with 70% opacity
  );
  
  static const TextStyle actionTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );
  
  // Theme-aware color getters
  static Color getBackgroundColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkBackgroundColor : lightBackgroundColor;
  }
  
  static Color getTextColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkTextColor : lightTextColor;
  }
  
  static Color getSecondaryTextColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkSecondaryTextColor : lightSecondaryTextColor;
  }
  
  static Color getIconColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkIconColor : lightIconColor;
  }
}

class CommentCard extends StatelessWidget {
  final Comment comment;
  final String? currentUserId;
  final VoidCallback? onDelete;
  final Color? textColor;

  const CommentCard({
    Key? key,
    required this.comment,
    this.currentUserId,
    this.onDelete,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final commentTextColor = textColor ?? CommentCardStyles.getTextColor(context);
    final secondaryTextColor = CommentCardStyles.getSecondaryTextColor(context);
    final iconColor = CommentCardStyles.getIconColor(context);

    Widget avatarWidget;
    if (comment.avatar != null && comment.avatar!.isNotEmpty) {
      avatarWidget = CachedNetworkImage(
        imageUrl: comment.avatar!,
        width: CommentCardStyles.avatarSize,
        height: CommentCardStyles.avatarSize,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[800]),
        errorWidget: (context, url, error) =>
            Icon(Icons.person, size: CommentCardStyles.iconSize, color: iconColor),
      );
    } else {
      avatarWidget = Icon(Icons.person, size: CommentCardStyles.iconSize, color: iconColor);
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
                  color: CommentCardStyles.avatarBackgroundColor,
                  borderRadius: BorderRadius.circular(CommentCardStyles.avatarRadius),
                  border: Border.all(color: CommentCardStyles.avatarBorderColor, width: CommentCardStyles.avatarBorderWidth),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CommentCardStyles.avatarRadius),
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
                      style: CommentCardStyles.authorTextStyle,
                    ),
                    const SizedBox(width: 8),
                    // Comment text with background
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1), // Transparent background
                          borderRadius: BorderRadius.circular(8.0), // Rounded corners
                        ),
                        child: Text(
                          comment.content,
                          style: CommentCardStyles.commentTextStyle,
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
                return CommentMenu.createMenuButton(
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