import 'package:flutter/material.dart';
import 'dart:ui'; // Required for ImageFilter.blur

/// Centralized styling for the CustomBottomNavigationBar widget
class CustomBottomNavigationBarStyles {
  // Colors
  static const Color lightNavBarColor = Color(0x33FFFFFF); // White with 20% opacity
  static const Color darkNavBarColor = Color(0x4D000000); // Black with 30% opacity
  static const Color lightIconColor = Colors.white;
  static const Color darkIconColor = Colors.white;
  
  // Sizes
  static const double iconSize = 28.0;
  static const double addIconSize = 36.0;
  static const double barHeight = 50.0;
  static const double buttonSize = 50.0;
  static const double blurSigma = 10.0;
  
  // Padding and margins
  static const EdgeInsets bottomPadding = EdgeInsets.only(bottom: 10.0);
  static const EdgeInsets leftPadding = EdgeInsets.only(left: 20.0, bottom: 10.0);
  static const EdgeInsets rightPadding = EdgeInsets.only(right: 20.0, bottom: 10.0);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: 0);
  
  // Border radius
  static const double barRadius = 30.0;
  static const double buttonRadius = 30.0;
  
  // Theme-aware color getters
  static Color getNavBarColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkNavBarColor : lightNavBarColor;
  }
  
  static Color getIconColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkIconColor : lightIconColor;
  }
}

class CustomBottomNavigationBar extends StatelessWidget {
  final VoidCallback onStarPressed;
  final VoidCallback onAddPressed;
  final VoidCallback onFriendsPressed;
  final VoidCallback onChatPressed;
  final VoidCallback onNotificationsPressed;

  const CustomBottomNavigationBar({
    super.key,
    required this.onStarPressed,
    required this.onAddPressed,
    required this.onFriendsPressed,
    required this.onChatPressed,
    required this.onNotificationsPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final navBarColor = CustomBottomNavigationBarStyles.getNavBarColor(context);
    final iconColor = CustomBottomNavigationBarStyles.getIconColor(context);

    return Stack(
      children: [
        // Main navigation bar (star, add, friends)
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: CustomBottomNavigationBarStyles.bottomPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CustomBottomNavigationBarStyles.barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CustomBottomNavigationBarStyles.blurSigma, 
                  sigmaY: CustomBottomNavigationBarStyles.blurSigma
                ),
                child: Container(
                  height: CustomBottomNavigationBarStyles.barHeight,
                  decoration: BoxDecoration(
                    color: navBarColor,
                    borderRadius: BorderRadius.circular(CustomBottomNavigationBarStyles.barRadius),
                  ),
                  child: IntrinsicWidth(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.star, color: iconColor, size: CustomBottomNavigationBarStyles.iconSize),
                          onPressed: onStarPressed,
                          padding: CustomBottomNavigationBarStyles.buttonPadding,
                          constraints: const BoxConstraints(),
                        ),
                        Padding(
                          padding: CustomBottomNavigationBarStyles.buttonPadding,
                          child: GestureDetector(
                            onTap: onAddPressed,
                            child: Container(
                              width: CustomBottomNavigationBarStyles.buttonSize,
                              height: CustomBottomNavigationBarStyles.buttonSize,
                              decoration: const BoxDecoration(
                                color: Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.add,
                                  color: iconColor,
                                  size: CustomBottomNavigationBarStyles.addIconSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.group, color: iconColor, size: CustomBottomNavigationBarStyles.iconSize),
                          onPressed: onFriendsPressed,
                          padding: CustomBottomNavigationBarStyles.buttonPadding,
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
            padding: CustomBottomNavigationBarStyles.leftPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CustomBottomNavigationBarStyles.barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CustomBottomNavigationBarStyles.blurSigma, 
                  sigmaY: CustomBottomNavigationBarStyles.blurSigma
                ),
                child: Container(
                  height: CustomBottomNavigationBarStyles.barHeight,
                  width: CustomBottomNavigationBarStyles.buttonSize,
                  decoration: BoxDecoration(
                    color: navBarColor,
                    borderRadius: BorderRadius.circular(CustomBottomNavigationBarStyles.barRadius),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.chat_bubble, color: iconColor, size: CustomBottomNavigationBarStyles.iconSize),
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
            padding: CustomBottomNavigationBarStyles.rightPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CustomBottomNavigationBarStyles.barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CustomBottomNavigationBarStyles.blurSigma, 
                  sigmaY: CustomBottomNavigationBarStyles.blurSigma
                ),
                child: Container(
                  height: CustomBottomNavigationBarStyles.barHeight,
                  width: CustomBottomNavigationBarStyles.buttonSize,
                  decoration: BoxDecoration(
                    color: navBarColor,
                    borderRadius: BorderRadius.circular(CustomBottomNavigationBarStyles.barRadius),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.notifications, color: iconColor, size: CustomBottomNavigationBarStyles.iconSize),
                    onPressed: onNotificationsPressed,
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