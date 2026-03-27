import 'package:workmanager/workmanager.dart';
import 'auto_update_service.dart';

class BackgroundUpdateScheduler {
  static final BackgroundUpdateScheduler _instance = BackgroundUpdateScheduler._internal();
  factory BackgroundUpdateScheduler() => _instance;
  BackgroundUpdateScheduler._internal();

  static const String _checkUpdateTask = 'checkForUpdates';

  /// Initialize the background update scheduler
  Future<void> initialize() async {
    try {
      await _registerDailyUpdateCheck();
    } catch (e) {
      // WorkManager registration failed silently
    }
  }

  /// Register a daily WorkManager task to check for updates
  Future<void> _registerDailyUpdateCheck() async {
    await Workmanager().registerPeriodicTask(
      _checkUpdateTask,
      _checkUpdateTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
      ),
      initialDelay: const Duration(minutes: 5),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Manually trigger an update check (called from settings or notification tap)
  Future<void> triggerUpdateCheck() async {
    await AutoUpdateService.triggerBackgroundUpdate();
  }
}
