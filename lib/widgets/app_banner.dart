import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/navigator_key.dart';

enum BannerType { error, success, warning, info }

class AppBanner {
  static OverlayEntry? _currentEntry;
  static _BannerWidgetState? _currentState;

  /// Show a top-sliding banner. Replaces any currently visible banner.
  static void show({
    required String message,
    BannerType type = BannerType.error,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    // Dismiss any existing banner instantly before showing the new one
    _dismissImmediately();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerWidget(
        message: message,
        type: type,
        duration: duration,
        onRegisterState: (state) => _currentState = state,
        onDismissed: () {
          entry.remove();
          if (_currentEntry == entry) {
            _currentEntry = null;
            _currentState = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void error(String message) =>
      show(message: message, type: BannerType.error);

  static void success(String message) =>
      show(message: message, type: BannerType.success);

  static void warning(String message) =>
      show(message: message, type: BannerType.warning);

  static void info(String message) =>
      show(message: message, type: BannerType.info);

  static void dismiss() {
    _currentState?.animateOut();
  }

  static void _dismissImmediately() {
    _currentEntry?.remove();
    _currentEntry = null;
    _currentState = null;
  }
}

class _BannerWidget extends StatefulWidget {
  final String message;
  final BannerType type;
  final Duration duration;
  final void Function(_BannerWidgetState) onRegisterState;
  final VoidCallback onDismissed;

  const _BannerWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onRegisterState,
    required this.onDismissed,
  });

  @override
  State<_BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<_BannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    widget.onRegisterState(this);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();

    // Auto-dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) animateOut();
    });
  }

  void animateOut() {
    if (!mounted || !_controller.isCompleted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;

    final (bgColor, icon) = switch (widget.type) {
      BannerType.error   => (const Color(0xFFD32F2F).withOpacity(0.85), Icons.error_outline_rounded),
      BannerType.success => (const Color(0xFF2E7D32).withOpacity(0.85), Icons.check_circle_outline_rounded),
      BannerType.warning => (const Color(0xFFE65100).withOpacity(0.85), Icons.warning_amber_rounded),
      BannerType.info    => (const Color(0xFF0277BD).withOpacity(0.85), Icons.info_outline_rounded),
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        type: MaterialType.transparency,
        child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: GestureDetector(
            onTap: animateOut,
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < 0) {
                animateOut();
              }
            },
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
              padding: EdgeInsets.fromLTRB(16, topPadding + 10, 16, 14),
              decoration: BoxDecoration(
                color: bgColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.7), size: 18),
                ],
              ),
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
