import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../widgets/custom_snack_bar.dart';
import '../widgets/background_gradient.dart';
import 'background_notifications_screen.dart';

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.initialize();
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Test'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: BackgroundGradient(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.showNotification(
                        title: 'Basic Test',
                        body: 'This is a basic test notification',
                        payload: 'basic_test',
                      );
                      CustomSnackBar.show(context, 'Basic notification sent! Check your notification center.');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test Basic Notification',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.showNotification(
                        title: 'Admin Alert',
                        body: 'Important system notification from admin',
                        payload: 'admin_test',
                      );
                      CustomSnackBar.show(context, 'Admin notification sent!');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test Admin Notification',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.showNotification(
                        title: 'New Feature!',
                        body: 'Check out our latest feature update',
                        payload: 'feature_test',
                      );
                      CustomSnackBar.show(context, 'Feature notification sent!');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test Feature Notification',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.showNotification(
                        title: 'Maintenance Alert',
                        body: 'Scheduled maintenance in 30 minutes',
                        payload: 'maintenance_test',
                      );
                      CustomSnackBar.show(context, 'Maintenance notification sent!');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test Maintenance Notification',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.showScheduledNotification(
                        title: 'Scheduled Test',
                        body: 'This notification was scheduled for 5 seconds from now',
                        scheduledDate: DateTime.now().add(const Duration(seconds: 5)),
                        payload: 'scheduled_test',
                      );
                      CustomSnackBar.show(context, 'Scheduled notification set for 5 seconds!');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test Scheduled Notification (5s)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.showNotification(
                        title: 'Test Suite - Basic',
                        body: 'Basic notification test',
                        payload: 'test_suite_basic',
                      );
                      await Future.delayed(const Duration(milliseconds: 500));
                      await _notificationService.showNotification(
                        title: 'Test Suite - Admin',
                        body: 'Admin notification test',
                        payload: 'test_suite_admin',
                      );
                      await Future.delayed(const Duration(milliseconds: 500));
                      await _notificationService.showNotification(
                        title: 'Test Suite - Feature',
                        body: 'Feature notification test',
                        payload: 'test_suite_feature',
                      );
                      await Future.delayed(const Duration(milliseconds: 500));
                      await _notificationService.showNotification(
                        title: 'Test Suite - Maintenance',
                        body: 'Maintenance notification test',
                        payload: 'test_suite_maintenance',
                      );
                      CustomSnackBar.show(context, 'All notification types sent!');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test All Notification Types',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          title: const Text(
                            'Test Foreground Notification',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: const Text(
                            'This will show a notification even when the app is in the foreground. You should see it as a banner at the top of the screen.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await _notificationService.showNotification(
                                  title: 'Foreground Test',
                                  body: 'This notification should appear even when the app is open',
                                  payload: 'foreground_test',
                                );
                                CustomSnackBar.show(context, 'Foreground notification sent!');
                              },
                              child: const Text(
                                'Send',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      );
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Test Foreground Notification',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _notificationService.cancelAllNotifications();
                      CustomSnackBar.show(context, 'All notifications cancelled!');
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Cancel All Notifications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final pendingNotifications = await _notificationService.getPendingNotifications();
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          title: const Text(
                            'Pending Notifications',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: Text(
                            'You have ${pendingNotifications.length} pending notifications.',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'OK',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    } catch (e) {
                      CustomSnackBar.show(context, 'Error: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Check Pending Notifications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackgroundNotificationsScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    'Background Notifications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20.0),
                const Text(
                  'Note: Notifications may appear differently on iOS vs Android. On iOS, you may need to check the notification center.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 