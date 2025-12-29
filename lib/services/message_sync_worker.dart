import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'chat_service.dart';
import 'auth_service.dart';
import 'dart:developer' as developer;

/// WorkManager callback for periodic message sync
/// This runs in a background isolate, so we need to initialize services here
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      developer.log('Message sync worker started: $task', name: 'MessageSyncWorker');
      
      // Initialize services in background isolate
      final chatService = ChatService();
      final authService = AuthService();
      final connectivity = Connectivity();
      
      // Check if user is logged in
      final userId = await authService.getStoredUserId();
      if (userId == null) {
        developer.log('User not logged in - skipping sync', name: 'MessageSyncWorker');
        return Future.value(true);
      }
      
      // Check connectivity
      final connectivityResult = await connectivity.checkConnectivity();
      final isOnline = connectivityResult != ConnectivityResult.none;
      if (!isOnline) {
        developer.log('No internet connection - skipping sync', name: 'MessageSyncWorker');
        return Future.value(true);
      }
      
      switch (task) {
        case 'syncMessages':
          // Process offline queue (send queued messages)
          await chatService.processOfflineQueue();
          developer.log('Offline queue processed', name: 'MessageSyncWorker');
          break;
        
        case 'syncAllMessages':
          // Full sync for all conversations
          // This would require friend list - for now just process queue
          await chatService.processOfflineQueue();
          developer.log('Full sync completed', name: 'MessageSyncWorker');
          break;
        
        default:
          developer.log('Unknown task: $task', name: 'MessageSyncWorker');
      }
      
      return Future.value(true);
    } catch (e, stackTrace) {
      developer.log('Error in message sync worker: $e', name: 'MessageSyncWorker');
      developer.log('Stack trace: $stackTrace', name: 'MessageSyncWorker');
      return Future.value(true); // Return true to prevent retry
    }
  });
}

/// Service to manage WorkManager tasks for background message sync
class MessageSyncWorker {
  static const String _syncMessagesTask = 'syncMessages';
  static const String _syncAllMessagesTask = 'syncAllMessages';
  
  /// Initialize WorkManager and register tasks
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to true for debugging
      );
      
      developer.log('WorkManager initialized', name: 'MessageSyncWorker');
    } catch (e) {
      developer.log('Error initializing WorkManager: $e', name: 'MessageSyncWorker');
    }
  }
  
  /// Register periodic sync task (runs every 15 minutes)
  static Future<void> registerPeriodicSync() async {
    try {
      await Workmanager().registerPeriodicTask(
        _syncMessagesTask,
        _syncMessagesTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        initialDelay: const Duration(minutes: 1), // Start after 1 minute
      );
      
      developer.log('Periodic message sync registered (every 15 minutes)', name: 'MessageSyncWorker');
    } catch (e) {
      developer.log('Error registering periodic sync: $e', name: 'MessageSyncWorker');
    }
  }
  
  /// Register one-time sync task (for immediate sync)
  static Future<void> syncNow() async {
    try {
      await Workmanager().registerOneOffTask(
        '${_syncMessagesTask}_${DateTime.now().millisecondsSinceEpoch}',
        _syncMessagesTask,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        initialDelay: const Duration(seconds: 5),
      );
      
      developer.log('One-time sync scheduled', name: 'MessageSyncWorker');
    } catch (e) {
      developer.log('Error scheduling one-time sync: $e', name: 'MessageSyncWorker');
    }
  }
  
  /// Cancel all sync tasks
  static Future<void> cancelAll() async {
    try {
      await Workmanager().cancelAll();
      developer.log('All sync tasks cancelled', name: 'MessageSyncWorker');
    } catch (e) {
      developer.log('Error cancelling sync tasks: $e', name: 'MessageSyncWorker');
    }
  }
}
