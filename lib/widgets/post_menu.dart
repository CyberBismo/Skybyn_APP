import 'package:flutter/material.dart';
import 'dart:ui';

class PostMenu {
  static OverlayEntry? _currentOverlayEntry;
  
  static bool get isMenuOpen => _currentOverlayEntry != null;
  
  static void closeCurrentMenu() {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
    }
  }

  static Widget createMenuButton({
    required BuildContext context,
    required String postId,
    required String? currentUserId,
    required String postUserId,
    required VoidCallback onDelete,
    required VoidCallback onEdit,
    required VoidCallback onShare,
    required VoidCallback onReport,
  }) {
    return GestureDetector(
      onTap: () {
        if (_currentOverlayEntry != null) {
          closeCurrentMenu();
        } else {
          // Get the button position relative to the screen
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          final position = renderBox.localToGlobal(Offset.zero);
          _showMenu(
            context, 
            postId, 
            currentUserId,
            postUserId,
            onDelete,
            onEdit,
            onShare,
            onReport,
            position
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.more_vert,
          color: Colors.white.withOpacity(0.7),
          size: 20,
        ),
      ),
    );
  }

  static void _showMenu(
    BuildContext context, 
    String postId, 
    String? currentUserId,
    String postUserId,
    VoidCallback onDelete,
    VoidCallback onEdit,
    VoidCallback onShare,
    VoidCallback onReport,
    Offset buttonPosition
  ) {
    closeCurrentMenu();
    
    final bool isAuthor = currentUserId == postUserId;
    
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
              right: 10, // Position menu on the right side like user menu
              top: buttonPosition.dy + 30, // Position menu below the button
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
                        width: 150,
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
                            // Share option - available for all users
                            _buildMenuItem(
                              context: context,
                              icon: Icons.share,
                              label: 'Share',
                              onTap: () {
                                closeCurrentMenu();
                                onShare();
                              },
                            ),
                            // Report option - available for all users
                            _buildMenuItem(
                              context: context,
                              icon: Icons.report,
                              label: 'Report',
                              onTap: () {
                                closeCurrentMenu();
                                onReport();
                              },
                            ),
                            // Add divider if user is author (to separate author-only options)
                            if (isAuthor) ...[
                              Divider(
                                color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.white.withOpacity(0.2) 
                                  : Colors.black.withOpacity(0.1),
                              ),
                              // Edit option - only for post author
                              _buildMenuItem(
                                context: context,
                                icon: Icons.edit,
                                label: 'Edit',
                                onTap: () {
                                  closeCurrentMenu();
                                  onEdit();
                                },
                              ),
                              // Delete option - only for post author
                              _buildMenuItem(
                                context: context,
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                onTap: () {
                                  closeCurrentMenu();
                                  onDelete();
                                },
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
} 