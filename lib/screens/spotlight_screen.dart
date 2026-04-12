import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/spotlight_video.dart';
import '../services/spotlight_service.dart';

class SpotlightScreen extends StatefulWidget {
  final ValueNotifier<bool> isActive;
  const SpotlightScreen({super.key, required this.isActive});

  @override
  State<SpotlightScreen> createState() => _SpotlightScreenState();
}

class _SpotlightScreenState extends State<SpotlightScreen>
    with AutomaticKeepAliveClientMixin {
  final SpotlightService _service = SpotlightService();
  final PageController _pageController = PageController();
  final Map<int, YoutubePlayerController> _controllers = {};
  final List<SpotlightVideo> _videos = [];

  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    widget.isActive.addListener(_onActiveChanged);
  }

  void _onActiveChanged() {
    if (!widget.isActive.value) {
      _controllers[_currentIndex]?.pause();
    } else {
      _controllers[_currentIndex]?.play();
    }
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _error = null;
        _videos.clear();
        _currentIndex = 0;
      });
      _disposeAllControllers();
    }

    try {
      final videos = await _service.fetchVideos(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _videos.addAll(videos);
        _isLoading = false;
      });
      if (_videos.isNotEmpty) {
        _initController(0);
        // Small delay to let the WebView initialise before playing
        Timer(const Duration(milliseconds: 600), () {
          if (mounted) _controllers[0]?.play();
        });
      }
    } catch (e) {
      debugPrint('[Spotlight] Error loading videos: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_service.hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final videos = await _service.fetchVideos();
      if (!mounted) return;
      setState(() {
        _videos.addAll(videos);
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  YoutubePlayerController _initController(int index) {
    if (_controllers.containsKey(index)) return _controllers[index]!;
    final controller = YoutubePlayerController(
      initialVideoId: _videos[index].id,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        loop: true,
        mute: false,
        useHybridComposition: false,
        disableDragSeek: true,
        hideThumbnail: true,
      ),
    );
    _controllers[index] = controller;
    return controller;
  }

  void _onPageChanged(int index) {
    // Pause previous video
    _controllers[_currentIndex]?.pause();
    _currentIndex = index;

    // Play current video (with small delay for WebView readiness)
    final controller = _initController(index);
    Timer(const Duration(milliseconds: 200), () {
      if (mounted && _currentIndex == index) controller.play();
    });

    // Dispose controllers that are far from current page
    _controllers.keys
        .where((k) => (k - index).abs() > 2)
        .toList()
        .forEach((k) {
      _controllers[k]?.dispose();
      _controllers.remove(k);
    });

    // Fetch more when close to end
    if (index >= _videos.length - 4) _loadMore();
  }

  void _disposeAllControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  @override
  void dispose() {
    widget.isActive.removeListener(_onActiveChanged);
    _disposeAllControllers();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Could not load videos',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _loadVideos(refresh: true),
                child: const Text('Try again',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No videos available',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _videos.length,
        itemBuilder: (context, index) {
          return _SpotlightVideoItem(
            video: _videos[index],
            controller: _initController(index),
          );
        },
      ),
    );
  }
}

class _SpotlightVideoItem extends StatelessWidget {
  final SpotlightVideo video;
  final YoutubePlayerController controller;

  const _SpotlightVideoItem({
    required this.video,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Black background
        const ColoredBox(color: Colors.black),

        // Portrait video player — centred and fills screen height
        Center(
          child: YoutubePlayer(
            controller: controller,
            aspectRatio: 9 / 16,
            showVideoProgressIndicator: false,
          ),
        ),

        // Gradient overlay at bottom for text legibility
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 160,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
        ),

        // Video info
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                video.channelTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (video.title.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
