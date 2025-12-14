import 'package:flutter/material.dart';

/// A simple shimmer/skeleton loader widget
class SkeletonLoader extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  const SkeletonLoader({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? Colors.grey[800]!;
    final highlightColor = widget.highlightColor ?? Colors.grey[700]!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 - _controller.value * 2, 0.0),
              end: Alignment(1.0 - _controller.value * 2, 0.0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// Skeleton widget for profile background/wallpaper
class ProfileBackgroundSkeleton extends StatelessWidget {
  const ProfileBackgroundSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 250,
      color: Colors.grey[800],
      child: SkeletonLoader(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Skeleton widget for profile avatar
class ProfileAvatarSkeleton extends StatelessWidget {
  final double size;
  
  const ProfileAvatarSkeleton({
    super.key,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey[700]!,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: SkeletonLoader(
          child: Container(
            width: size,
            height: size,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Skeleton widget for post card
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]!.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[800]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton (avatar + username + time)
          Row(
            children: [
              SkeletonLoader(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(
                      child: Container(
                        height: 16,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SkeletonLoader(
                      child: Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Content skeleton
          SkeletonLoader(
            child: Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SkeletonLoader(
            child: Container(
              height: 14,
              width: double.infinity * 0.8,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SkeletonLoader(
            child: Container(
              height: 14,
              width: double.infinity * 0.6,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              SkeletonLoader(
                child: Container(
                  height: 24,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SkeletonLoader(
                child: Container(
                  height: 24,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SkeletonLoader(
                child: Container(
                  height: 24,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton widget for chat message bubble
class ChatMessageSkeleton extends StatelessWidget {
  final bool isFromMe;
  final double? width; // Optional width for variety
  
  const ChatMessageSkeleton({
    super.key,
    this.isFromMe = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    // Use provided width or calculate based on screen width
    final messageWidth = width ?? (MediaQuery.of(context).size.width * (isFromMe ? 0.65 : 0.7));
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isFromMe) ...[
            SkeletonLoader(
              baseColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.2),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isFromMe
                    ? Colors.blue.withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isFromMe ? 18 : 4),
                  bottomRight: Radius.circular(isFromMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(
                    baseColor: Colors.white.withOpacity(0.2),
                    highlightColor: Colors.white.withOpacity(0.4),
                    child: Container(
                      height: 16,
                      width: messageWidth * 0.85,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SkeletonLoader(
                    baseColor: Colors.white.withOpacity(0.2),
                    highlightColor: Colors.white.withOpacity(0.4),
                    child: Container(
                      height: 16,
                      width: messageWidth * 0.6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SkeletonLoader(
                    baseColor: Colors.white.withOpacity(0.15),
                    highlightColor: Colors.white.withOpacity(0.3),
                    child: Container(
                      height: 11,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
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

/// Skeleton loader for chat screen with multiple message bubbles
class ChatScreenSkeleton extends StatelessWidget {
  const ChatScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6, // Show 6 skeleton messages
      itemBuilder: (context, index) {
        // Alternate between sent and received messages for realism
        final isFromMe = index % 3 == 0; // Every 3rd message is from me
        // Vary message widths for more realistic appearance
        final widthVariations = [0.6, 0.7, 0.65, 0.75, 0.55, 0.68];
        final width = screenWidth * widthVariations[index % widthVariations.length];
        return ChatMessageSkeleton(
          isFromMe: isFromMe,
          width: width,
        );
      },
    );
  }
}

