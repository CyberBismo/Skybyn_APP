import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/friend.dart';
import '../main.dart';
import 'friend_service.dart';
import 'auth_service.dart';

/// Service to manage floating chat bubble that appears outside the app
class FloatingChatBubbleService {
  static final FloatingChatBubbleService _instance = FloatingChatBubbleService._internal();
  factory FloatingChatBubbleService() => _instance;
  FloatingChatBubbleService._internal();

  static const String _positionKey = 'floating_bubble_position';
  static const String _enabledKey = 'floating_bubble_enabled';
  static const MethodChannel _channel = MethodChannel('no.skybyn.app/floating_bubble');
  
  OverlaySupportEntry? _bubbleOverlay;
  Friend? _currentFriend;
  int _unreadCount = 0;
  String? _lastMessage;
  bool _isShowing = false;
  Offset _position = const Offset(20, 200); // Default position
  bool _isEnabled = true;
  bool _useNativeOverlay = false; // Use native overlay on Android

  Friend? get currentFriend => _currentFriend;
  int get unreadCount => _unreadCount;
  bool get isShowing => _isShowing;
  bool get isEnabled => _isEnabled;

  /// Initialize the service and load saved preferences
  Future<void> initialize() async {
    await _loadPreferences();
    if (Platform.isAndroid) {
      _useNativeOverlay = true; // Use native overlay on Android for system-level
    }
  }

  /// Load saved position and enabled state
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionX = prefs.getDouble('${_positionKey}_x');
      final positionY = prefs.getDouble('${_positionKey}_y');
      if (positionX != null && positionY != null) {
        _position = Offset(positionX, positionY);
      }
      _isEnabled = prefs.getBool(_enabledKey) ?? true;
    } catch (e) {
      // Use defaults if loading fails
    }
  }

  /// Save bubble position
  Future<void> _savePosition(Offset position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${_positionKey}_x', position.dx);
      await prefs.setDouble('${_positionKey}_y', position.dy);
      _position = position;
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Check if overlay permission is granted (Android only)
  Future<bool> checkOverlayPermission() async {
    if (Platform.isAndroid) {
      return await Permission.systemAlertWindow.isGranted;
    }
    // iOS doesn't support system overlays, but we can show in-app overlay
    return true;
  }

  /// Request overlay permission (Android only)
  Future<bool> requestOverlayPermission() async {
    if (Platform.isAndroid) {
      if (await Permission.systemAlertWindow.isGranted) {
        return true;
      }
      return await Permission.systemAlertWindow.request().isGranted;
    }
    // iOS doesn't support system overlays
    return true;
  }

  /// Show floating chat bubble
  Future<void> showBubble({
    required Friend friend,
    required String message,
    int unreadCount = 1,
  }) async {
    if (!_isEnabled) {
      return;
    }

    _currentFriend = friend;
    _lastMessage = message;
    _unreadCount = unreadCount;
    _isShowing = true;

    // Dismiss existing bubble if any
    await dismissBubble();

    // Use native overlay on Android for system-level overlay
    if (_useNativeOverlay && Platform.isAndroid) {
      // Check permission on Android
      final hasPermission = await checkOverlayPermission();
      if (!hasPermission) {
        final granted = await requestOverlayPermission();
        if (!granted) {
          // Permission denied, fallback to in-app overlay
          _useNativeOverlay = false;
        }
      }
      
      if (_useNativeOverlay) {
        try {
          final displayName = friend.nickname.isNotEmpty ? friend.nickname : friend.username;
          await _channel.invokeMethod('showBubble', {
            'friendId': friend.id,
            'friendName': displayName,
            'avatarUrl': friend.avatar,
            'unreadCount': unreadCount,
            'message': message,
          });
          return;
        } catch (e) {
          // Fallback to in-app overlay if native fails
          _useNativeOverlay = false;
        }
      }
    }

    // Use in-app overlay (iOS or Android fallback)
    // Check permission on Android
    if (Platform.isAndroid) {
      final hasPermission = await checkOverlayPermission();
      if (!hasPermission) {
        final granted = await requestOverlayPermission();
        if (!granted) {
          // Permission denied, can't show bubble
          return;
        }
      }
    }

    // Create and show the bubble using overlay_support
    _bubbleOverlay = showOverlay(
      (context, t) => _FloatingChatBubbleWidget(
        friend: friend,
        message: message,
        unreadCount: unreadCount,
        position: _position,
        onPositionChanged: _savePosition,
        onTap: _handleBubbleTap,
        onDismiss: dismissBubble,
      ),
      duration: const Duration(days: 365), // Show indefinitely until dismissed
      key: const ValueKey('floating_chat_bubble'),
    );
  }

  /// Update bubble with new message
  Future<void> updateBubble({
    required Friend friend,
    required String message,
    int? unreadCount,
  }) async {
    if (!_isShowing || _currentFriend?.id != friend.id) {
      // Show new bubble if different friend or not showing
      await showBubble(
        friend: friend,
        message: message,
        unreadCount: unreadCount ?? (_unreadCount + 1),
      );
      return;
    }

    // Update existing bubble
    _lastMessage = message;
    if (unreadCount != null) {
      _unreadCount = unreadCount;
    } else {
      _unreadCount++;
    }

    // Use native overlay on Android
    if (_useNativeOverlay && Platform.isAndroid) {
      try {
        final displayName = friend.nickname.isNotEmpty ? friend.nickname : friend.username;
        await _channel.invokeMethod('updateBubble', {
          'friendId': friend.id,
          'friendName': displayName,
          'avatarUrl': friend.avatar,
          'unreadCount': _unreadCount,
          'message': message,
        });
        return;
      } catch (e) {
        // Fallback to in-app overlay
        _useNativeOverlay = false;
      }
    }

    // Recreate bubble with updated info (in-app overlay)
    dismissBubble();
    await showBubble(
      friend: friend,
      message: message,
      unreadCount: _unreadCount,
    );
  }

  /// Dismiss the floating bubble
  Future<void> dismissBubble() async {
    // Dismiss native overlay on Android
    if (_useNativeOverlay && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('hideBubble');
      } catch (e) {
        // Ignore errors
      }
    }
    
    // Dismiss in-app overlay
    _bubbleOverlay?.dismiss();
    _bubbleOverlay = null;
    _isShowing = false;
    _unreadCount = 0;
    _lastMessage = null;
  }

  /// Handle bubble tap - navigate to chat screen
  Future<void> _handleBubbleTap() async {
    if (_currentFriend == null) {
      return;
    }

    // Dismiss bubble
    dismissBubble();

    // Navigate to chat screen
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamed(
        '/chat',
        arguments: {'friend': _currentFriend},
      );
    }
  }

  /// Enable/disable floating bubble feature
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {
      // Ignore save errors
    }

    if (!enabled) {
      dismissBubble();
    }
  }

  /// Clear unread count (when messages are read)
  Future<void> clearUnreadCount() async {
    _unreadCount = 0;
    // Update bubble if showing
    if (_isShowing && _currentFriend != null && _lastMessage != null) {
      await updateBubble(
        friend: _currentFriend!,
        message: _lastMessage!,
        unreadCount: 0,
      );
    }
  }
}

