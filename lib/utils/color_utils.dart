import 'package:flutter/material.dart';

class ColorUtils {
  /// Returns white or black based on the background color's luminance.
  /// If luminance < 0.5, returns white (dark background).
  /// If luminance >= 0.5, returns black (light background).
  static Color getContrastingColor(Color backgroundColor) {
    return backgroundColor.computeLuminance() < 0.5 ? Colors.white : Colors.black;
  }
}
