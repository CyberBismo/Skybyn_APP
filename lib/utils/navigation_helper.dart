import 'package:flutter/material.dart';
import '../services/navigation_service.dart';

/// Helper class for navigation that automatically saves the route
class NavigationHelper {
  /// Navigate to a route and save it
  static Future<T?> pushNamed<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    NavigationService.saveLastRoute(routeName);
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }
  
  /// Replace current route and save it
  static Future<T?> pushReplacementNamed<T extends Object?, TO extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    TO? result,
  }) {
    NavigationService.saveLastRoute(routeName);
    return Navigator.of(context).pushReplacementNamed<T, TO>(
      routeName,
      arguments: arguments,
      result: result,
    );
  }
  
  /// Push a route (for secondary screens like profile, settings)
  static Future<T?> push<T extends Object?>(
    BuildContext context,
    Widget screen,
    String routeName,
  ) {
    // Don't save route for push (secondary screens)
    // Only save for pushReplacement (main screens)
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (context) => screen),
    );
  }
  
  /// Replace current route with a new screen and save it
  static Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    BuildContext context,
    Widget screen,
    String routeName, {
    TO? result,
  }) {
    NavigationService.saveLastRoute(routeName);
    return Navigator.of(context).pushReplacement<T, TO>(
      MaterialPageRoute(builder: (context) => screen),
      result: result,
    );
  }
}