/// Floating chat bubble widget
class _FloatingChatBubbleWidget extends StatefulWidget {
  final Friend friend;
  final String message;
  final int unreadCount;
  final Offset position;
  final Function(Offset) onPositionChanged;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _FloatingChatBubbleWidget({
    required this.friend,
    required this.message,
    required this.unreadCount,
    required this.position,
    required this.onPositionChanged,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_FloatingChatBubbleWidget> createState() => _FloatingChatBubbleWidgetState();
}

class _FloatingChatBubbleWidgetState extends State<_FloatingChatBubbleWidget>
    with SingleTickerProviderStateMixin {
  late Offset _position;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _position = widget.position;
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
      
      // Keep bubble within screen bounds
      final screenSize = MediaQuery.of(context).size;
      _position = Offset(
        _position.dx.clamp(0.0, screenSize.width - 80),
        _position.dy.clamp(0.0, screenSize.height - 80),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;
    _controller.reverse();
    
    // Snap to nearest edge
    final screenSize = MediaQuery.of(context).size;
    final centerX = screenSize.width / 2;
    
    setState(() {
      _position = Offset(
        _position.dx < centerX ? 10.0 : screenSize.width - 80,
        _position.dy,
      );
    });
    
    widget.onPositionChanged(_position);
  }

  void _onPanStart(DragStartDetails details) {
    _isDragging = true;
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.friend.nickname.isNotEmpty
        ? widget.friend.nickname
        : widget.friend.username;
    
    final messagePreview = widget.message.length > 30
        ? '${widget.message.substring(0, 30)}...'
        : widget.message;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanStart: _onPanStart,
        onTap: _isDragging ? null : widget.onTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Avatar
                  ClipOval(
                    child: widget.friend.avatar.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.friend.avatar,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[300],
                              child: Icon(
                                Icons.person,
                                color: Colors.grey[600],
                                size: 40,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[300],
                              child: Icon(
                                Icons.person,
                                color: Colors.grey[600],
                                size: 40,
                              ),
                            ),
                            fit: BoxFit.cover,
                            width: 80,
                            height: 80,
                          )
                        : Container(
                            color: Colors.blue[400],
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                  ),
                  // Unread badge
                  if (widget.unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          widget.unreadCount > 99 ? '99+' : widget.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  // Message preview tooltip (shown on long press or hover)
                  if (!_isDragging)
                    Positioned(
                      bottom: 90,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                messagePreview,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

