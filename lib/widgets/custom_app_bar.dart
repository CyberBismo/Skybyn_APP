import 'package:flutter/material.dart';
import 'dart:ui'; // Required for ImageFilter.blur
import 'unified_menu.dart';
import 'app_colors.dart';

/// Centralized app bar configuration and styling
class AppBarConfig {
  /// Returns the app bar height with platform-specific adjustments
  static double getAppBarHeight(BuildContext context) {
    // Web platform uses 75px height
    return 75.0;
  }

  /// Returns the total app bar height including status bar padding
  /// Note: This method is kept for backward compatibility but height is now calculated directly in build
  static double getTotalAppBarHeight(BuildContext context) {
    final appBarHeight = getAppBarHeight(context);
    final statusBarHeight = MediaQuery.of(context).padding.top;
    
    return appBarHeight + statusBarHeight;
  }

  /// App bar styling constants
  static const double androidHeightAdjustment = 20.0;
  static const double logoHeightMultiplier = 0.85;
  static const double blurSigma = 5.0; // Match web platform blur
}

/// Centralized styling for the CustomAppBar widget
class CustomAppBarStyles {
  // Sizes
  static const double searchIconSize = 24.0;
  static const double menuIconSize = 24.0;
  static const double blurSigma = 5.0; // Match web platform blur
  
  // Padding and margins
  static const EdgeInsets searchButtonPadding = EdgeInsets.symmetric(horizontal: 16.0);
  static const EdgeInsets menuButtonPadding = EdgeInsets.symmetric(horizontal: 16.0);
  static const EdgeInsets logoPadding = EdgeInsets.zero;
  
  // Border radius
  static const double searchButtonRadius = 0.0;
  static const double menuButtonRadius = 0.0;
  
  // Shadows and effects
  static const double elevation = 0.0;
  
  // Logo styling
  static const double logoHeightMultiplier = 0.85;
  static const BoxFit logoFit = BoxFit.contain;
  
  // Backdrop filter
  static const double backdropBlurSigma = 5.0; // Match web platform blur
}

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String logoPath;
  final VoidCallback onLogout;
  final VoidCallback onLogoPressed;
  final double? appBarHeight;
  final VoidCallback? onSearchFormToggle;
  final VoidCallback? onUserMenuToggle;
  final bool isSearchFormVisible;

  const CustomAppBar({
    super.key,
    required this.logoPath,
    required this.onLogout,
    required this.onLogoPressed,
    this.appBarHeight,
    this.onSearchFormToggle,
    this.onUserMenuToggle,
    this.isSearchFormVisible = false,
  });

  @override
  Size get preferredSize {
    // This will be called after build, so we can use a more dynamic approach
    return const Size.fromHeight(75.0 + 44.0); // Fallback for initial sizing
  }

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  final GlobalKey _menuKey = GlobalKey();

  void _handleSearchPressed() {
    print('🔍 Search icon clicked at ${DateTime.now()}');
    print('   - Search form visible: ${widget.isSearchFormVisible}');
    
    // Close user menu if it's open
    if (UnifiedMenu.isMenuOpen) {
      print('   - Closing user menu...');
      UnifiedMenu.closeCurrentMenu();
    }
    
    // Toggle search form
    print('   - Toggling search form');
    widget.onSearchFormToggle?.call();
    print('   - Search form toggle called');
    print('🔍 Search icon action completed');
  }

  @override
  Widget build(BuildContext context) {
    final appBarHeight = widget.appBarHeight ?? AppBarConfig.getAppBarHeight(context);
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final totalHeight = appBarHeight + statusBarHeight;
    
    return PreferredSize(
      preferredSize: Size.fromHeight(totalHeight),
      child: Container(
        height: totalHeight,
        decoration: const BoxDecoration(
          color: AppColors.backdropColor,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: CustomAppBarStyles.backdropBlurSigma, sigmaY: CustomAppBarStyles.backdropBlurSigma),
            child: Container(
              height: totalHeight,
              decoration: const BoxDecoration(
                color: AppColors.backdropColor,
              ),
              child: SafeArea(
                top: false, // Don't add top padding to move closer to status bar
                child: SizedBox(
                  height: appBarHeight,
                  child: Row(
                    children: [
                      // Search button - fixed width with padding
                      SizedBox(
                        width: 72.0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: IconButton(
                            onPressed: _handleSearchPressed,
                            icon: const Icon(
                              Icons.search, 
                              color: AppColors.iconColor, // White color, not affected by dark mode
                              size: CustomAppBarStyles.searchIconSize,
                            ),
                          ),
                        ),
                      ),
                      // Logo - centered with flex
                      Expanded(
                        child: Center(
                          child: GestureDetector(
                            onTap: widget.onLogoPressed,
                            child: Image.asset(
                              widget.logoPath,
                              height: appBarHeight * CustomAppBarStyles.logoHeightMultiplier,
                              fit: CustomAppBarStyles.logoFit,
                              color: null, // Ensure no color overlay
                              colorBlendMode: null, // Ensure no blend mode
                            ),
                          ),
                        ),
                      ),
                      // Menu button - fixed width with padding
                      SizedBox(
                        width: 72.0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: UnifiedMenu.createUserMenuButton(
                            context: context,
                            appBarHeight: appBarHeight,
                            onLogout: widget.onLogout,
                            menuKey: _menuKey,
                            onSearchFormToggle: widget.onSearchFormToggle,
                            isSearchFormVisible: widget.isSearchFormVisible,
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
      ),
    );
  }
} 