import 'package:flutter/material.dart';

class BackgroundGradient extends StatefulWidget {
  final Widget? child;
  const BackgroundGradient({super.key, this.child});

  @override
  State<BackgroundGradient> createState() => _BackgroundGradientState();
}

class _BackgroundGradientState extends State<BackgroundGradient> with TickerProviderStateMixin {
  late AnimationController _cloud1Controller;
  late AnimationController _cloud2Controller;
  late AnimationController _cloud3Controller;
  late Animation<double> _cloud1Animation;
  late Animation<double> _cloud2Animation;
  late Animation<double> _cloud3Animation;

  @override
  void initState() {
    super.initState();
    
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

    return Stack(
      children: [
        // Background gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode ? darkColors : lightColors,
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
} 