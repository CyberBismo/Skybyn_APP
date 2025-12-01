import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../models/post.dart';
import '../widgets/header.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'home_screen.dart';
import 'map_screen.dart';

/// Custom ScrollPhysics that prevents left swiping (to map screen) when on video screen
/// Only allows rightward swipes (to go back to home) when on page 1
class VideoScreenScrollPhysics extends ScrollPhysics {
  final int currentPage;
  
  const VideoScreenScrollPhysics({
    required this.currentPage,
    super.parent,
  });

  @override
  VideoScreenScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return VideoScreenScrollPhysics(
      currentPage: currentPage,
      parent: buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return true;
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // Simplified: When on page 1 (video screen), prevent scrolling to page 2
    // Only check if we're on page 1 and trying to scroll right
    if (currentPage == 1 && value > position.pixels) {
      // Prevent scrolling beyond page 1's boundary
      // For 3-page PageView, page 1 ends at maxScrollExtent / 2
      final maxAllowed = position.maxScrollExtent / 2;
      if (value > maxAllowed) {
        return maxAllowed - value;
      }
    }
    return super.applyBoundaryConditions(position, value);
  }
}

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen() : super(key: const ValueKey('VideoFeedScreen'));

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final PageController _pageController = PageController(); // Vertical scrolling for videos
  final PageController _horizontalPageController = PageController(initialPage: 1); // Horizontal swiping between screens
  final AuthService _authService = AuthService();
  final List<VideoPost> _videos = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _currentUserId;
  int _currentHorizontalPage = 1; // Track current horizontal page (0=home, 1=video, 2=map)
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, YoutubePlayerController> _youtubeControllers = {};
  final Map<int, WebViewController> _webviewControllers = {};
  bool _isVideoScreenVisible = false; // Track if video screen is actually visible
  bool _isNavigatingToScreen = true; // Track if screen is being navigated to (not yet settled)
  DateTime? _navigationCompleteTime; // Track when navigation completed

  @override
  void initState() {
    super.initState();
    _loadUserId();
    // Mark as navigating initially - will be cleared after a delay
    _isNavigatingToScreen = true;
    // Set navigation complete time after a delay to allow swipe to finish
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _isNavigatingToScreen = false;
        _navigationCompleteTime = DateTime.now();
      }
    });
    // Defer video loading until screen is actually visible
    // This prevents blocking during swipe animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadVideos();
        _isVideoScreenVisible = true;
      }
    });
    
    // Add listener to prevent swiping to map screen (page 2) from video screen (page 1)
    // Optimized: only update when scrolling actually stops
    _horizontalPageController.addListener(_onHorizontalPageScroll);
  }

  void _onHorizontalPageScroll() {
    // Only check when scrolling stops to avoid performance issues
    if (!_horizontalPageController.position.isScrollingNotifier.value) {
      if (_horizontalPageController.page != null && mounted) {
        final currentPage = _horizontalPageController.page!.round();
        if (currentPage == 2 && _currentHorizontalPage == 1) {
          // Prevent going to map screen - jump back to video screen
          _horizontalPageController.jumpToPage(1);
        } else if (currentPage != _currentHorizontalPage) {
          _currentHorizontalPage = currentPage;
        }
      }
    }
  }

  Future<void> _loadUserId() async {
    _currentUserId = await _authService.getStoredUserId();
  }

  Future<void> _loadVideos({int page = 1, bool append = false}) async {
    if (_currentUserId == null) {
      _currentUserId = await _authService.getStoredUserId();
    }

    if (append) {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.videoFeed),
        body: {
          'userID': _currentUserId ?? '',
          'page': page.toString(),
          'limit': '20',
        },
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        
        // Debug: Log response for troubleshooting
        print('Video feed response: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        
        if (decoded is Map && decoded['responseCode'] == 1) {
          final List<dynamic> videoData = decoded['videos'] ?? [];
          final hasMore = decoded['has_more'] ?? false;
          final totalVideos = decoded['total_videos'] ?? 0;
          
          print('Video feed: Found ${videoData.length} videos (total: $totalVideos)');
          
          final List<VideoPost> videos = [];
          for (final item in videoData) {
            if (item is Map) {
              final videoUrl = item['video_url']?.toString();
              final videoType = item['video_type']?.toString() ?? 'direct';
              
              if (videoUrl != null && videoUrl.isNotEmpty) {
                videos.add(VideoPost(
                  id: item['id']?.toString() ?? '',
                  userId: item['user_id']?.toString() ?? '',
                  username: item['username']?.toString() ?? 'Unknown',
                  nickname: item['nickname']?.toString() ?? item['username']?.toString() ?? 'Unknown',
                  avatar: item['avatar']?.toString() ?? '',
                  videoUrl: videoUrl,
                  videoType: videoType,
                  content: item['content']?.toString() ?? '',
                  created: item['created'] is int 
                      ? item['created'] 
                      : int.tryParse(item['created']?.toString() ?? '0') ?? 0,
                  likes: int.tryParse(item['likes']?.toString() ?? '0') ?? 0,
                  comments: int.tryParse(item['comments']?.toString() ?? '0') ?? 0,
                ));
              }
            }
          }

          // Filter for portrait videos and initialize
          final List<VideoPost> portraitVideos = [];
          for (final video in videos) {
            // For direct video URLs, we'll check aspect ratio after loading
            // For YouTube/Vimeo, assume they might be portrait (TikTok-style content)
            if (video.videoType == 'direct') {
              portraitVideos.add(video);
            } else if (video.videoType == 'youtube' || video.videoType == 'tiktok' || video.videoType == 'vimeo') {
              // Include platform videos - they often have portrait content
              portraitVideos.add(video);
            }
          }

          setState(() {
            if (page == 1) {
              _videos.clear();
            }
            _videos.addAll(portraitVideos);
            _isLoading = false;
            _isLoadingMore = false;
            _hasMore = hasMore;
            _currentPage = page;
          });

          // Initialize first video
          if (_videos.isNotEmpty && page == 1) {
            _initializeVideo(0);
          }
        } else {
          print('Video feed error: Invalid response format or responseCode != 1');
          print('Response: $decoded');
          setState(() {
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      } else {
        print('Video feed error: HTTP ${response.statusCode}');
        print('Response body: ${response.body}');
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print('Video feed exception: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  String? _extractVideoUrl(String content) {
    // Extract video URLs from content
    // Look for common video URL patterns
    final urlPattern = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+\.(mp4|webm|mov|avi|mkv|m3u8)',
      caseSensitive: false,
    );
    
    final match = urlPattern.firstMatch(content);
    if (match != null) {
      return match.group(0);
    }

    return null;
  }

  String? _extractVideoUrlFromHtml(String html) {
    // Extract video URL from HTML iframe or video tag
    // Check for video tag src (match either double or single quotes)
    // Use character class ["] to match either quote type
    final videoTagPatternDouble = RegExp(
      r'<video[^>]+src="([^"]+)"',
      caseSensitive: false,
    );
    final videoTagPatternSingle = RegExp(
      r"<video[^>]+src='([^']+)'",
      caseSensitive: false,
    );
    
    var videoMatch = videoTagPatternDouble.firstMatch(html);
    if (videoMatch == null) {
      videoMatch = videoTagPatternSingle.firstMatch(html);
    }
    if (videoMatch != null) {
      return videoMatch.group(1);
    }

    // Check for iframe src (YouTube, Vimeo, etc.)
    final iframePatternDouble = RegExp(
      r'<iframe[^>]+src="([^"]+)"',
      caseSensitive: false,
    );
    final iframePatternSingle = RegExp(
      r"<iframe[^>]+src='([^']+)'",
      caseSensitive: false,
    );
    
    var iframeMatch = iframePatternDouble.firstMatch(html);
    if (iframeMatch == null) {
      iframeMatch = iframePatternSingle.firstMatch(html);
    }
    if (iframeMatch != null) {
      final iframeUrl = iframeMatch.group(1);
      // For now, we'll skip iframe URLs (YouTube, Vimeo) as they need special handling
      // Only return direct video file URLs
      if (iframeUrl != null && iframeUrl.contains(RegExp(r'\.(mp4|webm|mov|avi|mkv|m3u8)'))) {
        return iframeUrl;
      }
    }

    return null;
  }

  Future<void> _initializeVideo(int index) async {
    if (index < 0 || index >= _videos.length || !mounted || !_isVideoScreenVisible) return;
    
    // Don't initialize if index has changed (user scrolled away)
    if (index != _currentIndex) return;
    
    // Don't initialize if screen is still being navigated to
    if (_isNavigatingToScreen) return;
    
    // Ensure navigation has completed (at least 300ms after navigation)
    if (_navigationCompleteTime == null || 
        DateTime.now().difference(_navigationCompleteTime!).inMilliseconds < 300) {
      return;
    }

    final video = _videos[index];
    
    // Don't initialize if we're still in the middle of a swipe
    if (_horizontalPageController.hasClients) {
      final currentPage = _horizontalPageController.page ?? 1.0;
      // If we're not fully on page 1, don't initialize
      if ((currentPage - 1.0).abs() > 0.1) {
        return;
      }
    }
    
    // Handle different video types
    if (video.videoType == 'youtube') {
      // Extract YouTube video ID
      final videoId = _extractYouTubeId(video.videoUrl);
        if (videoId != null) {
        final youtubeController = YoutubePlayerController(
          initialVideoId: videoId,
          flags: YoutubePlayerFlags(
            autoPlay: index == _currentIndex, // Only autoplay if it's the current video
            loop: true,
            mute: false,
          ),
        );
        
        if (mounted && index == _currentIndex) {
          setState(() {
            _youtubeControllers[index] = youtubeController;
          });
        } else if (mounted) {
          // Store controller but don't trigger rebuild if not current
          _youtubeControllers[index] = youtubeController;
        }
      }
      return;
    } else if (video.videoType == 'vimeo' || video.videoType == 'tiktok') {
      // Use webview for Vimeo and TikTok - defer initialization to avoid blocking
      // WebView initialization is expensive and causes frame drops
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || index != _currentIndex || !_isVideoScreenVisible) return;
        
        final webviewController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (String url) {
                // Inject script to make video fullscreen and autoplay (only if not swiping and navigation complete)
                final controller = _webviewControllers[index];
                if (controller != null && mounted && index == _currentIndex && 
                    _isVideoScreenVisible && _currentHorizontalPage == 1 && !_isNavigatingToScreen) {
                  final canPlay = _navigationCompleteTime != null && 
                      DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
                  if (canPlay) {
                    controller.runJavaScript('''
                      document.querySelector('video')?.play();
                    ''');
                  }
                }
              },
            ),
          )
          ..loadRequest(Uri.parse(video.videoUrl));
        
        if (mounted && index == _currentIndex) {
          _webviewControllers[index] = webviewController;
          setState(() {});
        }
      });
      return;
    }
    
    // Handle direct video files
    try {
      // Dispose previous controller if exists
      if (_controllers.containsKey(index)) {
        await _controllers[index]!.dispose();
        _controllers.remove(index);
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(video.videoUrl),
      );

      // Initialize on a separate isolate to avoid blocking main thread
      await controller.initialize();
      
      // Check if video is portrait (height > width)
      final aspectRatio = controller.value.aspectRatio;
      final isPortrait = aspectRatio < 1.0; // Portrait videos have aspect ratio < 1.0
      
      if (!isPortrait) {
        // Skip landscape videos
        await controller.dispose();
        // Remove from list
        if (mounted) {
          setState(() {
            _videos.removeAt(index);
            // Adjust current index if needed
            if (_currentIndex >= _videos.length && _videos.isNotEmpty) {
              _currentIndex = _videos.length - 1;
            }
          });
        }
        return;
      }
      
      controller.setLooping(true);
      
      // Only play if this is still the current video, not swiping, and navigation is complete
      if (mounted && index == _currentIndex && _isVideoScreenVisible && 
          _currentHorizontalPage == 1 && !_isNavigatingToScreen) {
        // Ensure navigation has completed before playing
        final canPlay = _navigationCompleteTime != null && 
            DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
        if (canPlay) {
          controller.play();
        }
      }

      if (mounted && index == _currentIndex) {
        setState(() {
          _controllers[index] = controller;
        });
      } else {
        // If user scrolled away, just store the controller but don't play
        if (mounted) {
          _controllers[index] = controller;
        }
      }
    } catch (e) {
      // Video failed to load - will show loading indicator
      if (mounted) {
        setState(() {});
      }
    }
  }

  String? _extractYouTubeId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  void _onPageChanged(int index) {
    // Validate index and ensure video screen is visible
    if (index < 0 || _videos.isEmpty || !_isVideoScreenVisible) return;
    
    // Dispose videos that are far from current index to free memory
    _disposeDistantVideos(index);
    
    // Pause previous video only if it exists
    if (_currentIndex >= 0 && _currentIndex < _videos.length && _currentIndex != index) {
      if (_controllers.containsKey(_currentIndex)) {
        _controllers[_currentIndex]!.pause();
      }
      if (_youtubeControllers.containsKey(_currentIndex)) {
        _youtubeControllers[_currentIndex]!.pause();
      }
    }

    _currentIndex = index;

    // Load more videos if near the end (only if we have videos)
    if (index >= _videos.length - 3 && _hasMore && !_isLoadingMore && _videos.isNotEmpty) {
      _loadVideos(page: _currentPage + 1, append: true);
    }

    // Play current video (only if index is valid, not swiping, and navigation is complete) - defer initialization with longer delay
    if (index < _videos.length && _isVideoScreenVisible && _currentHorizontalPage == 1 && !_isNavigatingToScreen) {
      // Ensure navigation has completed before playing
      final canPlay = _navigationCompleteTime != null && 
          DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
      
      if (!canPlay) return;
      if (_controllers.containsKey(index)) {
        final controller = _controllers[index]!;
        if (controller.value.isInitialized) {
          // Use microtask to avoid blocking
          Future.microtask(() {
            if (mounted && index == _currentIndex && controller.value.isInitialized && !_isNavigatingToScreen) {
              final canPlay = _navigationCompleteTime != null && 
                  DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
              if (canPlay) {
                controller.play();
              }
            }
          });
        }
      } else if (_youtubeControllers.containsKey(index)) {
        Future.microtask(() {
          if (mounted && index == _currentIndex && !_isNavigatingToScreen) {
            final canPlay = _navigationCompleteTime != null && 
                DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
            if (canPlay) {
              _youtubeControllers[index]?.play();
            }
          }
        });
      } else {
        // Initialize video asynchronously with delay to ensure smooth scrolling
        // Longer delay to let swipe animation complete first
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && index == _currentIndex && _isVideoScreenVisible) {
            _initializeVideo(index);
          }
        });
      }
    }
  }

  /// Pause all videos (used when leaving video screen or during swiping)
  void _pauseAllVideos() {
    // Pause all VideoPlayer controllers
    for (final controller in _controllers.values) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
      }
    }
    // Pause all YouTube controllers
    for (final controller in _youtubeControllers.values) {
      if (controller.value.isPlaying) {
        controller.pause();
      }
    }
    // Pause WebView videos by injecting pause script
    for (final entry in _webviewControllers.entries) {
      final controller = entry.value;
      try {
        controller.runJavaScript('''
          const video = document.querySelector('video');
          if (video && !video.paused) {
            video.pause();
          }
        ''');
      } catch (e) {
        // Ignore errors - WebView might not be ready
      }
    }
  }
  
  void _resumeCurrentVideo() {
    // Only resume if we're not swiping and screen is visible
    if (!_isVideoScreenVisible || _currentHorizontalPage != 1) {
      return;
    }
    
    if (_currentIndex >= 0 && _currentIndex < _videos.length) {
      // Resume VideoPlayer
      if (_controllers.containsKey(_currentIndex)) {
        final controller = _controllers[_currentIndex]!;
        if (controller.value.isInitialized && !controller.value.isPlaying) {
          controller.play();
        }
      }
      
      // Resume YouTube player
      if (_youtubeControllers.containsKey(_currentIndex)) {
        final controller = _youtubeControllers[_currentIndex]!;
        if (!controller.value.isPlaying) {
          controller.play();
        }
      }
      
      // WebView videos will auto-play when visible
    }
  }

  /// Dispose video controllers that are far from the current index
  void _disposeDistantVideos(int currentIndex) {
    const maxDistance = 2; // Keep videos within 2 positions of current
    
    final keysToRemove = <int>[];
    
    // Dispose controllers that are too far
    for (final key in _controllers.keys) {
      if ((key - currentIndex).abs() > maxDistance) {
        _controllers[key]?.dispose();
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _controllers.remove(key);
    }
    
    keysToRemove.clear();
    
    // Dispose YouTube controllers that are too far
    for (final key in _youtubeControllers.keys) {
      if ((key - currentIndex).abs() > maxDistance) {
        _youtubeControllers[key]?.dispose();
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _youtubeControllers.remove(key);
    }
    
    keysToRemove.clear();
    
    // Dispose webview controllers that are too far
    for (final key in _webviewControllers.keys) {
      if ((key - currentIndex).abs() > maxDistance) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _webviewControllers.remove(key);
    }
  }

  @override
  void dispose() {
    // Remove listener before disposing
    _horizontalPageController.removeListener(_onHorizontalPageScroll);
    _pageController.dispose();
    _horizontalPageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final controller in _youtubeControllers.values) {
      controller.dispose();
    }
    _youtubeControllers.clear();
    _webviewControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Disable clouds by setting a key that can be detected
    return Container(
      key: const ValueKey('VideoFeedScreen'),
      color: Colors.black, // Cover clouds with black background
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: CustomAppBar(
          logoPath: 'assets/images/logo.png',
          onLogoPressed: () {
            Navigator.of(context).pop();
          },
        ),
      body: PageView(
          controller: _horizontalPageController,
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(), // Enable normal PageView scrolling
          onPageChanged: (index) {
          // Store previous page before updating
          final previousPage = _currentHorizontalPage;
          
          // Update current horizontal page
          _currentHorizontalPage = index;
          
          // Update visibility flag - only allow video operations when on video screen
          _isVideoScreenVisible = (index == 1);
          
          // If leaving video screen, pause all videos
          if (previousPage == 1 && index != 1) {
            _pauseAllVideos();
          }
          
          // Prevent navigation to map screen (page 2) from video screen (page 1)
          if (index == 2 && previousPage == 1) {
            // If we're trying to go to map screen from video screen, prevent it
            Future.microtask(() {
              if (mounted && _horizontalPageController.hasClients) {
                _horizontalPageController.jumpToPage(1);
                _currentHorizontalPage = 1;
                _isVideoScreenVisible = true;
              }
            });
            return;
          }
          
          // When page changes, navigate to the new screen using pushReplacement with smooth transitions
          if (index == 0) {
            // Home screen - slide in from right
            Future.microtask(() {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.easeInOutCubic;

                      var tween = Tween(begin: begin, end: end).chain(
                        CurveTween(curve: curve),
                      );

                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 250),
                    reverseTransitionDuration: const Duration(milliseconds: 250),
                  ),
                );
              }
            });
          } else if (index == 2 && previousPage != 1) {
            // Map screen (only accessible from home screen, not from video screen) - slide in from left
            Future.microtask(() {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const MapScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(-1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.easeInOutCubic;

                      var tween = Tween(begin: begin, end: end).chain(
                        CurveTween(curve: curve),
                      );

                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 250),
                    reverseTransitionDuration: const Duration(milliseconds: 250),
                  ),
                );
              }
            });
          } else if (index == 1) {
            // Video screen - ensure videos are loaded if not already
            if (_videos.isEmpty && !_isLoading) {
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted && _isVideoScreenVisible) {
                  _loadVideos();
                }
              });
            }
            // Resume current video when returning to video screen (if not swiping)
            if (_isVideoScreenVisible) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _isVideoScreenVisible && _currentHorizontalPage == 1) {
                  _resumeCurrentVideo();
                }
              });
            }
          }
        },
        children: [
          // Page 0: Home Screen - use const for better performance
          const HomeScreen(),
          // Page 1: Video Feed Screen Content
          _buildVideoContent(),
          // Page 2: Map Screen - use const for better performance
          const MapScreen(),
        ],
      ),
      ),
    );
  }

  Widget _buildVideoContent() {
    // Show loading state immediately without blocking
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.0,
        ),
      );
    }
    
    // Show empty state if no videos
    if (_videos.isEmpty) {
      return const Center(
        child: Text(
          'No videos found',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      );
    }
    
    // Build video feed with optimized PageView
    return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: _videos.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _videos.length) {
                    // Loading indicator at the end
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  
                  final video = _videos[index];
                  final controller = _controllers[index];
                  final youtubeController = _youtubeControllers[index];
                  final webviewController = _webviewControllers[index];

                  return _buildVideoItem(video, controller, youtubeController, webviewController, index);
                },
              );
  }

  Widget _buildVideoItem(
    VideoPost video,
    VideoPlayerController? controller,
    YoutubePlayerController? youtubeController,
    WebViewController? webviewController,
    int index,
  ) {
    // Only play video if it's the current one
    final isCurrentVideo = index == _currentIndex;
    
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player - wrapped in RepaintBoundary to isolate repaints
          if (youtubeController != null)
            RepaintBoundary(
              child: YoutubePlayer(
                controller: youtubeController,
                aspectRatio: 9 / 16, // Portrait aspect ratio
                showVideoProgressIndicator: isCurrentVideo, // Only show progress for current video
                progressIndicatorColor: Colors.red,
                progressColors: const ProgressBarColors(
                  playedColor: Colors.red,
                  handleColor: Colors.redAccent,
                ),
              ),
            )
          else if (webviewController != null)
            RepaintBoundary(
              child: WebViewWidget(controller: webviewController),
            )
          else if (controller != null && controller.value.isInitialized)
            RepaintBoundary(
              child: GestureDetector(
                onTap: () {
                  // Don't allow play/pause toggle during swiping
                  // Toggle play/pause without setState - use controller directly
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    if (_isVideoScreenVisible && _currentHorizontalPage == 1 && !_isNavigatingToScreen) {
                      final canPlay = _navigationCompleteTime != null && 
                          DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
                      if (canPlay) {
                        controller.play();
                      }
                    }
                  }
                },
                child: ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        // Play/pause overlay - only rebuilds when playing state changes
                        if (!value.isPlaying)
                          Container(
                            color: Colors.black.withOpacity(0.3),
                            child: const Center(
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 64,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

        // Tap overlay for YouTube and webview videos
        if (youtubeController != null || webviewController != null)
          GestureDetector(
            onTap: () {
              // Don't allow play/pause toggle during swiping
              if (youtubeController != null) {
                if (youtubeController.value.isPlaying) {
                  youtubeController.pause();
                } else {
                  if (_isVideoScreenVisible && _currentHorizontalPage == 1 && !_isNavigatingToScreen) {
                    final canPlay = _navigationCompleteTime != null && 
                        DateTime.now().difference(_navigationCompleteTime!).inMilliseconds >= 300;
                    if (canPlay) {
                      youtubeController.play();
                    }
                  }
                }
              }
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),

        // Gradient overlay at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Video info overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // User info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: video.avatar.isNotEmpty
                          ? CachedNetworkImageProvider(
                              video.avatar.startsWith('http')
                                  ? video.avatar
                                  : 'https://skybyn.no${video.avatar}',
                            )
                          : null,
                      child: video.avatar.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.nickname.isNotEmpty ? video.nickname : video.username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            timeago.format(DateTime.fromMillisecondsSinceEpoch(video.created * 1000)),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Content
                if (video.content.isNotEmpty)
                  Text(
                    video.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),

      ],
      ),
    );
  }

}

class VideoPost {
  final String id;
  final String userId;
  final String username;
  final String nickname;
  final String avatar;
  final String videoUrl;
  final String videoType; // 'direct', 'youtube', 'vimeo', 'tiktok', etc.
  final String content;
  final int created;
  final int likes;
  final int comments;

  VideoPost({
    required this.id,
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.videoUrl,
    required this.videoType,
    required this.content,
    required this.created,
    required this.likes,
    required this.comments,
  });
}

