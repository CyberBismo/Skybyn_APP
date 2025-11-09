import 'package:flutter/material.dart';
import 'dart:ui'; // Required for ImageFilter.blur
import 'unified_menu.dart';
import 'app_colors.dart';
import '../services/auto_update_service.dart';
import '../services/auth_service.dart';
import 'permission_dialog.dart';
import 'update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';

/// Centralized app bar configuration and styling
class AppBarConfig {
  /// Returns the app bar height with platform-specific adjustments
  static double getAppBarHeight(BuildContext context) {
    // Web platform uses 60px height (reduced from 75px)
    return 60.0;
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
  final VoidCallback? onLogout; // Made optional since it's handled internally
  final VoidCallback onLogoPressed;
  final double? appBarHeight;
  final VoidCallback? onSearchFormToggle;
  final VoidCallback? onUserMenuToggle;
  final bool isSearchFormVisible;

  const CustomAppBar({
    super.key,
    required this.logoPath,
    this.onLogout, // Optional - will use internal handler if not provided
    required this.onLogoPressed,
    this.appBarHeight,
    this.onSearchFormToggle,
    this.onUserMenuToggle,
    this.isSearchFormVisible = false,
  });

  @override
  Size get preferredSize {
    // This will be called after build, so we can use a more dynamic approach
    return const Size.fromHeight(60.0 + 44.0); // Fallback for initial sizing - will be overridden by build method
  }

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  final GlobalKey _menuKey = GlobalKey();
  final _authService = AuthService();

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  }

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

  void _checkForUpdates() async {
    // Prevent multiple dialogs from showing at once
    if (AutoUpdateService.isDialogShowing) {
      print('⚠️ [CustomAppBar] Update dialog already showing, skipping...');
      UnifiedMenu.closeCurrentMenu();
      return;
    }

    try {
      // Check if we have permission to install from unknown sources
      if (!await AutoUpdateService.hasInstallPermission()) {
        // Show permission dialog
        final bool userGranted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PermissionDialog(
            onGranted: () {
              Navigator.of(context).pop(true);
            },
            onDenied: () {
              Navigator.of(context).pop(false);
            },
          ),
        ) ?? false;
        
        if (!userGranted) {
          UnifiedMenu.closeCurrentMenu();
          return;
        }
        
        // Try to request permission
        final bool permissionGranted = await AutoUpdateService.requestInstallPermission();
        if (!permissionGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: TranslatedText(TranslationKeys.permissionDeniedCannotCheckUpdates)),
            );
          }
          UnifiedMenu.closeCurrentMenu();
          return;
        }
      }
      
      // Check for updates
      final updateInfo = await AutoUpdateService.checkForUpdates();
      
      if (mounted && updateInfo != null && updateInfo.isAvailable) {
        // Only show if dialog is not already showing (don't check version history)
        if (AutoUpdateService.isDialogShowing) {
          print('⚠️ [CustomAppBar] Update dialog already showing, skipping...');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: TranslatedText(TranslationKeys.updateDialogAlreadyOpen)),
            );
          }
          UnifiedMenu.closeCurrentMenu();
          return;
        }

        // Mark dialog as showing immediately to prevent duplicates
        AutoUpdateService.setDialogShowing(true);
        
        // Get current version
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        
        // Mark this version as shown (so we don't spam)
        await AutoUpdateService.markUpdateShownForVersion(updateInfo.version);
        
        // Show update dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(
            currentVersion: currentVersion,
            latestVersion: updateInfo.version,
            releaseNotes: updateInfo.releaseNotes,
            downloadUrl: updateInfo.downloadUrl,
          ),
        ).then((_) {
          // Dialog closed, mark as not showing
          AutoUpdateService.setDialogShowing(false);
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: TranslatedText(TranslationKeys.noUpdatesAvailable)),
        );
      }
    } catch (e) {
      // Mark dialog as not showing on error
      AutoUpdateService.setDialogShowing(false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text('${TranslationKeys.errorCheckingUpdates.tr}: $e'),
            ),
          ),
        );
      }
    } finally {
      UnifiedMenu.closeCurrentMenu();
    }
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
          color: Colors.transparent,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: CustomAppBarStyles.backdropBlurSigma, sigmaY: CustomAppBarStyles.backdropBlurSigma),
            child: Container(
              height: totalHeight,
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              child: SafeArea(
                top: false, // Don't add top padding to move closer to status bar
                child: SizedBox(
                  height: appBarHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
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
                                  onLogout: widget.onLogout ?? _handleLogout,
                                  menuKey: _menuKey,
                                  onSearchFormToggle: widget.onSearchFormToggle,
                                  isSearchFormVisible: widget.isSearchFormVisible,
                                ),
                              ),
                            ),
                          ],
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