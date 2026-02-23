import 'package:flutter/material.dart';

/// Centralized color constants for the entire app
class AppColors {
  // Background colors
  static const Color lightBackgroundColor =
      Color.fromRGBO(255, 255, 255, 0.2); // White with 20% opacity
  static const Color darkBackgroundColor =
      Color.fromRGBO(0, 0, 0, 0.30); // Black with 30% opacity
  static const Color transparentBackground = Colors.transparent;
  static const Color transparentColor = Colors.transparent;

  // Text colors - All white
  static const Color lightTextColor = Colors.white; // White for light mode
  static const Color darkTextColor = Colors.white; // White for dark mode
  static const Color lightSecondaryTextColor =
      Colors.white; // White for light mode
  static const Color darkSecondaryTextColor =
      Colors.white; // White for dark mode
  static const Color lightHintColor = Colors.white; // White for light mode
  static const Color darkHintColor = Colors.white; // White for dark mode

  // Icon colors - All white
  static const Color lightIconColor = Colors.white; // White for light mode
  static const Color darkIconColor = Colors.white; // White for dark mode
  static const Color searchIconColor = Colors.white; // White for all modes
  static const Color menuIconColor = Colors.white; // White for all modes

  // Card colors
  static const Color lightCardBackgroundColor =
      Color.fromRGBO(255, 255, 255, 0.15); // White with 15% opacity
  static const Color darkCardBackgroundColor =
      Color.fromRGBO(0, 0, 0, 0.30); // Black with 30% opacity
  static const Color lightCardBorderColor =
      Color.fromRGBO(0, 0, 0, 0.10); // Black with 10% opacity
  static const Color darkCardBorderColor =
      Color.fromRGBO(255, 255, 255, 0.15); // White with 15% opacity

  // Navigation bar colors
  static const Color lightNavBarColor =
      Color.fromRGBO(255, 255, 255, 0.15); // White with 15% opacity
  static const Color darkNavBarColor =
      Color.fromRGBO(0, 0, 0, 0.30); // Black with 30% opacity

  // Form colors
  static const Color lightFormColor =
      Color.fromRGBO(255, 255, 255, 0.15); // White with 15% opacity
  static const Color darkFormColor =
      Color.fromRGBO(0, 0, 0, 0.30); // Black with 30% opacity
  static const Color lightFieldColor = Colors.transparent;
  static const Color darkFieldColor = Colors.transparent;

  // Avatar colors
  static const Color lightAvatarBorderColor = Colors.white;
  static const Color darkAvatarBorderColor =
      Color.fromRGBO(0, 0, 0, 0.8); // Black with 80% opacity
  static const Color avatarBackgroundColor = Colors.black;

  // App bar colors - All white
  static const Color iconColor = Colors.white;
  static const Color backgroundColor = Colors.transparent;
  static const Color backdropColor = Colors.transparent;
  static const Color shadowColor = Colors.transparent;

  // Menu colors
  static const Color menuBorderColorLight =
      Color.fromRGBO(0, 0, 0, 0.15); // White with 15% opacity
  static const Color menuBorderColorDark =
      Color.fromRGBO(255, 255, 255, 0.15); // White with 15% opacity
  static const Color menuDividerColorLight =
      Color.fromRGBO(0, 0, 0, 0.15); // White with 15% opacity
  static const Color menuDividerColorDark =
      Color.fromRGBO(255, 255, 255, 0.15); // White with 15% opacity

  // Theme-aware color getters
  static Color getBackgroundColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkBackgroundColor : lightBackgroundColor;
  }

  static Color getTextColor(BuildContext context) {
    return Colors.white; // Always white
  }

  static Color getSecondaryTextColor(BuildContext context) {
    return Colors.white; // Always white
  }

  static Color getHintColor(BuildContext context) {
    return Colors.white; // Always white
  }

  static Color getIconColor(BuildContext context) {
    return Colors.white; // Always white
  }

  static Color getSearchIconColor(BuildContext context) {
    return Colors.white; // Always white
  }

  static Color getMenuIconColor(BuildContext context) {
    return Colors.white; // Always white
  }

  static Color getCardBackgroundColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBackgroundColor : lightCardBackgroundColor;
  }

  static Color getCardColor(BuildContext context) {
    return getCardBackgroundColor(context);
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
