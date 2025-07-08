import 'package:flutter/material.dart';

class BackgroundGradient extends StatelessWidget {
  final Widget? child;
  const BackgroundGradient({Key? key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final lightColors = [
      const Color(0xFF4169E1), // Royal Blue
      const Color(0xFFADD8E6), // Light Blue
    ];

    final darkColors = [
      const Color(0xFF021024), // Almost black
      const Color(0xFF4169E1), // Midnight blue
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode ? darkColors : lightColors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
} 