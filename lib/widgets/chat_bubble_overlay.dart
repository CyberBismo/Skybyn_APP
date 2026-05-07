import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:cached_network_image/cached_network_image.dart';

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatBubbleOverlay(),
    );
  }
}

class ChatBubbleOverlay extends StatefulWidget {
  const ChatBubbleOverlay({super.key});

  @override
  State<ChatBubbleOverlay> createState() => _ChatBubbleOverlayState();
}

class _ChatBubbleOverlayState extends State<ChatBubbleOverlay>
    with SingleTickerProviderStateMixin {
  String? _friendId;
  String _friendName = '';
  String _friendAvatar = '';
  int _unreadCount = 0;

  StreamSubscription? _dataSubscription;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((raw) {
      if (raw == null) return;
      try {
        final map = raw is String ? jsonDecode(raw) as Map : raw as Map;
        if (mounted) {
          setState(() {
            _friendId = map['friendId']?.toString();
            _friendName = map['friendName']?.toString() ?? '';
            _friendAvatar = map['friendAvatar']?.toString() ?? '';
            _unreadCount = (map['unreadCount'] as num?)?.toInt() ?? 0;
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _openChat() async {
    if (_friendId == null) return;
    await FlutterOverlayWindow.shareData(
        jsonEncode({'action': 'open_chat', 'friendId': _friendId}));
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final hasBadge = _unreadCount > 0;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        painter: _ClearPainter(),
        child: GestureDetector(
        onTap: _openChat,
        child: ScaleTransition(
          scale: hasBadge ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Avatar circle
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1565C0).withAlpha(115),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _friendAvatar.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _friendAvatar,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _initials(),
                        )
                      : _initials(),
                ),
              ),
              // Unread badge
              if (hasBadge)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
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

  Widget _initials() {
    final letter = _friendName.isNotEmpty ? _friendName[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF1565C0),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ClearPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.transparent, BlendMode.clear);
  }

  @override
  bool shouldRepaint(_ClearPainter oldDelegate) => false;
}
