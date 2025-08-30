import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../services/theme_service.dart';
import 'unified_menu.dart';
import 'app_colors.dart';

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
                          comment.content,
                          style: TextStyle(
                            fontSize: CommentCardStyles.fontSize,
                            color: commentTextColor,
                          ),
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