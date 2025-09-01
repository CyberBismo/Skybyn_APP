import 'package:flutter/material.dart';

class BackgroundGradient extends StatelessWidget {
  final Widget? child;
  const BackgroundGradient({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: child,
    );
  }
}