import 'package:flutter/material.dart';

class InAppNotificationService extends ChangeNotifier {
  static final InAppNotificationService _instance = InAppNotificationService._internal();
  factory InAppNotificationService() => _instance;
  InAppNotificationService._internal();

  bool _isVisible = false;
  String _title = '';
  String _body = '';

  bool get isVisible => _isVisible;
  String get title => _title;
  String get body => _body;

  void show(String title, String body) {
    _title = title;
    _body = body;
    _isVisible = true;
    notifyListeners();

    // Auto-hide after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      hide();
    });
  }

  void hide() {
    if (_isVisible) {
      _isVisible = false;
      notifyListeners();
    }
  }
}

