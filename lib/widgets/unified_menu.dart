import 'package:flutter/material.dart';
import 'dart:ui';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/qr_scanner_screen.dart';
import '../screens/share_screen.dart';
import 'app_colors.dart';
import '../utils/translation_keys.dart';
import '../services/translation_service.dart';
import '../services/auth_service.dart';

/// Menu item definition
class MenuItem {
  final IconData icon;
  final String translationKey; // Store translation key instead of translated label
  final VoidCallback onTap;
  final bool isDestructive;

  const MenuItem({
    required this.icon,
    required this.translationKey,
    required this.onTap,
    this.isDestructive = false,
  });
}

/// Unified menu system that can handle different types of menus
class UnifiedMenu {
  static OverlayEntry? _currentOverlayEntry;
  
  static bool get isMenuOpen => _currentOverlayEntry != null;
  
  static void closeCurrentMenu() {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
    }
  }

  /// Create a menu button for posts
  static Widget createPostMenuButton({
    required BuildContext context,
    required String postId,
    required String? currentUserId,
    required String postUserId,
    required VoidCallback onDelete,
    required VoidCallback onEdit,
    required VoidCallback onShare,
    required VoidCallback onReport,
  }) {
    return _createMenuButton(
      context: context,
      onTap: () {
        final bool isAuthor = currentUserId == postUserId;
        final List<MenuItem> items = [
          MenuItem(
            icon: Icons.share,
            translationKey: TranslationKeys.share,
            onTap: onShare,
          ),
          MenuItem(
            icon: Icons.report,
            translationKey: TranslationKeys.report,
            onTap: onReport,
          ),
        ];

        if (isAuthor) {
          items.addAll([
            MenuItem(
              icon: Icons.edit,
              translationKey: TranslationKeys.edit,
              onTap: onEdit,
            ),
            MenuItem(
              icon: Icons.delete_outline,
              translationKey: TranslationKeys.delete,
              onTap: onDelete,
              isDestructive: true,
            ),
          ]);
        }

        _showMenu(context, items, position: 'right');
      },
    );
  }

  /// Create a menu button for comments
  static Widget createCommentMenuButton({
    required BuildContext context,
    required String commentId,
    required String? currentUserId,
    required String commentUserId,
    required VoidCallback onDelete,
  }) {
    // Only show menu button if the comment belongs to the current user
    if (currentUserId == null || currentUserId != commentUserId) {
      return const SizedBox.shrink();
    }

    return _createMenuButton(
      context: context,
      onTap: () {
        final List<MenuItem> items = [
          MenuItem(
            icon: Icons.delete_outline,
            translationKey: TranslationKeys.delete,
            onTap: onDelete,
            isDestructive: true,
          ),
        ];

        _showMenu(context, items, position: 'left');
      },
      iconSize: 16,
    );
  }

  /// Create a menu button for user menu
  static Widget createUserMenuButton({
    required BuildContext context,
    required double appBarHeight,
    required VoidCallback onLogout,
    required GlobalKey menuKey,
    VoidCallback? onSearchFormToggle,
    bool isSearchFormVisible = false,
  }) {
    return GestureDetector(
      key: menuKey,
      onTap: () async {
        if (_currentOverlayEntry != null) {
          closeCurrentMenu();
        } else {
          // Close search form if it's visible
          if (isSearchFormVisible && onSearchFormToggle != null) {
            onSearchFormToggle();
          }
          
          // Check user rank for admin access
          final authService = AuthService();
          final user = await authService.getStoredUserProfile();
          final userRank = user?.rank != null ? int.tryParse(user!.rank) : 0;
          final isAdmin = userRank != null && userRank > 5;
          
          final List<MenuItem> items = [
            MenuItem(
              icon: Icons.home,
              translationKey: TranslationKeys.home,
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              },
            ),
            MenuItem(
              icon: Icons.person,
              translationKey: TranslationKeys.profile,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            MenuItem(
              icon: Icons.settings,
              translationKey: TranslationKeys.settings,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
            MenuItem(
              icon: Icons.qr_code_scanner,
              translationKey: TranslationKeys.qrScanner,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const QrScannerScreen()),
                );
              },
            ),
            MenuItem(
              icon: Icons.share,
              translationKey: TranslationKeys.shareApp,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ShareScreen()),
                );
              },
            ),
            MenuItem(
              icon: Icons.logout,
              translationKey: TranslationKeys.logout,
              onTap: onLogout,
              isDestructive: true,
            ),
          ];

          _showMenu(context, items, position: 'right', topOffset: appBarHeight + 70);
        }
      },
      child: const Icon(
        Icons.menu,
        color: Colors.white,
        size: 24.0,
      ),
    );
  }

  /// Create a generic menu button
  static Widget _createMenuButton({
    required BuildContext context,
    required VoidCallback onTap,
    double iconSize = 20,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.more_vert,
          color: AppColors.getIconColor(context), // Theme-aware: black in light mode, white in dark mode
          size: iconSize,
        ),
      ),
    );
  }

  /// Show the menu with the given items
  static void _showMenu(
    BuildContext context,
    List<MenuItem> items, {
    String position = 'right',
    double? topOffset,
  }) {
    closeCurrentMenu();
    
    // Get the button position relative to the screen
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    
    _currentOverlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Full screen gesture detector to close menu when tapping outside
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  closeCurrentMenu();
                },
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // Menu content
            Positioned(
              left: position == 'left' ? buttonPosition.dx - 150 : null,
              right: position == 'right' ? 10 : null,
              top: topOffset ?? (buttonPosition.dy + (position == 'left' ? 20 : 30)),
              child: GestureDetector(
                onTap: () {
                  // Prevent closing when tapping on the menu itself
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 200,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.getMenuBorderColor(context),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < items.length; i++) ...[
                              _buildMenuItem(context, items[i]),
                              if (i < items.length - 1 && items[i + 1].isDestructive)
                                Divider(
                                  color: AppColors.getMenuDividerColor(context),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_currentOverlayEntry!);
  }

  /// Build a menu item
  static Widget _buildMenuItem(BuildContext context, MenuItem item) {
    return InkWell(
      onTap: () {
        closeCurrentMenu();
        item.onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              item.icon,
              color: item.isDestructive ? Colors.red : AppColors.getIconColor(context),
              size: 20,
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text(
                TranslationService().translate(item.translationKey),
                style: TextStyle(
                  color: item.isDestructive ? Colors.red : AppColors.getTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 