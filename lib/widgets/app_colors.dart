import 'package:flutter/material.dart';
import '../utils/color_utils.dart';
import 'background_gradient.dart';

/// Centralized color constants for the entire app
class AppColors {
  // Background colors
  static const Color lightBackgroundColor =
      Color.fromRGBO(255, 255, 255, 0.2); // White with 20% opacity
  static const Color darkBackgroundColor =
      Color.fromRGBO(0, 0, 0, 0.30); // Black with 30% opacity
  static const Color transparentBackground = Colors.transparent;

  // Static colors for cases where context is not available or gradients not used
  static const Color defaultContentColor = Colors.white;
  static const Color avatarBackgroundColor = Colors.black;

  // Theme-aware color getters
  static Color getBackgroundColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      return bgTheme.isDark 
          ? Colors.black.withOpacity(0.05) 
          : Colors.white.withOpacity(0.05);
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkBackgroundColor : lightBackgroundColor;
  }

  static Color getTextColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      if (bgTheme.isDefaultBackground) {
        return Colors.white;
      }
      return ColorUtils.getContrastingColor(bgTheme.topColor);
    }
    return defaultContentColor;
  }

  static Color getSecondaryTextColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      if (bgTheme.isDefaultBackground) {
        return Colors.white.withOpacity(0.7);
      }
      return ColorUtils.getContrastingColor(bgTheme.topColor).withOpacity(0.7);
    }
    return defaultContentColor.withOpacity(0.7);
  }

  static Color getHintColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      if (bgTheme.isDefaultBackground) {
        return Colors.white.withOpacity(0.6);
      }
      return ColorUtils.getContrastingColor(bgTheme.topColor).withOpacity(0.6);
    }
    return defaultContentColor.withOpacity(0.6);
  }

  static Color getIconColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      if (bgTheme.isDefaultBackground) {
        return Colors.white;
      }
      return ColorUtils.getContrastingColor(bgTheme.bottomColor);
    }
    return defaultContentColor;
  }

  static Color getSearchIconColor(BuildContext context) {
    return getIconColor(context);
  }

  static Color getMenuIconColor(BuildContext context) {
    return getIconColor(context);
  }

  static Color getCardBackgroundColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      return bgTheme.isDark 
          ? Colors.white.withOpacity(0.1) 
          : Colors.black.withOpacity(0.1);
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBackgroundColor : lightCardBackgroundColor;
  }

  static Color getCardBorderColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      return bgTheme.isDark 
          ? Colors.white.withOpacity(0.2) 
          : Colors.black.withOpacity(0.2);
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkCardBorderColor : lightCardBorderColor;
  }

  static Color getNavBarColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      return bgTheme.isDark 
          ? Colors.black.withOpacity(0.15) 
          : Colors.white.withOpacity(0.15);
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkNavBarColor : lightNavBarColor;
  }

  static Color getFormColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      return bgTheme.isDark 
          ? Colors.white.withOpacity(0.05) 
          : Colors.black.withOpacity(0.05);
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkFormColor : lightFormColor;
  }

  static Color getAvatarBorderColor(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    if (bgTheme != null) {
      return bgTheme.isDark ? Colors.black.withOpacity(0.8) : Colors.white;
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkAvatarBorderColor : lightAvatarBorderColor;
  }

  static Color getMenuBorderColor(BuildContext context) {
    return getCardBorderColor(context);
  }

  static Color getMenuDividerColor(BuildContext context) {
    return getCardBorderColor(context);
  }

  // Original constants kept for backward compatibility if needed in static contexts
  static const Color lightTextColor = Colors.white;
  static const Color darkTextColor = Colors.white;
  static const Color lightSecondaryTextColor = Colors.white;
  static const Color darkSecondaryTextColor = Colors.white;
  static const Color lightHintColor = Colors.white;
  static const Color darkHintColor = Colors.white;
  static const Color lightIconColor = Colors.white;
  static const Color darkIconColor = Colors.white;
  static const Color searchIconColor = Colors.white;
  static const Color menuIconColor = Colors.white;
  static const Color lightCardBackgroundColor = Color.fromRGBO(255, 255, 255, 0.15);
  static const Color darkCardBackgroundColor = Color.fromRGBO(0, 0, 0, 0.30);
  static const Color lightCardBorderColor = Color.fromRGBO(0, 0, 0, 0.10);
  static const Color darkCardBorderColor = Color.fromRGBO(255, 255, 255, 0.15);
  static const Color lightNavBarColor = Color.fromRGBO(255, 255, 255, 0.15);
  static const Color darkNavBarColor = Color.fromRGBO(0, 0, 0, 0.30);
  static const Color lightFormColor = Color.fromRGBO(255, 255, 255, 0.15);
  static const Color darkFormColor = Color.fromRGBO(0, 0, 0, 0.30);
  static const Color lightAvatarBorderColor = Colors.white;
  static const Color darkAvatarBorderColor = Color.fromRGBO(0, 0, 0, 0.8);
  static const Color menuBorderColorLight = Color.fromRGBO(0, 0, 0, 0.15);
  static const Color menuBorderColorDark = Color.fromRGBO(255, 255, 255, 0.15);
  static const Color menuDividerColorLight = Color.fromRGBO(0, 0, 0, 0.15);
  static const Color menuDividerColorDark = Color.fromRGBO(255, 255, 255, 0.15);
}
