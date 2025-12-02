import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/video_item.dart';
import '../services/video_feed_service.dart';
import '../services/auth_service.dart';
import '../widgets/video_player_item.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final VideoFeedService _videoService = VideoFeedService();
  final PageController _pageController = PageController();
  final List<VideoItem> _videos = [];
  int _currentPage = 0;
  int _currentVideoIndex = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  Timer? _preloadTimer;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    // Set system UI overlay style for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _preloadTimer?.cancel();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadVideos({bool loadMore = false}) async {
    if (loadMore && (_isLoadingMore || !_hasMore)) return;

    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _error = null;
      }
    });

    try {
      // Get user ID if logged in
      final authService = AuthService();
      final userId = await authService.getStoredUserId();

      final response = await _videoService.fetchVideos(
        page: loadMore ? _page + 1 : 1,
        limit: 20,
        userId: userId,
      );

      if (mounted) {
        setState(() {
          if (loadMore) {
            _videos.addAll(response.videos);
            _page++;
          } else {
            _videos.clear();
            _videos.addAll(response.videos);
            _page = response.page;
            _currentVideoIndex = 0;
            if (_videos.isNotEmpty) {
              // Jump to first video
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _pageController.hasClients) {
                  _pageController.jumpToPage(0);
                }
              });
            }
          }
          _hasMore = response.hasMore;
          _isLoading = false;
          _isLoadingMore = false;
          if (!response.isSuccess) {
            _error = response.error;
          }
        });

        // Preload next videos in background
        _preloadNextVideos();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _error = e.toString();
        });
      }
    }
  }

  void _preloadNextVideos() {
    // Cancel any existing preload timer
    _preloadTimer?.cancel();
    
    // Preload videos in background after a short delay
    _preloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _currentVideoIndex < _videos.length - 2) {
        // Preload logic can be added here if needed
        // For now, videos are loaded on-demand by the video player
      }
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentVideoIndex = index;
      _currentPage = index;
    });

    // Load more videos when approaching the end
    if (index >= _videos.length - 3 && _hasMore && !_isLoadingMore) {
      _loadVideos(loadMore: true);
    }

    // Preload next videos
    _preloadNextVideos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading && _videos.isEmpty
            ? _buildLoadingScreen()
            : _error != null && _videos.isEmpty
                ? _buildErrorScreen()
                : _videos.isEmpty
                    ? _buildEmptyScreen()
                    : _buildVideoFeed(),
      ),
    );
  }

  Widget _buildVideoFeed() {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _onPageChanged,
      itemCount: _videos.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _videos.length) {
          // Loading indicator at the end
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        }

        final video = _videos[index];
        final isVisible = index == _currentVideoIndex;

        return VideoPlayerItem(
          video: video,
          isVisible: isVisible,
        );
      },
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white70,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load videos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                _loadVideos();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            color: Colors.white70,
            size: 64,
          ),
          SizedBox(height: 16),
          Text(
            'No videos available',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

