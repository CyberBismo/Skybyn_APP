import 'package:flutter/material.dart';
import 'dart:ui';
import 'app_colors.dart';
import 'left_panel.dart';
import 'right_panel.dart';
import 'chat_list_modal.dart';
import 'notification_overlay.dart';

/// Centralized styling for the CustomBottomNavigationBar widget
class BottomNavBarStyles {
  // Sizes
  static const double iconSize = 24.0;
  static const double addButtonSize = 56.0;
  static const double addButtonIconSize = 32.0;
  
  // Padding and margins
  static const EdgeInsets barPadding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: 8.0);
  
  // Border radius
  static const double barRadius = 25.0;
  static const double addButtonRadius = 28.0;
  
  // Shadows and effects
  static const double blurSigma = 10.0;
  static const double elevation = 0.0;
  
  // Animation
  static const Duration buttonAnimationDuration = Duration(milliseconds: 200);
  static const Curve buttonAnimationCurve = Curves.easeInOut;
}

class CustomBottomNavigationBar extends StatelessWidget {
  final VoidCallback onAddPressed;
  final int unreadNotificationCount;
  final int unreadChatCount;
  final GlobalKey? notificationButtonKey;
  final Function(int)? onUnreadCountChanged;

  const CustomBottomNavigationBar({
    super.key,
    required this.onAddPressed,
    this.unreadNotificationCount = 0,
    this.unreadChatCount = 0,
    this.notificationButtonKey,
    this.onUnreadCountChanged,
  });

  void _openLeftPanel(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close shortcuts panel',
      barrierColor: Colors.transparent,
      useRootNavigator: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenSize = MediaQuery.of(context).size;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(size: screenSize),
          child: const LeftPanel(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ));
        
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
    );
  }

  void _openFriendsModal(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close friends list',
      barrierColor: Colors.transparent,
      useRootNavigator: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenSize = MediaQuery.of(context).size;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(size: screenSize),
          child: const RightPanel(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ));
        
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
    );
  }

  void _openChatListModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ChatListModal(),
    );
  }

  void _toggleNotificationOverlay(BuildContext context) {
    if (UnifiedNotificationOverlay.isOverlayOpen) {
      UnifiedNotificationOverlay.closeCurrentOverlay();
    } else {
      if (notificationButtonKey != null) {
        UnifiedNotificationOverlay.showNotificationOverlay(
          context: context,
          notificationButtonKey: notificationButtonKey!,
          onUnreadCountChanged: onUnreadCountChanged,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const navBarColor = AppColors.lightNavBarColor; // Using light nav bar color for consistency
    const iconColor = Colors.white; // All icons are white and not affected by dark mode

    return Stack(
      children: [
        // Main navigation bar (star, add, friends)
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: BottomNavBarStyles.barPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BottomNavBarStyles.barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: BottomNavBarStyles.blurSigma, 
                  sigmaY: BottomNavBarStyles.blurSigma
                ),
                child: Container(
                  height: 50.0, // Assuming barHeight is 50.0
                  decoration: BoxDecoration(
                    color: navBarColor,
                    borderRadius: BorderRadius.circular(BottomNavBarStyles.barRadius),
                  ),
                  child: IntrinsicWidth(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.star, color: iconColor, size: BottomNavBarStyles.iconSize),
                          onPressed: () => _openLeftPanel(context),
                          padding: BottomNavBarStyles.buttonPadding,
                          constraints: const BoxConstraints(),
                        ),
                        Padding(
                          padding: BottomNavBarStyles.buttonPadding,
                          child: GestureDetector(
                            onTap: onAddPressed,
                            child: Container(
                              width: BottomNavBarStyles.addButtonSize,
                              height: BottomNavBarStyles.addButtonSize,
                              decoration: const BoxDecoration(
                                color: Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.add,
                                  color: iconColor,
                                  size: BottomNavBarStyles.addButtonIconSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.group, color: iconColor, size: BottomNavBarStyles.iconSize),
                          onPressed: () => _openFriendsModal(context),
                          padding: BottomNavBarStyles.buttonPadding,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Chat button (bottom left)
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: BottomNavBarStyles.barPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BottomNavBarStyles.barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: BottomNavBarStyles.blurSigma, 
                  sigmaY: BottomNavBarStyles.blurSigma
                ),
                child: Container(
                  height: 50.0, // Assuming barHeight is 50.0
                  width: 50.0,
                  decoration: BoxDecoration(
                    color: navBarColor,
                    borderRadius: BorderRadius.circular(BottomNavBarStyles.barRadius),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble, color: iconColor, size: BottomNavBarStyles.iconSize),
                        onPressed: () => _openChatListModal(context),
                      ),
                      if (unreadChatCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unreadChatCount > 99 ? '99+' : unreadChatCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Notifications button (bottom right)
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: BottomNavBarStyles.barPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BottomNavBarStyles.barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: BottomNavBarStyles.blurSigma, 
                  sigmaY: BottomNavBarStyles.blurSigma
                ),
                child: Container(
                  height: 50.0, // Assuming barHeight is 50.0
                  width: 50.0,
                  decoration: BoxDecoration(
                    color: navBarColor,
                    borderRadius: BorderRadius.circular(BottomNavBarStyles.barRadius),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        key: notificationButtonKey,
                        icon: const Icon(Icons.notifications, color: iconColor, size: BottomNavBarStyles.iconSize),
                        onPressed: () => _toggleNotificationOverlay(context),
                      ),
                      if (unreadNotificationCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unreadNotificationCount > 99 ? '99+' : unreadNotificationCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
} 