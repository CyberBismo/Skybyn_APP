import 'package:flutter/material.dart';
import 'dart:ui'; // Required for ImageFilter.blur
import 'user_menu.dart';

/// Centralized app bar configuration and styling
class AppBarConfig {
  /// Returns the app bar height with platform-specific adjustments
  static double getAppBarHeight(BuildContext context) {
    final baseAppBarHeight = AppBar().preferredSize.height;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    
    return isAndroid ? baseAppBarHeight + 20.0 : baseAppBarHeight;
  }

  /// Returns the total app bar height including status bar padding
  static double getTotalAppBarHeight(BuildContext context) {
    final appBarHeight = getAppBarHeight(context);
    final statusBarHeight = MediaQuery.of(context).padding.top;
    
    return appBarHeight + statusBarHeight;
  }

  /// App bar styling constants
  static const double androidHeightAdjustment = 20.0;
  static const double logoHeightMultiplier = 0.85;
  static const double blurSigma = 3.0;
  
  /// App bar colors
  static const Color iconColor = Colors.white;
  static const Color backgroundColor = Colors.transparent;
  
  /// App bar padding
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(horizontal: 16.0);
  static const EdgeInsets logoPadding = EdgeInsets.zero;
}

/// Centralized styling for the CustomAppBar widget
class CustomAppBarStyles {
  // Colors
  static const Color searchIconColor = Colors.white;
  static const Color menuIconColor = Colors.white;
  static const Color logoBackgroundColor = Colors.transparent;
  static const Color backdropColor = Colors.transparent;
  
  // Sizes
  static const double searchIconSize = 24.0;
  static const double menuIconSize = 24.0;
  static const double blurSigma = 3.0;
  
  // Padding and margins
  static const EdgeInsets searchButtonPadding = EdgeInsets.symmetric(horizontal: 16.0);
  static const EdgeInsets menuButtonPadding = EdgeInsets.symmetric(horizontal: 16.0);
  static const EdgeInsets logoPadding = EdgeInsets.zero;
  
  // Border radius
  static const double searchButtonRadius = 0.0;
  static const double menuButtonRadius = 0.0;
  
  // Shadows and effects
  static const double elevation = 0.0;
  static const Color shadowColor = Colors.transparent;
  
  // Logo styling
  static const double logoHeightMultiplier = 0.85;
  static const BoxFit logoFit = BoxFit.contain;
  
  // Backdrop filter
  static const double backdropBlurSigma = 3.0;
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
    return const Size.fromHeight(kToolbarHeight + 20.0);
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
    if (UserMenu.isMenuOpen) {
      print('   - Closing user menu...');
      UserMenu.closeCurrentMenu();
    }
    
    // Toggle search form
    print('   - Toggling search form');
    widget.onSearchFormToggle?.call();
    print('   - Search form toggle called');
    print('🔍 Search icon action completed');
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.appBarHeight ?? AppBarConfig.getAppBarHeight(context);
    return PreferredSize(
      preferredSize: Size.fromHeight(AppBarConfig.getTotalAppBarHeight(context)),
      child: Container(
        height: AppBarConfig.getTotalAppBarHeight(context),
        decoration: BoxDecoration(
          color: CustomAppBarStyles.backdropColor,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: CustomAppBarStyles.backdropBlurSigma, sigmaY: CustomAppBarStyles.backdropBlurSigma),
            child: Container(
              height: AppBarConfig.getTotalAppBarHeight(context),
              decoration: BoxDecoration(
                color: CustomAppBarStyles.backdropColor,
              ),
              child: SafeArea(
                child: Container(
                  height: height,
                  child: Row(
                    children: [
                      // Search button - fixed width with padding
                      SizedBox(
                        width: 72.0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: IconButton(
                            onPressed: _handleSearchPressed,
                            icon: Icon(
                              Icons.search, 
                              color: CustomAppBarStyles.searchIconColor,
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
                              height: height * CustomAppBarStyles.logoHeightMultiplier,
                              fit: CustomAppBarStyles.logoFit,
                            ),
                          ),
                        ),
                      ),
                      // Menu button - fixed width with padding
                      SizedBox(
                        width: 72.0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: UserMenu.createMenuButton(
                            context: context,
                            appBarHeight: height,
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