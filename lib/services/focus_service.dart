import 'package:flutter/material.dart';

/// A service to manage focus across the app and prevent SystemContextMenu conflicts
class FocusService {
  static final FocusService _instance = FocusService._internal();
  factory FocusService() => _instance;
  FocusService._internal();

  final List<FocusNode> _registeredFocusNodes = [];
  bool _isDisposed = false;

  /// Register a focus node to be managed by the service
  void registerFocusNode(FocusNode focusNode) {
    if (!_isDisposed && !_registeredFocusNodes.contains(focusNode)) {
      _registeredFocusNodes.add(focusNode);
    }
  }

  /// Unregister a focus node from the service
  void unregisterFocusNode(FocusNode focusNode) {
    _registeredFocusNodes.remove(focusNode);
  }

  /// Unfocus all registered focus nodes except the specified one
  void unfocusOthers(FocusNode? keepFocused) {
    for (final focusNode in _registeredFocusNodes) {
      if (focusNode != keepFocused && focusNode.hasFocus) {
        focusNode.unfocus();
      }
    }
  }

  /// Unfocus all registered focus nodes
  void unfocusAll() {
    for (final focusNode in _registeredFocusNodes) {
      if (focusNode.hasFocus) {
        focusNode.unfocus();
      }
    }
  }

  /// Get the currently focused node
  FocusNode? getCurrentFocus() {
    for (final focusNode in _registeredFocusNodes) {
      if (focusNode.hasFocus) {
        return focusNode;
      }
    }
    return null;
  }

  /// Check if any registered focus node has focus
  bool get hasAnyFocus {
    return _registeredFocusNodes.any((node) => node.hasFocus);
  }

  /// Dispose the service and all registered focus nodes
  void dispose() {
    _isDisposed = true;
    for (final focusNode in _registeredFocusNodes) {
      focusNode.dispose();
    }
    _registeredFocusNodes.clear();
  }

  /// Clear all registered focus nodes without disposing them
  void clear() {
    _registeredFocusNodes.clear();
  }
}

/// A mixin to easily add focus management to widgets
mixin FocusManagerMixin<T extends StatefulWidget> on State<T> {
  final FocusService _focusService = FocusService();
  final List<FocusNode> _localFocusNodes = [];

  /// Register a focus node with the service
  void registerFocusNode(FocusNode focusNode) {
    _focusService.registerFocusNode(focusNode);
    _localFocusNodes.add(focusNode);
  }

  /// Unregister a focus node from the service
  void unregisterFocusNode(FocusNode focusNode) {
    _focusService.unregisterFocusNode(focusNode);
    _localFocusNodes.remove(focusNode);
  }

  /// Unfocus all other focus nodes except the specified one
  void unfocusOthers(FocusNode? keepFocused) {
    _focusService.unfocusOthers(keepFocused);
  }

  /// Unfocus all focus nodes
  void unfocusAll() {
    _focusService.unfocusAll();
  }

  @override
  void dispose() {
    // Unregister all local focus nodes
    for (final focusNode in _localFocusNodes) {
      _focusService.unregisterFocusNode(focusNode);
    }
    _localFocusNodes.clear();
    super.dispose();
  }
} 