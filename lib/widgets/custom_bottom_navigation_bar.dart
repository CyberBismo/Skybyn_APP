import 'package:flutter/material.dart';
import 'dart:ui';
import 'app_colors.dart';

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
  final VoidCallback onStarPressed;
  final VoidCallback onAddPressed;
  final VoidCallback onFriendsPressed;
  final VoidCallback onChatPressed;
  final VoidCallback onNotificationsPressed;
  final int unreadNotificationCount;
  final GlobalKey? notificationButtonKey;

  const CustomBottomNavigationBar({
    super.key,
    required this.onStarPressed,
    required this.onAddPressed,
    required this.onFriendsPressed,
    required this.onChatPressed,
    required this.onNotificationsPressed,
    this.unreadNotificationCount = 0,
    this.notificationButtonKey,
  });

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
                          onPressed: onStarPressed,
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
                          onPressed: onFriendsPressed,
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
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble, color: iconColor, size: BottomNavBarStyles.iconSize),
                    onPressed: onChatPressed,
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
                        onPressed: onNotificationsPressed,
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