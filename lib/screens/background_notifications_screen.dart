import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';
import 'dart:convert';

class BackgroundNotificationsScreen extends StatefulWidget {
  const BackgroundNotificationsScreen({super.key});

  @override
  State<BackgroundNotificationsScreen> createState() => _BackgroundNotificationsScreenState();
}

class _BackgroundNotificationsScreenState extends State<BackgroundNotificationsScreen> {
  final BackgroundService _backgroundService = BackgroundService();
  final NotificationService _notificationService = NotificationService();
  List<Map<String, dynamic>> _storedNotifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStoredNotifications();
  }

  Future<void> _loadStoredNotifications() async {
    setState(() => _isLoading = true);
    try {
      final notifications = await _backgroundService.getStoredNotifications();
      setState(() {
        _storedNotifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notifications: $e')),
        );
      }
    }
  }

  Future<void> _clearStoredNotifications() async {
    try {
      await _backgroundService.clearStoredNotifications();
      setState(() {
        _storedNotifications = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stored notifications cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing notifications: $e')),
        );
      }
    }
  }

  Future<void> _testBackgroundNotification() async {
    try {
      await _notificationService.showNotification(
        title: 'Test Background Notification',
        body: 'This is a test notification from background service',
        payload: jsonEncode({
          'type': 'test',
          'data': 'test_payload',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test notification sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending test notification: $e')),
        );
      }
    }
  }

  Future<void> _startBackgroundWebSocket() async {
    try {
      await _backgroundService.startBackgroundWebSocket();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Background WebSocket started')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting background WebSocket: $e')),
        );
      }
    }
  }

  Future<void> _startBackgroundService() async {
    try {
      await _backgroundService.startBackgroundService();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Background service started')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting background service: $e')),
        );
      }
    }
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Background Notifications',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _loadStoredNotifications,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D47A1),
              Color(0xFF1565C0),
              Color(0xFF1976D2),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Test Controls
                Card(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Test Controls',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _testBackgroundNotification,
                                icon: const Icon(Icons.notifications),
                                label: const Text('Test Notification'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _startBackgroundWebSocket,
                                icon: const Icon(Icons.wifi),
                                label: const Text('Start WebSocket'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _startBackgroundService,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Background Service'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Stored Notifications
                Expanded(
                  child: Card(
                    color: Colors.white.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Stored Notifications',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _clearStoredNotifications,
                                icon: const Icon(Icons.clear_all, color: Colors.white),
                                label: const Text('Clear All', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                : _storedNotifications.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No stored notifications',
                                          style: TextStyle(color: Colors.white70),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _storedNotifications.length,
                                        itemBuilder: (context, index) {
                                          final notification = _storedNotifications[index];
                                          return Card(
                                            color: Colors.white.withValues(alpha: 0.05),
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: ListTile(
                                              title: Text(
                                                notification['title'] ?? 'Unknown',
                                                style: const TextStyle(color: Colors.white),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    notification['body'] ?? 'No content',
                                                    style: const TextStyle(color: Colors.white70),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Type: ${notification['type'] ?? 'unknown'}',
                                                    style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Time: ${_formatTimestamp(notification['timestamp'] ?? 0)}',
                                                    style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              trailing: IconButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _storedNotifications.removeAt(index);
                                                  });
                                                },
                                                icon: const Icon(Icons.delete, color: Colors.red),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 