import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'video_feed_screen.dart';

/// Main navigation screen with Snapchat-style horizontal gesture navigation
/// Layout: Map (left) | Home (center) | Video (right)
/// 
/// Navigation:
/// - Swipe right from Home to go to Map
/// - Swipe left from Home to go to Video
/// - Swipe left from Map to go back to Home
/// - Swipe right from Video to go back to Home
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late PageController _pageController;
  int _currentPage = 1; // Start at Home (center)

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1); // Start at Home (index 1)
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  /// Navigate to a specific page (used by child screens)
  void navigateToPage(int pageIndex) {
    if (_pageController.hasClients && pageIndex >= 0 && pageIndex <= 2) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<bool> _handleBackButton() async {
    // If on Map (page 0) or Video (page 2), navigate to Home (page 1)
    if (_currentPage == 0 || _currentPage == 2) {
      navigateToPage(1);
      return false; // Prevent default back button behavior
    }
    // If on Home (page 1), allow normal back button behavior
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackButton,
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          physics: const AlwaysScrollableScrollPhysics(
            parent: PageScrollPhysics(),
          ), // Ensure PageView can always detect horizontal gestures
          scrollDirection: Axis.horizontal,
          children: [
            // Page 0: Map Screen (left) - swipe right from home to access
            MapScreen(
              onReturnToHome: () => navigateToPage(1),
            ),
            // Page 1: Home Screen (center) - default starting point
            const HomeScreen(),
            // Page 2: Video Feed Screen (right) - swipe left from home to access
            const VideoFeedScreen(),
          ],
        ),
        // Bottom navigation is handled by each individual screen
      ),
    );
  }
}

