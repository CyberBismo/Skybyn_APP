import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/friend.dart';
import 'auth_service.dart';

class ChatBubbleService {
  static final ChatBubbleService _instance = ChatBubbleService._internal();
  factory ChatBubbleService() => _instance;
  ChatBubbleService._internal();

  static const _channel = MethodChannel('no.skybyn.app/bubble');

  Future<bool> isPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    return await Permission.systemAlertWindow.isGranted;
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.systemAlertWindow.request();
    debugPrint('[Bubble] systemAlertWindow permission status: $status');
    return status.isGranted;
  }

  Future<void> showBubble({required Friend friend, int unreadCount = 1}) async {
    if (!Platform.isAndroid) return;
    final granted = await isPermissionGranted();
    debugPrint('[Bubble] showBubble called — permission granted: $granted');
    if (!granted) {
      debugPrint('[Bubble] No overlay permission — requesting now');
      await requestPermission();
      return;
    }
    final authService = AuthService();
    final sessionToken = await authService.getStoredSessionToken() ?? '';
    final userId = await authService.getStoredUserId() ?? '';
    try {
      final result = await _channel.invokeMethod<bool>('showBubble', {
        'friendId': friend.id,
        'friendName': friend.nickname.isNotEmpty ? friend.nickname : friend.username,
        'friendAvatar': friend.avatar,
        'unreadCount': unreadCount,
        'sessionToken': sessionToken,
        'userId': userId,
      });
      debugPrint('[Bubble] showBubble result: $result');
    } catch (e) {
      debugPrint('[Bubble] showBubble error: $e');
    }
  }

  Future<void> closeBubble({required String friendId}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('dismissBubble', {'friendId': friendId});
    } catch (_) {}
  }

  // Called from main.dart on resume — checks if a bubble tap opened the app to a specific chat.
  Future<String?> getPendingChatOpen() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getPendingChatOpen');
    } catch (_) {
      return null;
    }
  }

  void listenForOverlayActions() {}
  void dispose() {}
}
