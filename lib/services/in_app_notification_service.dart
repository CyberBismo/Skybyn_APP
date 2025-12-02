import 'package:flutter/material.dart';
import '../widgets/in_app_notification.dart';
import '../models/friend.dart';
import '../main.dart';

/// Service to manage in-app notifications for all notification types
class InAppNotificationService {
  static final InAppNotificationService _instance = InAppNotificationService._internal();
  factory InAppNotificationService() => _instance;
  InAppNotificationService._internal();

  OverlayEntry? _currentNotification;
  String? _currentNotificationId;
  String? _currentNotificationType;

  /// Check if a specific chat screen is currently in focus
  bool isChatScreenInFocus(String friendId) {
    try {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return false;

      final context = navigatorKey.currentContext;
      if (context == null) return false;

      // Get the current route from the context
      final currentRoute = ModalRoute.of(context);
      if (currentRoute == null || !currentRoute.isCurrent) return false;

      // Check route name
      final routeSettings = currentRoute.settings;
      if (routeSettings.name != '/chat') return false;

      // Check if the current route arguments contain this friend
      final args = routeSettings.arguments as Map<String, dynamic>?;
      if (args == null) return false;
      
      final friend = args['friend'] as Friend?;
      if (friend == null) return false;
      
      // Compare friend IDs
      return friend.id == friendId;
    } catch (e) {
      // If route checking fails, assume not in focus to be safe
      return false;
    }
  }

  /// Show in-app notification for chat messages
  void showChatNotification({
    required Friend friend,
    required String message,
    required VoidCallback onTap,
  }) {
    // Don't show if chat screen for this friend is already in focus
    if (isChatScreenInFocus(friend.id)) {
      return;
    }

    _showNotification(
      title: friend.nickname.isNotEmpty ? friend.nickname : friend.username,
      body: message,
      avatarUrl: friend.avatar,
      icon: Icons.chat,
      iconColor: Colors.blue,
      notificationId: 'chat_${friend.id}',
      notificationType: 'chat',
      onTap: onTap,
    );
  }

  /// Show in-app notification for any notification type
  void showNotification({
    required String title,
    required String body,
    String? avatarUrl,
    IconData? icon,
    Color? iconColor,
    String? notificationId,
    String? notificationType,
    required VoidCallback onTap,
  }) {
    _showNotification(
      title: title,
      body: body,
      avatarUrl: avatarUrl,
      icon: icon,
      iconColor: iconColor,
      notificationId: notificationId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      notificationType: notificationType ?? 'generic',
      onTap: onTap,
    );
  }

  void _showNotification({
    required String title,
    required String body,
    String? avatarUrl,
    IconData? icon,
    Color? iconColor,
    required String notificationId,
    required String notificationType,
    required VoidCallback onTap,
  }) {
    // Dismiss any existing notification
    dismissNotification();

    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    _currentNotificationId = notificationId;
    _currentNotificationType = notificationType;

    _currentNotification = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: InAppNotification(
              title: title,
              body: body,
              avatarUrl: avatarUrl,
              icon: icon,
              iconColor: iconColor,
              notificationId: notificationId,
              onTap: () {
                dismissNotification();
                onTap();
              },
              onDismiss: dismissNotification,
            ),
          ),
        ),
      ),
    );

    overlayState.insert(_currentNotification!);
  }

  /// Dismiss the current notification
  void dismissNotification() {
    _currentNotification?.remove();
    _currentNotification = null;
    _currentNotificationId = null;
    _currentNotificationType = null;
  }

  /// Check if a notification is currently showing
  bool get isShowing => _currentNotification != null;

  /// Get the notification ID of the current notification
  String? get currentNotificationId => _currentNotificationId;

  /// Get the notification type of the current notification
  String? get currentNotificationType => _currentNotificationType;
}
