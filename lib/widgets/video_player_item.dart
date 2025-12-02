import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../models/video_item.dart';
import '../services/video_feed_service.dart';

class VideoPlayerItem extends StatefulWidget {
  final VideoItem video;
  final bool isVisible;
  final VoidCallback? onVideoEnd;

  const VideoPlayerItem({
    super.key,
    required this.video,
    required this.isVisible,
    this.onVideoEnd,
  });

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  YoutubePlayerController? _youtubeController;
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _visibilityTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      _handleVisibilityChange(widget.isVisible);
    }
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      if (widget.video.videoType == 'youtube' || widget.video.source == 'youtube') {
        final videoId = VideoFeedService.extractYouTubeVideoId(widget.video.videoUrl);
        if (videoId != null) {
          _youtubeController = YoutubePlayerController(
            initialVideoId: videoId,
            flags: const YoutubePlayerFlags(
              autoPlay: false,
              mute: false,
              loop: false,
              controlsVisibleAtStart: false,
              hideControls: true,
              enableCaption: false,
            ),
          );

          // Wait for controller to initialize
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (mounted) {
            setState(() {
              _isInitialized = true;
              _isLoading = false;
            });
            
            // Auto-play if visible
            if (widget.isVisible) {
              _playVideo();
            }
          }
        } else {
          throw Exception('Could not extract YouTube video ID');
        }
      } else {
        // For other video types, use video_player
        // Note: Direct video URLs are needed for video_player
        // This is a placeholder - you may need to extract direct URLs from other platforms
        throw Exception('Non-YouTube videos require direct video URLs');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _handleVisibilityChange(bool isVisible) {
    if (isVisible) {
      // Small delay to ensure smooth transition
      _visibilityTimer?.cancel();
      _visibilityTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted && widget.isVisible) {
          _playVideo();
        }
      });
    } else {
      _visibilityTimer?.cancel();
      _pauseVideo();
    }
  }

  void _playVideo() {
    if (_youtubeController != null && _isInitialized) {
      _youtubeController!.play();
    } else if (_videoController != null && _isInitialized) {
      _videoController!.play();
    }
  }

  void _pauseVideo() {
    if (_youtubeController != null) {
      _youtubeController!.pause();
    } else if (_videoController != null) {
      _videoController!.pause();
    }
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _youtubeController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${widget.video.id}'),
      onVisibilityChanged: (info) {
        // Only play/pause when visibility changes significantly
        if (info.visibleFraction > 0.8 && !widget.isVisible) {
          // Video became visible
          _handleVisibilityChange(true);
        } else if (info.visibleFraction < 0.2 && widget.isVisible) {
          // Video became hidden
          _handleVisibilityChange(false);
        }
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video player
            if (_isInitialized && !_hasError)
              _buildVideoPlayer()
            else if (_isLoading)
              _buildLoadingIndicator()
            else if (_hasError)
              _buildErrorWidget(),
            
            // Video info overlay (bottom)
            if (_isInitialized && !_hasError)
              _buildVideoInfoOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_youtubeController != null) {
      return YoutubePlayer(
        controller: _youtubeController!,
        aspectRatio: 9 / 16, // Portrait aspect ratio
        showVideoProgressIndicator: false,
        progressIndicatorColor: Colors.transparent,
        progressColors: const ProgressBarColors(
          playedColor: Colors.transparent,
          handleColor: Colors.transparent,
          bufferedColor: Colors.transparent,
          backgroundColor: Colors.transparent,
        ),
      );
    } else if (_videoController != null && _videoController!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load video',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              _initializePlayer();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfoOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Username
            Row(
              children: [
                if (widget.video.avatar != null)
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(widget.video.avatar!),
                    onBackgroundImageError: (_, __) {},
                  )
                else
                  const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 16),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.video.nickname.isNotEmpty ? widget.video.nickname : widget.video.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Content/Description
            if (widget.video.content.isNotEmpty)
              Text(
                widget.video.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

