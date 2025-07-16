import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/qr_scanner_screen.dart';


class UserMenu {
  static OverlayEntry? _currentOverlayEntry;
  
  static bool get isMenuOpen => _currentOverlayEntry != null;
  
  static void closeCurrentMenu() {
    print('🗑️ UserMenu.closeCurrentMenu() called');
    if (_currentOverlayEntry != null) {
      print('   - Removing current overlay entry');
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
      print('   - Overlay entry removed and cleared');
    } else {
      print('   - No current overlay entry to remove');
    }
  }

  static Widget createMenuButton({
    required BuildContext context,
    required double appBarHeight,
    required VoidCallback onLogout,
    required GlobalKey menuKey,
    VoidCallback? onAuthPressed,
    VoidCallback? onSearchFormToggle,
    bool isSearchFormVisible = false,
  }) {
    return GestureDetector(
      key: menuKey,
      onTap: () {
        print('☰ Menu icon clicked');
        if (_currentOverlayEntry != null) {
          // If menu is open, close it
          print('☰ Closing existing menu');
          closeCurrentMenu();
        } else {
          // If menu is closed, open it
          print('☰ Opening new menu');
          
          // Close search form if it's visible
          if (isSearchFormVisible && onSearchFormToggle != null) {
            print('☰ Closing search form before opening menu');
            onSearchFormToggle();
          }
          
          _showMenu(context, appBarHeight, onLogout);
        }
      },
      child: Icon(
        Icons.menu,
        color: Colors.white,
        size: 24.0,
      ),
    );
  }

  static void _showMenu(BuildContext context, double appBarHeight, VoidCallback onLogout) {
    print('☰ Showing user menu');
    
    // Close any existing menu first
    closeCurrentMenu();
    
    final completer = Completer<String?>();
    OverlayEntry? overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Full screen gesture detector to close menu when tapping outside
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  overlayEntry?.remove();
                  _currentOverlayEntry = null;
                },
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // Menu content
            Positioned(
              right: 10,
              top: appBarHeight + 70,
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
                            color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.2) 
                              : Colors.black.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMenuItem(
                              context: context,
                              icon: Icons.home,
                              label: 'Home',
                              onTap: () {
                                overlayEntry?.remove();
                                _currentOverlayEntry = null;
                                completer.complete('home');
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                                );
                              },
                            ),
                            _buildMenuItem(
                              context: context,
                              icon: Icons.person,
                              label: 'Profile',
                              onTap: () {
                                overlayEntry?.remove();
                                _currentOverlayEntry = null;
                                completer.complete('profile');
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => ProfileScreen()),
                                );
                              },
                            ),
                            _buildMenuItem(
                              context: context,
                              icon: Icons.settings,
                              label: 'Settings',
                              onTap: () {
                                overlayEntry?.remove();
                                _currentOverlayEntry = null;
                                completer.complete('settings');
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                                );
                              },
                            ),
                            _buildMenuItem(
                              context: context,
                              icon: Icons.qr_code,
                              label: 'Auth',
                              onTap: () {
                                overlayEntry?.remove();
                                _currentOverlayEntry = null;
                                completer.complete('auth');
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => const QrScannerScreen()),
                                );
                              },
                            ),

                            Divider(
                              color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white.withOpacity(0.2) 
                                : Colors.black.withOpacity(0.1),
                            ),
                            _buildMenuItem(
                              context: context,
                              icon: Icons.logout,
                              label: 'Logout',
                              onTap: () {
                                overlayEntry?.remove();
                                _currentOverlayEntry = null;
                                completer.complete('logout');
                                onLogout();
                              },
                            ),
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

    _currentOverlayEntry = overlayEntry;
    Overlay.of(context).insert(overlayEntry);
  }

  static Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // Keep the old methods for backward compatibility but mark them as deprecated
  @deprecated
  static Future<String?> show(BuildContext context, double appBarHeight, VoidCallback onLogout, GlobalKey menuKey, {VoidCallback? onAuthPressed, VoidCallback? onClose}) async {
    // This method is deprecated - use createMenuButton instead
    return null;
  }

  @deprecated
  static Future<String?> _showMenuAtDefaultPosition(BuildContext context, double appBarHeight, VoidCallback onLogout, VoidCallback? onAuthPressed, VoidCallback? onClose) async {
    // This method is deprecated - use createMenuButton instead
    return null;
  }

  @deprecated
  static Widget _buildMenuItemContent({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    // This method is deprecated - use _buildMenuItem instead
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
} 