import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../widgets/header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/background_gradient.dart';
import '../widgets/global_search_overlay.dart';
import '../widgets/map_view.dart';
import '../services/chat_message_count_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final ChatMessageCountService _chatMessageCountService =
      ChatMessageCountService();

  bool _showSearchForm = false;
  int _unreadChatCount = 0;
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _unreadChatCount = _chatMessageCountService.totalUnreadCount;
    _chatMessageCountService.addListener(_updateUnreadCount);
  }

  void _updateUnreadCount() {
    if (mounted) {
      setState(() {
        _unreadChatCount = _chatMessageCountService.totalUnreadCount;
      });
    }
  }

  @override
  void dispose() {
    _chatMessageCountService.removeListener(_updateUnreadCount);
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: CustomAppBar(
        logoPath: 'assets/images/logo.png',
        onLogoPressed: () =>
            Navigator.of(context).pushReplacementNamed('/home'),
        onSearchFormToggle: () =>
            setState(() => _showSearchForm = !_showSearchForm),
        isSearchFormVisible: _showSearchForm,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS
              ? 8.0
              : 8.0 + MediaQuery.of(context).padding.bottom,
        ),
        child: CustomBottomNavigationBar(
          onAddPressed: () {},
          unreadChatCount: _unreadChatCount,
          unreadNotificationCount: _unreadNotificationCount,
        ),
      ),
      body: Stack(
        children: [
          const BackgroundGradient(),
          Positioned.fill(
            child: MapView(mapController: _mapController),
          ),
          if (_showSearchForm)
            GlobalSearchOverlay(
              isVisible: _showSearchForm,
              onClose: () => setState(() => _showSearchForm = false),
            ),
        ],
      ),
    );
  }
}
