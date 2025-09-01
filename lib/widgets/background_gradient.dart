import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:async';

class BackgroundGradient extends StatefulWidget {
  final Widget? child;
  const BackgroundGradient({super.key, this.child});

  @override
  State<BackgroundGradient> createState() => _BackgroundGradientState();
}

class _BackgroundGradientState extends State<BackgroundGradient> with TickerProviderStateMixin {
  List<Color>? _imageGradientColors;
  late AnimationController _cloud1Controller;
  late AnimationController _cloud2Controller;
  late AnimationController _cloud3Controller;
  late Animation<double> _cloud1Animation;
  late Animation<double> _cloud2Animation;
  late Animation<double> _cloud3Animation;

  @override
  void initState() {
    super.initState();
    _loadGradientFromBackground();
    
    // Cloud 1: Left to right, very slow speed
    _cloud1Controller = AnimationController(
      duration: const Duration(seconds: 80), // Very slow
      vsync: this,
    );
    _cloud1Animation = Tween<double>(
      begin: -0.3,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _cloud1Controller,
      curve: Curves.linear,
    ));

    // Cloud 2: Right to left, slow speed
    _cloud2Controller = AnimationController(
      duration: const Duration(seconds: 60), // Slow
      vsync: this,
    );
    _cloud2Animation = Tween<double>(
      begin: 1.3,
      end: -0.3,
    ).animate(CurvedAnimation(
      parent: _cloud2Controller,
      curve: Curves.linear,
    ));

    // Cloud 3: Left to right, medium speed
    _cloud3Controller = AnimationController(
      duration: const Duration(seconds: 100), // Very slow
      vsync: this,
    );
    _cloud3Animation = Tween<double>(
      begin: -0.3,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _cloud3Controller,
      curve: Curves.linear,
    ));

    // Start animations
    _cloud1Controller.repeat();
    _cloud2Controller.repeat();
    _cloud3Controller.repeat();
  }

  @override
  void dispose() {
    _cloud1Controller.dispose();
    _cloud2Controller.dispose();
    _cloud3Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final lightColors = [
      const Color(0xFF48C6EF), // Light blue (web light mode)
      const Color(0xFF6F86D6), // Blue (web light mode)
    ];

    final darkColors = [
      const Color(0xFF243B55), // Dark blue (web dark mode)
      const Color(0xFF141E30), // Almost black (web dark mode)
    ];

    final midnightColors = [
      const Color(0xFF0B132B), // Midnight navy
      const Color(0xFF000814), // Near-black midnight blue
    ];

    final gradientColors = isDarkMode
        ? midnightColors
        : (_imageGradientColors ?? lightColors);

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
        
        // Animated cloud overlays
        AnimatedBuilder(
          animation: _cloud1Animation,
          builder: (context, child) {
            return Positioned(
              left: MediaQuery.of(context).size.width * _cloud1Animation.value,
              top: MediaQuery.of(context).size.height * 0.1,
              child: Opacity(
                opacity: 0.1, // Low opacity like web platform
                child: Transform.scale(
                  scale: 0.8,
                  child: Image.asset(
                    'assets/images/cloud.png', // Use the cloud image
                    width: 200,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
          },
        ),
        
        AnimatedBuilder(
          animation: _cloud2Animation,
          builder: (context, child) {
            return Positioned(
              left: MediaQuery.of(context).size.width * _cloud2Animation.value,
              top: MediaQuery.of(context).size.height * 0.3,
              child: Opacity(
                opacity: 0.08, // Slightly different opacity
                child: Transform.scale(
                  scale: 1.2,
                  child: Image.asset(
                    'assets/images/cloud.png',
                    width: 250,
                    height: 150,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
          },
        ),
        
        AnimatedBuilder(
          animation: _cloud3Animation,
          builder: (context, child) {
            return Positioned(
              left: MediaQuery.of(context).size.width * _cloud3Animation.value,
              top: MediaQuery.of(context).size.height * 0.6,
              child: Opacity(
                opacity: 0.06, // Different opacity for variety
                child: Transform.scale(
                  scale: 0.6,
                  child: Image.asset(
                    'assets/images/cloud.png',
                    width: 150,
                    height: 90,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _loadGradientFromBackground() async {
    try {
      final ByteData data = await rootBundle.load('assets/images/background.png');
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Image image = await _decodeImage(bytes);

      final ByteData? raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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

    return Color.fromARGB(aAvg, rAvg, gAvg, bAvg);
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