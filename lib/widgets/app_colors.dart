import 'package:flutter/material.dart';

/// Centralized color constants for the entire app
class AppColors {
  // Background colors
  static const Color lightBackgroundColor = Color(0x33FFFFFF); // White with 20% opacity
  static const Color darkBackgroundColor = Color(0x4D000000); // Black with 30% opacity
  static const Color transparentBackground = Colors.transparent;
  
  // Text colors
  static const Color lightTextColor = Colors.black; // Pure black for light mode
  static const Color darkTextColor = Colors.white; // Pure white for dark mode
  static const Color lightSecondaryTextColor = Color(0x99000000); // Black with 60% opacity
  static const Color darkSecondaryTextColor = Color(0xB3FFFFFF); // White with 70% opacity
  static const Color lightHintColor = Color(0x66000000); // Black with 40% opacity
  static const Color darkHintColor = Color(0x99FFFFFF); // White with 60% opacity
  
  // Icon colors
  static const Color lightIconColor = Colors.black; // Black for light mode
  static const Color darkIconColor = Colors.white; // White for dark mode
  static const Color searchIconColor = Colors.black; // Will be overridden by getter
  static const Color menuIconColor = Colors.black; // Will be overridden by getter
  
  // Card colors
  static const Color lightCardBackgroundColor = Color(0x26FFFFFF); // White with 15% opacity
  static const Color darkCardBackgroundColor = Color(0x4D000000); // Black with 30% opacity
  static const Color lightCardBorderColor = Color(0x1A000000); // Black with 10% opacity
  static const Color darkCardBorderColor = Color(0x26FFFFFF); // White with 15% opacity
  
  // Navigation bar colors
  static const Color lightNavBarColor = Color(0x26FFFFFF); // White with 15% opacity
  static const Color darkNavBarColor = Color(0x4D000000); // Black with 30% opacity
  
  // Form colors
  static const Color lightFormColor = Color(0x26FFFFFF); // White with 15% opacity
  static const Color darkFormColor = Color(0x4D000000); // Black with 30% opacity
  static const Color lightFieldColor = Colors.transparent;
  static const Color darkFieldColor = Colors.transparent;
  
  // Avatar colors
  static const Color lightAvatarBorderColor = Colors.white;
  static const Color darkAvatarBorderColor = Color(0xCC000000); // Black with 80% opacity
  static const Color avatarBackgroundColor = Colors.black;
  
  // App bar colors
  static const Color iconColor = Colors.white;
  static const Color backgroundColor = Colors.transparent;
  static const Color backdropColor = Colors.transparent;
  static const Color shadowColor = Colors.transparent;
  
  // Menu colors
  static const Color menuBorderColorLight = Color(0x26FFFFFF); // White with 15% opacity
  static const Color menuBorderColorDark = Color(0x26FFFFFF); // White with 15% opacity
  static const Color menuDividerColorLight = Color(0x26FFFFFF); // White with 15% opacity
  static const Color menuDividerColorDark = Color(0x26FFFFFF); // White with 15% opacity
  
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
  
  static Color getHintColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkHintColor : lightHintColor;
  }
  
  static Color getIconColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkIconColor : lightIconColor;
  }
  
  static Color getSearchIconColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkIconColor : lightIconColor;
  }
  
  static Color getMenuIconColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkIconColor : lightIconColor;
  }
  
  static Color getCardBackgroundColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBackgroundColor : lightCardBackgroundColor;
  }
  
  static Color getCardBorderColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBorderColor : lightCardBorderColor;
  }
  
  static Color getNavBarColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkNavBarColor : lightNavBarColor;
  }
  
  static Color getFormColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkFormColor : lightFormColor;
  }
  
  static Color getAvatarBorderColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkAvatarBorderColor : lightAvatarBorderColor;
  }
  
  static Color getMenuBorderColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? menuBorderColorDark : menuBorderColorLight;
  }
  
  static Color getMenuDividerColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? menuDividerColorDark : menuDividerColorLight;
  }
} 