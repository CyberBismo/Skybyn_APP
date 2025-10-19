import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

class CloudData {
  final double x;
  final double y;
  final double width;
  final double height;
  final double speed;
  final int direction; // 1 for right, -1 for left
  final double opacity;
  final double scale;
  final bool isFlipped;

  CloudData({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.speed,
    required this.direction,
    required this.opacity,
    required this.scale,
    required this.isFlipped,
  });
}

class BackgroundGradient extends StatefulWidget {
  final Widget? child;
  const BackgroundGradient({super.key, this.child});

  @override
  State<BackgroundGradient> createState() => _BackgroundGradientState();
}

class _BackgroundGradientState extends State<BackgroundGradient>
    with TickerProviderStateMixin {
  List<Color>? _imageGradientColors;
  final List<CloudData> _clouds = [];
  final Random _random = Random();
  late AnimationController _animationController;
  Timer? _cloudUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadGradientFromBackground();

    // Initialize animation controller for cloud movement
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 16), // ~60 FPS
      vsync: this,
    );

    // Clouds will be generated in the first build

    // Start animation
    _animationController.repeat();

    // Start cloud position update timer
    _cloudUpdateTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateCloudPositions();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cloudUpdateTimer?.cancel();
    super.dispose();
  }

  void _generateClouds() {
    _clouds.clear();

    // Generate 10-15 random clouds (similar to web version)
    final int cloudCount = 10 + _random.nextInt(6); // 10-15 clouds

    for (int i = 0; i < cloudCount; i++) {
      final double screenWidth = MediaQuery.of(context).size.width;
      final double screenHeight = MediaQuery.of(context).size.height;

      // Random properties like web version
      final double width =
          (_random.nextDouble() * 200 + 100); // 100-300px width
      final double height = (_random.nextDouble() * 50 + 30); // 30-80px height
      final double x =
          _random.nextDouble() * screenWidth; // Random horizontal position
      final double y = _random.nextDouble() *
          (screenHeight - 50); // Random vertical position
      final double speed =
          _random.nextDouble() * 0.2 + 0.05; // Speed between 0.05-0.25
      final int direction = _random.nextBool() ? 1 : -1; // Random direction
      final double opacity =
          _random.nextDouble() * 0.1 + 0.05; // 0.05-0.15 opacity
      final double scale = _random.nextDouble() * 0.8 + 0.6; // 0.6-1.4 scale
      final bool isFlipped = _random.nextBool(); // Random flip

      _clouds.add(CloudData(
        x: x,
        y: y,
        width: width,
        height: height,
        speed: speed,
        direction: direction,
        opacity: opacity,
        scale: scale,
        isFlipped: isFlipped,
      ));
    }
  }

  void _updateCloudPositions() {
    if (!mounted || _clouds.isEmpty) return;

    final double screenWidth = MediaQuery.of(context).size.width;

    for (int i = 0; i < _clouds.length; i++) {
      final cloud = _clouds[i];
      double newX = cloud.x + (cloud.speed * cloud.direction);

      // Reset cloud position when it goes off screen
      if (cloud.direction == 1 && newX > screenWidth) {
        newX = -cloud.width; // Reset to left side
      } else if (cloud.direction == -1 && newX + cloud.width < 0) {
        newX = screenWidth; // Reset to right side
      }

      _clouds[i] = CloudData(
        x: newX,
        y: cloud.y,
        width: cloud.width,
        height: cloud.height,
        speed: cloud.speed,
        direction: cloud.direction,
        opacity: cloud.opacity,
        scale: cloud.scale,
        isFlipped: cloud.isFlipped,
      );
    }

    setState(() {}); // Trigger rebuild
  }

  @override
  Widget build(BuildContext context) {
    // Generate clouds on first build when context is available
    if (_clouds.isEmpty) {
      _generateClouds();
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final lightColors = [
      const Color.fromRGBO(72, 198, 239, 1.0), // Light blue (web light mode)
      const Color.fromRGBO(111, 134, 214, 1.0), // Blue (web light mode)
    ];

    final midnightColors = [
      const Color.fromRGBO(11, 19, 43, 1.0), // Midnight navy
      const Color.fromRGBO(0, 8, 20, 1.0), // Near-black midnight blue
    ];

    final gradientColors =
        isDarkMode ? midnightColors : (_imageGradientColors ?? lightColors);

    return Stack(
      children: [
        // Background gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: widget.child,
        ),

        // Random cloud overlays
        if (_clouds.isNotEmpty)
          Stack(
            children: _clouds.map((cloud) {
              return Positioned(
                left: cloud.x,
                top: cloud.y,
                child: Opacity(
                  opacity: cloud.opacity,
                  child: Transform.scale(
                    scale: cloud.scale,
                    child: Transform.flip(
                      flipX: cloud.isFlipped,
                      child: Image.asset(
                        'assets/images/cloud.png',
                        width: cloud.width,
                        height: cloud.height,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Future<void> _loadGradientFromBackground() async {
    try {
      final ByteData data =
          await rootBundle.load('assets/images/background.png');
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Image image = await _decodeImage(bytes);

      final ByteData? raw =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) return;
      final Uint8List pixels = raw.buffer.asUint8List();

      final int width = image.width;
      final int height = image.height;

      int yTop = (height * 0.1).floor().clamp(0, height - 1);
      int yBottom = (height * 0.9).floor().clamp(0, height - 1);

      Color topColor = _averageRowColor(pixels, width, height, yTop);
      Color bottomColor = _averageRowColor(pixels, width, height, yBottom);

      if (!mounted) return;
      setState(() {
        _imageGradientColors = [topColor, bottomColor];
      });
    } catch (_) {
      // If anything fails, keep defaults
    }
  }

  Color _averageRowColor(Uint8List pixels, int width, int height, int y) {
    int redTotal = 0;
    int greenTotal = 0;
    int blueTotal = 0;
    int alphaTotal = 0;

    for (int x = 0; x < width; x++) {
      final int index = (y * width + x) * 4; // RGBA
      final int r = pixels[index];
      final int g = pixels[index + 1];
      final int b = pixels[index + 2];
      final int a = pixels[index + 3];
      redTotal += r;
      greenTotal += g;
      blueTotal += b;
      alphaTotal += a;
    }

    final int count = width;
    final int rAvg = (redTotal / count).round();
    final int gAvg = (greenTotal / count).round();
    final int bAvg = (blueTotal / count).round();
    final int aAvg = (alphaTotal / count).round();

    return Color.fromRGBO(rAvg, gAvg, bAvg, aAvg / 255.0);
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image image) {
      if (!completer.isCompleted) {
        completer.complete(image);
      }
    });
    return completer.future;
  }
}
