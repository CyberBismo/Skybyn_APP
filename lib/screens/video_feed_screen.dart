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

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadVideos();
    
    // Add listener to prevent swiping to map screen (page 2) from video screen (page 1)
    _horizontalPageController.addListener(() {
      if (!_horizontalPageController.position.isScrollingNotifier.value) {
        // When scrolling stops, check if we're on page 2 and reset to page 1 if we came from page 1
        if (_horizontalPageController.page != null) {
          final currentPage = _horizontalPageController.page!.round();
          if (currentPage == 2 && _currentHorizontalPage == 1) {
            // Prevent going to map screen - jump back to video screen
            _horizontalPageController.jumpToPage(1);
          } else {
            _currentHorizontalPage = currentPage;
          }
        }
      }
    });
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
    if (index < 0 || index >= _videos.length) return;

    final video = _videos[index];
    
    // Handle different video types
    if (video.videoType == 'youtube') {
      // Extract YouTube video ID
      final videoId = _extractYouTubeId(video.videoUrl);
      if (videoId != null) {
        final youtubeController = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            loop: true,
            mute: false,
          ),
        );
        
        if (mounted) {
          setState(() {
            _youtubeControllers[index] = youtubeController;
          });
        }
      }
      return;
    } else if (video.videoType == 'vimeo' || video.videoType == 'tiktok') {
      // Use webview for Vimeo and TikTok
      final webviewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              // Inject script to make video fullscreen and autoplay
              // Use the controller from the map to avoid closure issues
              final controller = _webviewControllers[index];
              if (controller != null) {
                controller.runJavaScript('''
                  document.querySelector('video')?.play();
                ''');
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(video.videoUrl));
      
      if (mounted) {
        setState(() {
          _webviewControllers[index] = webviewController;
        });
      }
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
      controller.play();

      if (mounted) {
        setState(() {
          _controllers[index] = controller;
        });
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
    // Pause previous video
    if (_controllers.containsKey(_currentIndex)) {
      _controllers[_currentIndex]!.pause();
    }
    if (_youtubeControllers.containsKey(_currentIndex)) {
      _youtubeControllers[_currentIndex]!.pause();
    }

    _currentIndex = index;

    // Load more videos if near the end
    if (index >= _videos.length - 3 && _hasMore && !_isLoadingMore) {
      _loadVideos(page: _currentPage + 1, append: true);
    }

    // Play current video
    if (_controllers.containsKey(index)) {
      _controllers[index]!.play();
    } else if (_youtubeControllers.containsKey(index)) {
      _youtubeControllers[index]!.play();
    } else {
      _initializeVideo(index);
    }
  }

  @override
  void dispose() {
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
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          // Prevent scrolling to page 2 when on page 1 (video screen)
          if (_currentHorizontalPage == 1 && _horizontalPageController.hasClients) {
            final currentPage = _horizontalPageController.page ?? 1;
            // If trying to scroll to page 2 or beyond, prevent it
            if (currentPage > 1.5) {
              // Reset to page 1
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _horizontalPageController.hasClients) {
                  _horizontalPageController.jumpToPage(1);
                }
              });
              return true; // Consume the notification
            }
          }
          return false;
        },
        child: PageView(
          controller: _horizontalPageController,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          onPageChanged: (index) {
          // Store previous page before updating
          final previousPage = _currentHorizontalPage;
          
          // Update current horizontal page
          _currentHorizontalPage = index;
          
          // Prevent navigation to map screen (page 2) from video screen (page 1)
          if (index == 2 && previousPage == 1) {
            // If we're trying to go to map screen from video screen, prevent it
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _horizontalPageController.hasClients) {
                _horizontalPageController.jumpToPage(1);
                _currentHorizontalPage = 1;
              }
            });
            return;
          }
          
          // When page changes, navigate to the new screen using pushReplacement
          if (index == 0) {
            // Home screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              }
            });
          } else if (index == 2 && previousPage != 1) {
            // Map screen (only accessible from home screen, not from video screen)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MapScreen()),
                );
              }
            });
          }
        },
        children: [
          // Page 0: Home Screen
          const HomeScreen(),
          // Page 1: Video Feed Screen Content
          _buildVideoContent(),
          // Page 2: Map Screen
          const MapScreen(),
        ],
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _videos.isEmpty
            ? const Center(
                child: Text(
                  'No videos found',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : PageView.builder(
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player
        if (youtubeController != null)
          YoutubePlayer(
            controller: youtubeController,
            aspectRatio: 9 / 16, // Portrait aspect ratio
            showVideoProgressIndicator: true,
            progressIndicatorColor: Colors.red,
            progressColors: const ProgressBarColors(
              playedColor: Colors.red,
              handleColor: Colors.redAccent,
            ),
          )
        else if (webviewController != null)
          WebViewWidget(controller: webviewController)
        else if (controller != null && controller.value.isInitialized)
          GestureDetector(
            onTap: () {
              if (controller.value.isPlaying) {
                controller.pause();
              } else {
                controller.play();
              }
              setState(() {});
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                // Play/pause overlay
                if (!controller.value.isPlaying)
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
              if (youtubeController != null) {
                if (youtubeController.value.isPlaying) {
                  youtubeController.pause();
                } else {
                  youtubeController.play();
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

        // Action buttons on the right
        Positioned(
          right: 16,
          bottom: 100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(
                icon: Icons.favorite,
                label: _formatCount(video.likes),
                onTap: () {
                  // TODO: Implement like functionality
                },
              ),
              const SizedBox(height: 24),
              _buildActionButton(
                icon: Icons.comment,
                label: _formatCount(video.comments),
                onTap: () {
                  // TODO: Implement comment functionality
                },
              ),
              const SizedBox(height: 24),
              _buildActionButton(
                icon: Icons.share,
                label: 'Share',
                onTap: () {
                  // TODO: Implement share functionality
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white, size: 32),
          onPressed: onTap,
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
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

