import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import '../services/auth_service.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'app_colors.dart';

class Notification {
  final String id;
  final String username;
  final String nickname;
  final String avatar;
  final int date;
  final String content;
  final int read;
  final String type;
  final String? profile;
  final String? post;

  Notification({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.date,
    required this.content,
    required this.read,
    required this.type,
    this.profile,
    this.post,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['notiID']?.toString() ?? '',
      username: json['username']?.toString() ?? 'System',
      nickname: json['nickname']?.toString() ?? json['username']?.toString() ?? 'System',
      avatar: json['avatar']?.toString() ?? '',
      date: int.tryParse(json['date']?.toString() ?? '0') ?? 0,
      content: json['content']?.toString() ?? '',
      read: int.tryParse(json['read']?.toString() ?? '0') ?? 0,
      type: json['type']?.toString() ?? '',
      profile: json['profile']?.toString(),
      post: json['post']?.toString(),
    );
  }
}

/// Unified notification overlay system that positions relative to bottom nav bar
class UnifiedNotificationOverlay {
  static OverlayEntry? _currentOverlayEntry;
  static _NotificationOverlayState? _currentState;
  
  static bool get isOverlayOpen => _currentOverlayEntry != null;
  
  static void closeCurrentOverlay() {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
      _currentState = null;
    }
  }

  /// Show notification overlay positioned relative to the notification button
  static void showNotificationOverlay({
    required BuildContext context,
    required GlobalKey notificationButtonKey,
    Function(int)? onUnreadCountChanged,
  }) {
    closeCurrentOverlay();
    
    // Get the button position relative to the screen
    final RenderBox? renderBox = notificationButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    // Calculate overlay position - above the bottom nav bar
    final overlayHeight = screenHeight * 0.6; // 60% of screen height
    final bottomOffset = bottomPadding + 50.0 + 16.0; // Bottom nav height + padding + gap
    final overlayTop = screenHeight - overlayHeight - bottomOffset;
    
    _currentOverlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Full screen gesture detector to close overlay when tapping outside
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  closeCurrentOverlay();
                },
                child: Container(
                  color: Colors.black54,
                ),
              ),
            ),
            // Notification overlay content
            Positioned(
              left: 16,
              right: 16,
              top: overlayTop,
              bottom: bottomOffset,
              child: GestureDetector(
                onTap: () {}, // Prevent closing when tapping on the overlay itself
                child: NotificationOverlayContent(
                  onClose: closeCurrentOverlay,
                  onUnreadCountChanged: onUnreadCountChanged,
                  onStateCreated: (state) {
                    _currentState = state;
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_currentOverlayEntry!);
  }
}

/// Content widget for the notification overlay (used by UnifiedNotificationOverlay)
class NotificationOverlayContent extends StatefulWidget {
  final VoidCallback onClose;
  final Function(int)? onUnreadCountChanged;
  final Function(_NotificationOverlayState)? onStateCreated;

  const NotificationOverlayContent({
    super.key,
    required this.onClose,
    this.onUnreadCountChanged,
    this.onStateCreated,
  });

  @override
  State<NotificationOverlayContent> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlayContent> {
  final AuthService _authService = AuthService();
  List<Notification> _notifications = [];
  bool _isLoading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final userId = await _authService.getStoredUserId();
    if (!mounted || userId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _userId = userId;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.notifications),
        body: {'userID': userId},
      );

      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          setState(() {
            _notifications = data.map((item) => Notification.fromJson(item)).toList();
            _isLoading = false;
          });
          
          // Update unread count
          final unreadCount = _notifications.where((n) => n.read == 0).length;
          widget.onUnreadCountChanged?.call(unreadCount);
        } else {
          setState(() {
            _notifications = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.readNotification),
        body: {'notiID': notificationId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          setState(() {
            final index = _notifications.indexWhere((n) => n.id == notificationId);
            if (index != -1) {
              _notifications[index] = Notification(
                id: _notifications[index].id,
                username: _notifications[index].username,
                nickname: _notifications[index].nickname,
                avatar: _notifications[index].avatar,
                date: _notifications[index].date,
                content: _notifications[index].content,
                read: 1,
                type: _notifications[index].type,
                profile: _notifications[index].profile,
                post: _notifications[index].post,
              );
            }
          });
          
          // Update unread count
          final unreadCount = _notifications.where((n) => n.read == 0).length;
          widget.onUnreadCountChanged?.call(unreadCount);
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _readAll() async {
    if (_userId == null) return;
    
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.readAllNotifications),
        body: {'userID': _userId!},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          await _loadNotifications();
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _deleteAll() async {
    if (_userId == null) return;
    
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.deleteAllNotifications),
        body: {'userID': _userId!},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          setState(() {
            _notifications = [];
          });
          widget.onUnreadCountChanged?.call(0);
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return DateFormat('MMM d, y').format(date);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.getMenuBorderColor(context),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // Header with title and action buttons
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.getMenuDividerColor(context),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Read All button (left)
                      IconButton(
                        icon: const Icon(Icons.done_all, color: Colors.white),
                        onPressed: _readAll,
                        tooltip: TranslationKeys.readAll.tr,
                      ),
                      // Title (center)
                      Expanded(
                        child: Center(
                          child: TranslatedText(
                            TranslationKeys.notifications,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Delete All button (right)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.white),
                        onPressed: _deleteAll,
                        tooltip: TranslationKeys.deleteAll.tr,
                      ),
                    ],
                  ),
                ),
                // Notifications list
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        )
                      : _notifications.isEmpty
                          ? Center(
                              child: TranslatedText(
                                TranslationKeys.noData,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadNotifications,
                              color: Colors.white,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _notifications.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final notification = _notifications[index];
                                  return GestureDetector(
                                    onTap: () {
                                      if (notification.read == 0) {
                                        _markAsRead(notification.id);
                                      }
                                      // TODO: Navigate to profile or post based on notification type
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          radius: 22,
                                          backgroundColor: Colors.white.withOpacity(0.2),
                                          child: notification.avatar.isNotEmpty
                                              ? ClipOval(
                                                  child: CachedNetworkImage(
                                                    imageUrl: notification.avatar,
                                                    width: 44,
                                                    height: 44,
                                                    fit: BoxFit.cover,
                                                    placeholder: (context, url) => Image.asset(
                                                      'assets/images/icon.png',
                                                      width: 44,
                                                      height: 44,
                                                      fit: BoxFit.cover,
                                                    ),
                                                    errorWidget: (context, url, error) => Image.asset(
                                                      'assets/images/icon.png',
                                                      width: 44,
                                                      height: 44,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                )
                                              : Image.asset(
                                                  'assets/images/icon.png',
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                        title: Text(
                                          notification.nickname,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: notification.read == 0
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 16,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(
                                              notification.content,
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDate(notification.date),
                                              style: TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: notification.read == 0
                                            ? Container(
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: Colors.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

